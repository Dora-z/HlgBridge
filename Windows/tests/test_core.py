import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import numpy as np
from PIL import Image
import piexif
import pillow_heif
from hlgbridge import core, codec


class CoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="HlgBridge-测试-")
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def fixture(self, *, hdr=True, orientation=1, unknown=False):
        path = self.root / "测试照片.HIF"
        array = np.zeros((32, 48, 3), dtype=np.uint16 if hdr else np.uint8)
        array[:, :24] = [55000, 40000, 30000] if hdr else [180, 120, 80]
        array[:, 24:] = [25000, 30000, 35000] if hdr else [80, 100, 150]
        exif = piexif.dump({"0th": {piexif.ImageIFD.Make: b"Synthetic", piexif.ImageIFD.Model: b"Test",
                                   piexif.ImageIFD.Orientation: orientation},
                            "Exif": {piexif.ExifIFD.DateTimeOriginal: b"2026:01:02 03:04:05",
                                     piexif.ExifIFD.ExposureTime: (1, 100)},
                            "GPS": {piexif.GPSIFD.GPSLatitudeRef: b"N", piexif.GPSIFD.GPSLatitude: ((10, 1), (0, 1), (0, 1))}})
        image = pillow_heif.from_bytes("RGB;16" if hdr else "RGB", (48, 32), array.tobytes())
        image.save(path, quality=95, exif=exif, save_nclx_profile=True,
                   color_primaries=2 if unknown else 9 if hdr else 1,
                   transfer_characteristics=2 if unknown else 18 if hdr else 13,
                   matrix_coefficients=9 if hdr else 1)
        return path

    def test_hlg_dual_output_native_decode_metadata_and_same_base(self, tone="natural"):
        path = self.fixture()
        original = path.read_bytes()
        self.assertEqual(core.inspect(path).kind, "hlg")
        files, _ = core.convert(path, self.root, core.Options(tone=tone))
        self.assertEqual(len(files), 2)
        self.assertEqual(codec.verify(files[1].read_bytes())[:2], (48, 32))
        base = np.asarray(Image.open(files[0]).convert("RGB"))
        hdr_base = np.asarray(Image.open(files[1]).convert("RGB"))
        np.testing.assert_array_equal(base, hdr_base)
        for file in files:
            metadata = piexif.load(str(file))
            self.assertFalse(metadata["GPS"])
            self.assertEqual(metadata["0th"][piexif.ImageIFD.Orientation], 1)
            self.assertEqual(metadata["Exif"][piexif.ExifIFD.DateTimeOriginal], b"2026:01:02 03:04:05")
        self.assertEqual(path.read_bytes(), original)
        self.assertIn(b"http://ns.adobe.com/hdr-gain-map/1.0/", files[1].read_bytes())
        self.assertIn(b"urn:iso:std:iso:ts:21496:-1", files[1].read_bytes())

    def test_sdr_does_not_create_hdr(self):
        path = self.fixture(hdr=False)
        self.assertEqual(core.inspect(path).kind, "sdr")
        files, note = core.convert(path, self.root)
        self.assertEqual(len(files), 1)
        self.assertTrue(note)
        with self.assertRaises(ValueError):
            core.convert(path, self.root, core.Options(mode="hdr"))

    def test_camera_highlight_dual_output_and_sdr_bypass(self):
        self.test_hlg_dual_output_native_decode_metadata_and_same_base(tone="camera-highlight")
        sdr = self.fixture(hdr=False)
        old, _ = core.convert(sdr, self.root, core.Options(mode="sdr", tone="camera"))
        new, _ = core.convert(sdr, self.root, core.Options(mode="sdr", tone="camera-highlight"))
        self.assertEqual(old[0].read_bytes(), new[0].read_bytes())

    def test_rotated_pixels_and_gps(self):
        path = self.fixture(orientation=6)
        files, _ = core.convert(path, self.root, core.Options(keep_gps=True))
        with Image.open(files[0]) as image:
            self.assertEqual(image.size, (32, 48))
        for file in files:
            self.assertTrue(piexif.load(str(file))["GPS"])

    def test_unknown_rejects_without_explicit_override(self):
        path = self.fixture(unknown=True)
        self.assertEqual(core.inspect(path).kind, "unknown")
        with self.assertRaisesRegex(ValueError, "未知"):
            core.convert(path, self.root)
        files, _ = core.convert(path, self.root, core.Options(mode="sdr", assume_hlg=True))
        self.assertEqual(len(files), 1)
        self.assertEqual(core._classify({"nclx_profile": {"color_primaries": 9, "transfer_characteristics": 16}})[0], "unknown")

    def test_corrupt_does_not_publish(self):
        path = self.root / "broken.HIF"
        path.write_bytes(b"broken")
        with self.assertRaises(Exception):
            core.convert(path, self.root)
        self.assertFalse(list(self.root.glob("*.jpg")))

    def test_duplicate_names_and_recursive_scanner(self):
        path = self.fixture(hdr=False)
        self.assertEqual(core.scan([path, self.root, path]), [path.resolve()])
        first, _ = core.convert(path, self.root, core.Options(mode="sdr"))
        saved = first[0].read_bytes()
        second, _ = core.convert(path, self.root, core.Options(mode="sdr"))
        self.assertTrue(second[0].stem.endswith("_1"))
        self.assertEqual(first[0].read_bytes(), saved)

    def test_cancel_during_conversion_cleans_staging(self):
        path = self.fixture()
        token = core.Cancellation()
        def progress(stage):
            if stage == "写入文件":
                token.cancel()
        with self.assertRaises(core.Cancelled):
            core.convert(path, self.root, cancellation=token, progress=progress)
        self.assertFalse(list(self.root.glob("*.jpg")))
        self.assertFalse(list(self.root.glob(".hlgbridge-*")))

    def test_cancel_after_first_publish_rolls_back_both(self):
        token = core.Cancellation()
        original_rename = os.rename if os.name == "nt" else os.link
        def publish_then_cancel(*args, **kwargs):
            result = original_rename(*args, **kwargs)
            token.cancel()
            return result
        with patch("os.rename" if os.name == "nt" else "os.link", side_effect=publish_then_cancel):
            with self.assertRaises(core.Cancelled):
                core._publish([("SDR", b"a"), ("HDR", b"b")], "test", self.root, token)
        self.assertFalse(list(self.root.iterdir()))

    def test_write_failure_cleans_staging(self):
        token = core.Cancellation()
        with patch("tempfile.mkstemp", side_effect=PermissionError("denied")):
            with self.assertRaises(PermissionError):
                core._publish([("SDR", b"a")], "test", self.root, token)
        self.assertFalse(list(self.root.iterdir()))

    def test_hlg_reference_levels_and_neutral_monotonicity(self):
        encoded = np.repeat(np.linspace(0, 1, 257, dtype=np.float32)[:, None], 3, axis=1)[None]
        linear = core.hlg_to_linear(encoded)
        self.assertTrue(np.isfinite(linear).all())
        np.testing.assert_allclose(linear[0, -1], 1000 / 203, rtol=1e-6)
        for tone in ["natural", "camera-highlight", "camera", "subject", "highlight"]:
            result = core.map_sdr(linear, core.Options(tone=tone))
            self.assertTrue(np.isfinite(result).all())
            self.assertGreaterEqual(float(np.min(np.diff(result[0, :, 0]))), -1e-6)
            self.assertTrue(np.all((result >= 0) & (result <= 1)))
            np.testing.assert_allclose(result[..., 0], result[..., 1], atol=1e-5)
            np.testing.assert_allclose(result[..., 1], result[..., 2], atol=1e-5)

    def test_camera_highlight_preserves_midtones_and_recovers_bright_steps(self):
        rgb = np.array([[[0, 0, 0], [0.02, 0.02, 0.02], [0.05, 0.05, 0.05],
                         [0.09, 0.09, 0.09], [0.04, 0.06, 0.05]]], np.float32)
        old = core.map_sdr(rgb, core.Options(tone="camera"))
        new = core.map_sdr(rgb, core.Options(tone="camera-highlight"))
        np.testing.assert_allclose(new, old, atol=1e-6)
        levels = np.array([0.3825, 0.5, 0.8334, 1, 2, 4.926, 10], np.float32)
        bright = np.repeat(levels[:, None], 3, axis=1)[None]
        protected = core.map_sdr(bright, core.Options(tone="camera-highlight"))
        self.assertTrue(np.all(np.diff(protected[0, :, 0]) > 0.001))
        self.assertTrue(np.all(protected < 0.999))
        self.assertGreater(float(protected[0, 4, 0] - protected[0, 3, 0]), 0.04)
        legacy = core.map_sdr(bright, core.Options(tone="camera"))
        np.testing.assert_allclose(legacy[0, -4:], 1, atol=1e-6)
        colors = np.array([[[4, 0.1, 0.1], [0.1, 4, 0.1], [0.1, 0.1, 4], [4, 3, 0.1]]], np.float32)
        mapped = core.map_sdr(colors, core.Options(tone="camera-highlight"))
        self.assertTrue(np.isfinite(mapped).all() and np.all((mapped >= 0) & (mapped <= 1)))

    def test_natural_retains_bright_detail_and_exposure_control(self):
        levels = np.array([0.5, 1.0, 2.0, 4.926], np.float32)
        image = np.repeat(levels[:, None], 3, axis=1)[None]
        normal = core.map_sdr(image, core.Options())
        darker = core.map_sdr(image, core.Options(exposure=-1))
        self.assertTrue(np.all(np.diff(normal[0, :, 0]) > 0.001))
        self.assertTrue(np.all(normal < 0.99))
        self.assertTrue(np.all(darker < normal))
        with self.assertRaises(ValueError):
            core.Options(exposure=float("nan")).validate()


if __name__ == "__main__":
    unittest.main()
