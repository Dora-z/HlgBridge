import argparse
from pathlib import Path
from .core import Options, convert, scan
from .codec import verify

parser = argparse.ArgumentParser(description="HlgBridge Windows 批量转换")
parser.add_argument("source", type=Path)
parser.add_argument("output", type=Path, nargs="?")
parser.add_argument("--mode", choices=["both", "sdr", "hdr"], default="both")
parser.add_argument("--tone", choices=["camera", "subject", "highlight"], default="camera")
parser.add_argument("--keep-gps", action="store_true")
parser.add_argument("--assume-hlg", action="store_true")
parser.add_argument("--verify", action="store_true")
args = parser.parse_args()
if args.verify:
    print(verify(args.source.read_bytes()))
else:
    if args.output is None:
        parser.error("请提供输出目录。")
    args.output.mkdir(parents=True, exist_ok=True)
    files = scan([args.source])
    if not files:
        parser.error("未找到 HEIF 照片。")
    failed = False
    for path in files:
        try:
            result, note = convert(path, args.output, Options(mode=args.mode, tone=args.tone, keep_gps=args.keep_gps, assume_hlg=args.assume_hlg))
            print(*result, note, sep="\n")
        except Exception as exc:
            print(f"{path.name}: {exc}")
            failed = True
    raise SystemExit(int(failed))
