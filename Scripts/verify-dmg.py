"""Mount the finished image and verify the layout and a simulated drag-install."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

from ds_store import DSStore

image = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="hlgbridge-dmg-") as temporary:
    mount = Path(temporary) / "mounted"
    mount.mkdir()
    subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                    "-mountpoint", str(mount), str(image)], check=True, stdout=subprocess.DEVNULL)
    try:
        assert sorted(p.name for p in mount.iterdir() if not p.name.startswith(".")) == [
            "Applications", "HlgBridge.app"]
        assert os.readlink(mount / "Applications") == "/Applications"
        assert (mount / ".background.tiff").is_file()
        with DSStore.open(str(mount / ".DS_Store"), "r") as store:
            assert store["HlgBridge.app"]["Iloc"] == (190, 220)
            assert store["Applications"]["Iloc"] == (570, 220)
            assert store["."]["icvp"]["backgroundType"] == 2
            assert store["."]["bwsp"]["WindowBounds"] == "{{180, 180}, {760, 440}}"
        app = mount / "HlgBridge.app"
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        installed = Path(temporary) / "Applications" / "HlgBridge.app"
        subprocess.run(["ditto", str(app), str(installed)], check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(installed)], check=True)
        info = plistlib.loads((installed / "Contents/Info.plist").read_bytes())
        assert info["CFBundleExecutable"] == "HlgBridge"
        print("DMG 验证通过：安装布局、应用程序快捷方式、挂载及复制后的应用签名。")
    finally:
        subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)
