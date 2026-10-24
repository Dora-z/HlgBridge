"""Generate the Windows ICO and collect the licenses shipped with the portable app."""
from importlib import metadata
from pathlib import Path
import shutil
from PIL import Image

root = Path(__file__).resolve().parents[1]
out = root / ".build" / "windows-assets"
out.mkdir(parents=True, exist_ok=True)
with Image.open(root / "Assets" / "AppIcon.png") as image:
    image.save(out / "AppIcon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
licenses = out / "Licenses"
licenses.mkdir(exist_ok=True)
for dist in metadata.distributions():
    name = dist.metadata.get("Name", "")
    if name.lower().replace("_", "-") not in {"pillow", "pillow-heif", "numpy", "piexif", "shiboken6"} and not name.lower().startswith("pyside6"):
        continue
    for file in dist.files or []:
        if any(token in str(file).lower() for token in ["license", "copying", "copyright", "notice"]):
            source = Path(dist.locate_file(file))
            if source.is_file():
                target = licenses / name / str(file).replace("..", "_")
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
source = root / ".build" / "windows-native" / "_deps" / "ultrahdr-src"
for file in list(source.glob("LICENSE-*")) + list((source / "third_party" / "turbojpeg").glob("LICENSE.md")) + list((source / "third_party" / "turbojpeg").glob("README.ijg")):
    target = licenses / ("libjpeg-turbo-" + file.name if file.parent.name == "turbojpeg" else "libultrahdr-" + file.name)
    shutil.copy2(file, target)
shutil.copy2(root / "THIRD_PARTY_NOTICES.md", licenses / "THIRD_PARTY_NOTICES.md")
