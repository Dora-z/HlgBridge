from __future__ import annotations
from dataclasses import dataclass
import io
import os
from pathlib import Path
import tempfile
import threading
from typing import Callable
import numpy as np
from PIL import Image, ImageCms
import piexif
import pillow_heif
from . import codec

EXTENSIONS = {".hif", ".heif", ".heic"}
WEIGHTS = np.array([0.2627, 0.6780, 0.0593], np.float32)
BT2020_TO_709 = np.array([[1.660491, -0.587641, -0.072850],
                          [-0.124551, 1.132900, -0.008349],
                          [-0.018151, -0.100579, 1.118730]], np.float32)
P3_TO_709 = np.array([[1.22494, -0.22494, 0], [-0.042057, 1.042057, 0],
                      [-0.019638, -0.078636, 1.098274]], np.float32)
SRGB_ICC = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()


class Cancelled(Exception):
    pass


class Cancellation:
    def __init__(self):
        self.event = threading.Event()

    def cancel(self):
        self.event.set()

    def check(self):
        if self.event.is_set():
            raise Cancelled("已取消")


@dataclass(frozen=True)
class Options:
    mode: str = "both"
    tone: str = "natural"
    strength: float = 0.65
    exposure: float = 0.0
    keep_gps: bool = False
    assume_hlg: bool = False

    def validate(self):
        if self.mode not in {"sdr", "hdr", "both"} or self.tone not in {"natural", "camera-highlight", "camera", "subject", "highlight"}:
            raise ValueError("输出模式无效。")
        if not np.isfinite(self.exposure) or not -3 <= self.exposure <= 3:
            raise ValueError("曝光补偿应在 -3 到 +3 EV 之间。")
        if not np.isfinite(self.strength) or not 0 <= self.strength <= 1:
            raise ValueError("提亮强度应在 0–100% 之间。")


@dataclass
class Info:
    path: Path
    size: tuple[int, int]
    depth: int
    kind: str
    profile: str


def scan(paths) -> list[Path]:
    found = set()
    for value in paths:
        path = Path(value)
        if path.is_dir():
            for root, dirs, files in os.walk(path, followlinks=False):
                dirs[:] = sorted(d for d in dirs if not d.startswith("."))
                for name in files:
                    if Path(name).suffix.lower() in EXTENSIONS:
                        found.add((Path(root) / name).resolve())
        elif path.suffix.lower() in EXTENSIONS:
            found.add(path.resolve())
    return sorted(found, key=lambda p: str(p).casefold())


def _classify(metadata: dict) -> tuple[str, str]:
    nclx = metadata.get("nclx_profile") or {}
    primaries = nclx.get("color_primaries")
    transfer = nclx.get("transfer_characteristics")
    if primaries == 9 and transfer == 18:
        return "hlg", "BT.2100 HLG"
    if transfer in {16, 18}:
        return "unknown", f"不支持的 HDR 色彩标记 ({primaries}/{transfer})"
    icc = metadata.get("icc_profile")
    if icc:
        try:
            name = ImageCms.getProfileName(ImageCms.ImageCmsProfile(io.BytesIO(icc))).strip()
            if "hlg" in name.lower():
                return "hlg", name
            if "pq" in name.lower() or "log" in name.lower():
                return "unknown", name
            if any(text in name.lower() for text in ["srgb", "display p3", "adobe rgb", "bt.709"]):
                return "sdr", name
        except (OSError, ValueError, ImageCms.PyCMSError):
            pass
    if primaries in {1, 9, 12} and transfer in {1, 13, 14, 15}:
        return "sdr", f"SDR ({primaries}/{transfer})"
    return "unknown", "未知色彩"


def _open(path: Path):
    # Keep 10/12-bit samples at their original bit positions; never reduce HDR to 8 bits.
    image = pillow_heif.open_heif(path, convert_hdr_to_8bit=False, hdr_to_16bit=False)
    if image.size[0] <= 0 or image.size[1] <= 0 or image.size[0] * image.size[1] > 100_000_000:
        raise ValueError("照片尺寸无效或超过 1 亿像素。")
    if image.mode not in {"RGB", "RGBA", "RGB;10", "RGB;12", "RGB;16", "RGBA;10", "RGBA;12", "RGBA;16"}:
        raise ValueError(f"不支持的像素格式：{image.mode}")
    return image


def inspect(path: Path) -> Info:
    image = _open(path)
    kind, profile = _classify(image.info)
    return Info(path, image.size, image.info.get("bit_depth", 8), kind, profile)


def inverse_srgb(rgb):
    return np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)


def srgb_encode(rgb):
    rgb = np.clip(rgb, 0, 1)
    return np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * rgb ** (1 / 2.4) - 0.055)


def hlg_to_linear(encoded: np.ndarray) -> np.ndarray:
    a = np.float32(0.17883277)
    b = 1 - 4 * a
    c = 0.5 - a * np.log(4 * a)
    scene = np.where(encoded <= 0.5, encoded * encoded / 3, (np.exp((encoded - c) / a) + b) / 12)
    luminance = np.maximum(scene @ WEIGHTS, 0)
    # BT.2100 HLG: 1000-nit display, system gamma 1.2; SDR reference white 203 nits.
    return scene * luminance[..., None] ** np.float32(0.2) * np.float32(1000 / 203)


def map_sdr(linear: np.ndarray, options: Options) -> np.ndarray:
    linear = linear * np.float32(2 ** options.exposure)
    if options.tone == "natural":
        rgb = np.maximum(linear @ BT2020_TO_709.T, 0)
        y = rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32)
        target = 2 * y / (1 + 2 * y)
        gain = np.divide(target, y, out=np.full_like(y, 2.0), where=y > 1e-8)
        rgb *= gain[..., None]
        peak = np.max(rgb, axis=-1)
        chroma = np.minimum(1, np.divide(1 - target, np.maximum(peak - target, 1e-8)))
        rgb = target[..., None] + chroma[..., None] * (rgb - target[..., None])
        return srgb_encode(rgb)
    y = np.maximum(linear @ WEIGHTS, 0)
    if options.tone in {"camera", "camera-highlight"}:
        camera = 3.30 * y / (1 + 2.10 * y)
        if options.tone == "camera-highlight":
            knee = np.float32(0.70)
            target = np.where(camera <= knee, camera,
                              knee + (1 - knee) * -np.expm1(-np.maximum(camera - knee, 0) / (1 - knee)))
        else:
            target = np.minimum(camera, 1)
        black_gain = 3.30
    else:
        # Portable highlight-preserving rendition; not Apple's private system mapping.
        peak = np.float32(1000 / 203)
        target = y * (1 + y / (peak * peak)) / (1 + y)
        target = np.clip(target, 0, 1)
        if options.tone == "subject":
            target = target ** (1 - 0.6 * options.strength)
        black_gain = 0.0
    gain = np.divide(target, y, out=np.full_like(y, black_gain), where=y > 1e-8)
    rgb = (linear * gain[..., None]) @ BT2020_TO_709.T
    if options.tone == "camera-highlight":
        peak, low = np.max(rgb, axis=-1), np.min(rgb, axis=-1)
        chroma = np.minimum(1, (1 - target) / np.maximum(peak - target, 1e-8))
        chroma = np.minimum(chroma, target / np.maximum(target - low, 1e-8))
        rgb = target[..., None] + chroma[..., None] * (rgb - target[..., None])
    return srgb_encode(rgb)


def _exif(metadata: dict, size: tuple[int, int], keep_gps: bool) -> bytes:
    original = metadata.get("exif")
    parsed = {"0th": {}, "Exif": {}, "GPS": {}, "1st": {}, "thumbnail": None}
    if original:
        try:
            parsed = piexif.load(original)
        except (ValueError, OSError, piexif.InvalidImageDataError):
            pass
    tiff_names = ["Make", "Model", "DateTime", "Artist", "Copyright"]
    exif_names = ["DateTimeOriginal", "DateTimeDigitized", "OffsetTime", "OffsetTimeOriginal", "OffsetTimeDigitized", "SubSecTimeOriginal", "SubSecTimeDigitized", "ExposureTime", "FNumber", "ISOSpeedRatings", "ExposureProgram", "ExposureBiasValue", "MeteringMode", "Flash", "FocalLength", "FocalLengthIn35mmFilm", "LensMake", "LensModel", "WhiteBalance", "ExposureMode", "ApertureValue", "ShutterSpeedValue"]
    tiff_ids = {getattr(piexif.ImageIFD, name) for name in tiff_names if hasattr(piexif.ImageIFD, name)}
    exif_ids = {getattr(piexif.ExifIFD, name) for name in exif_names if hasattr(piexif.ExifIFD, name)}
    clean = {"0th": {k: v for k, v in parsed.get("0th", {}).items() if k in tiff_ids},
             "Exif": {k: v for k, v in parsed.get("Exif", {}).items() if k in exif_ids},
             "GPS": parsed.get("GPS", {}) if keep_gps else {}, "1st": {}, "thumbnail": None}
    clean["0th"].update({piexif.ImageIFD.Orientation: 1, piexif.ImageIFD.Software: b"HlgBridge 1.2 Windows"})
    clean["Exif"].update({piexif.ExifIFD.PixelXDimension: size[0], piexif.ExifIFD.PixelYDimension: size[1], piexif.ExifIFD.ColorSpace: 1})
    return piexif.dump(clean)


def _sdr_pixels(image, pixels: np.ndarray) -> np.ndarray:
    depth = image.info.get("bit_depth", 8)
    encoded = pixels.astype(np.float32) / ((1 << depth) - 1)
    icc = image.info.get("icc_profile")
    if icc:
        pil = Image.fromarray(np.uint8(np.clip(encoded, 0, 1) * 255 + 0.5))
        try:
            return np.asarray(ImageCms.profileToProfile(pil, ImageCms.ImageCmsProfile(io.BytesIO(icc)),
                                                       ImageCms.createProfile("sRGB"), outputMode="RGB"))
        except (OSError, ValueError, ImageCms.PyCMSError) as exc:
            raise ValueError("无法转换这张照片的 ICC 色彩配置。") from exc
    profile = image.info.get("nclx_profile") or {}
    transfer = profile.get("transfer_characteristics")
    if transfer == 13:
        linear = inverse_srgb(encoded)
    else:
        linear = np.where(encoded < 0.081, encoded / 4.5, ((encoded + 0.099) / 1.099) ** (1 / 0.45))
    primaries = profile.get("color_primaries")
    if primaries == 9:
        linear = linear @ BT2020_TO_709.T
    elif primaries == 12:
        linear = linear @ P3_TO_709.T
    return np.uint8(srgb_encode(linear) * 255 + 0.5)


def _decode(path: Path, options: Options, max_side: int | None = None):
    image = _open(path)
    metadata = dict(image.info)
    kind, _ = _classify(metadata)
    is_hdr = kind == "hlg" or (kind == "unknown" and options.assume_hlg)
    if kind == "unknown" and not options.assume_hlg:
        raise ValueError("色彩标记未知。确认是松下 HLG 后，勾选“按松下 HLG 处理”再重试。")
    pixels = np.asarray(image)[..., :3]
    if max_side:
        step = max(1, int(np.ceil(max(image.size) / max_side)))
        pixels = pixels[::step, ::step]
    linear = None
    if is_hdr:
        depth = image.info.get("bit_depth", 8)
        linear = hlg_to_linear(pixels.astype(np.float32) / ((1 << depth) - 1))
        sdr = np.uint8(map_sdr(linear, options) * 255 + 0.5)
    else:
        sdr = _sdr_pixels(image, pixels)
    # libheif already applies HEIF irot/imir transformations. pillow-heif synchronizes
    # Exif orientation with those transforms; don't apply the original tag twice.
    return sdr, linear, metadata


def preview(path: Path, options: Options) -> Image.Image:
    options.validate()
    pixels, _, _ = _decode(path, options, max_side=1200)
    image = Image.fromarray(pixels)
    image.info["icc_profile"] = SRGB_ICC
    return image


def _publish(items: list[tuple[str, bytes]], stem: str, directory: Path, cancellation: Cancellation) -> list[Path]:
    if not directory.is_dir():
        raise ValueError("输出目录不存在。")
    staging: list[Path] = []
    published: list[Path] = []
    try:
        for _, data in items:
            cancellation.check()
            fd, name = tempfile.mkstemp(prefix=".hlgbridge-", suffix=".tmp", dir=directory)
            path = Path(name)
            staging.append(path)
            with os.fdopen(fd, "wb") as output:
                output.write(data)
                output.flush()
                os.fsync(output.fileno())
        for index, (suffix, _) in enumerate(items):
            number = 0
            while True:
                cancellation.check()
                extra = f"_{number}" if number else ""
                target = directory / f"{stem}_{suffix}{extra}.jpg"
                try:
                    if os.name == "nt":
                        os.rename(staging[index], target)  # Windows never replaces an existing target.
                    else:
                        os.link(staging[index], target)
                        staging[index].unlink()
                    published.append(target)
                    break
                except FileExistsError:
                    number += 1
        cancellation.check()
        return published
    except BaseException:
        for path in published:
            path.unlink(missing_ok=True)
        raise
    finally:
        for path in staging:
            path.unlink(missing_ok=True)


def convert(path: Path, directory: Path, options: Options = Options(), cancellation: Cancellation | None = None,
            progress: Callable[[str], None] = lambda _: None) -> tuple[list[Path], str]:
    options.validate()
    cancellation = cancellation or Cancellation()
    cancellation.check()
    progress("解码及色彩转换")
    sdr, linear, metadata = _decode(path, options)
    cancellation.check()
    if linear is None and options.mode == "hdr":
        raise ValueError("这是 SDR 原片，不能生成真实 HDR。请选择普通 JPEG 或同时导出。")
    image = Image.fromarray(sdr)
    output = io.BytesIO()
    image.save(output, format="JPEG", quality=95, subsampling=1, icc_profile=SRGB_ICC,
               exif=_exif(metadata, image.size, options.keep_gps))
    jpeg = output.getvalue()
    items = []
    if options.mode != "hdr":
        items.append(("SDR", jpeg))
    cancellation.check()
    if linear is not None and options.mode != "sdr":
        progress("生成 HDR 增益图")
        cancellation.check()
        items.append(("HDR", codec.encode(linear, jpeg)))
    cancellation.check()
    progress("写入文件")
    files = _publish(items, path.stem, directory, cancellation)
    note = "SDR 原片：仅导出普通 JPEG。" if linear is None and options.mode == "both" else ""
    return files, note
