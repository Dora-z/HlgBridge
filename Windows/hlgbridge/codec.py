from __future__ import annotations
import ctypes as C
import os
from functools import lru_cache
from pathlib import Path
import sys
import numpy as np


def bundle_root() -> Path:
    return Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parents[2]))


@lru_cache(maxsize=1)
def library():
    override = os.environ.get("HLGBRIDGE_CODEC")
    name = "hlgcodec.dll" if sys.platform == "win32" else "libhlgcodec.dylib" if sys.platform == "darwin" else "libhlgcodec.so"
    path = Path(override) if override else bundle_root() / "native" / name
    if not path.is_file():
        raise RuntimeError("未找到 HDR 编码组件。请使用完整解压的应用目录，或重新构建原生库。")
    lib = C.CDLL(str(path))
    lib.hlg_encode.argtypes = [C.c_void_p, C.c_uint, C.c_uint, C.c_void_p, C.c_size_t, C.c_float,
                               C.POINTER(C.c_void_p), C.POINTER(C.c_size_t), C.c_void_p, C.c_size_t]
    lib.hlg_encode.restype = C.c_int
    lib.hlg_free.argtypes = [C.c_void_p]
    lib.hlg_free.restype = None
    lib.hlg_verify.argtypes = [C.c_void_p, C.c_size_t, C.POINTER(C.c_uint), C.POINTER(C.c_uint),
                               C.POINTER(C.c_float), C.c_void_p, C.c_size_t]
    lib.hlg_verify.restype = C.c_int
    return lib


def encode(linear: np.ndarray, jpeg: bytes) -> bytes:
    height, width = linear.shape[:2]
    rgba = np.ones((height, width, 4), dtype=np.float16)
    rgba[..., :3] = np.clip(linear, 0, 10000 / 203)
    raw = (C.c_ubyte * len(jpeg)).from_buffer_copy(jpeg)
    output = C.c_void_p()
    size = C.c_size_t()
    error = C.create_string_buffer(512)
    lib = library()
    if not lib.hlg_encode(rgba.ctypes.data, width, height, raw, len(jpeg), 1000.0,
                          C.byref(output), C.byref(size), error, len(error)):
        raise RuntimeError(error.value.decode("utf-8", errors="replace"))
    try:
        return C.string_at(output, size.value)
    finally:
        lib.hlg_free(output)


def verify(data: bytes) -> tuple[int, int, float]:
    raw = (C.c_ubyte * len(data)).from_buffer_copy(data)
    width, height, boost = C.c_uint(), C.c_uint(), C.c_float()
    error = C.create_string_buffer(512)
    if not library().hlg_verify(raw, len(data), C.byref(width), C.byref(height), C.byref(boost), error, len(error)):
        raise RuntimeError(error.value.decode("utf-8", errors="replace"))
    return width.value, height.value, boost.value
