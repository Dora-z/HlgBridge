"""Run against the packaged .exe to check Qt and bundled HEVC/HDR native libraries."""
import json
from pathlib import Path
import tempfile
import traceback
import time
import faulthandler
import numpy as np
from PIL import Image
import pillow_heif
from .core import Options, convert
from .codec import verify


def run(report_path):
    result = {"success": False}
    fault_path = Path(report_path).with_suffix(".fault.log")
    fault = fault_path.open("w", encoding="utf-8")
    faulthandler.enable(file=fault)
    def checkpoint(stage):
        result["stage"] = stage
        Path(report_path).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        print("self-test: " + stage, flush=True)
    try:
        checkpoint("loading Qt")
        from .gui import create_application, Window, dispose_window
        app = create_application()
        checkpoint("creating window")
        window = Window()
        window.show()
        app.processEvents()
        checkpoint("window ready")
        assert window.tone.currentData() == "natural"
        window.tone.setCurrentIndex(window.tone.findData("camera-highlight"))
        assert window.options().tone == "camera-highlight"
        with tempfile.TemporaryDirectory(prefix="HlgBridge-检查-") as directory:
            root = Path(directory)
            pixels = np.full((32, 48, 3), 35000, dtype=np.uint16)
            source = root / "test.HIF"
            image = pillow_heif.from_bytes("RGB;16", (48, 32), pixels.tobytes())
            image.save(source, quality=90, save_nclx_profile=True, color_primaries=9,
                       transfer_characteristics=18, matrix_coefficients=9)
            checkpoint("native conversion")
            files, _ = convert(source, root, Options(tone="camera-highlight"))
            assert verify(files[-1].read_bytes())[:2] == (48, 32)
            with Image.open(files[0]) as opened:
                assert opened.size == (48, 32)
            checkpoint("importing preview")
            window.add_paths([source])
            assert window.tree.topLevelItemCount() == 1
            window.output = root
            window.refresh_controls()
            checkpoint("starting batch thread")
            window.run_batch()
            deadline = time.monotonic() + 20
            while window.running and time.monotonic() < deadline:
                app.processEvents()
                time.sleep(0.01)
            checkpoint("batch returned")
            assert not window.running, "Qt batch thread did not finish"
            assert "已导出 2" in window.tree.topLevelItem(0).text(2)
            assert (root / "test_HDR_1.jpg").is_file()
            checkpoint("waiting preview")
            window.pool.waitForDone()
            app.processEvents()
            checkpoint("closing window")
            dispose_window(window, app)
        checkpoint("done")
        result.update(success=True, qt=True, hevc_10_bit=True, ultra_hdr=True, qt_batch_thread=True)
    except Exception:
        result["error"] = traceback.format_exc()
    faulthandler.disable()
    fault.close()
    Path(report_path).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0 if result["success"] else 1
