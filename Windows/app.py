import sys

if __name__ == "__main__":
    if "--self-test" in sys.argv:
        import json
        from pathlib import Path
        import traceback
        index = sys.argv.index("--self-test")
        report = sys.argv[index + 1] if len(sys.argv) > index + 1 else "self-test.json"
        try:
            from hlgbridge.smoke import run
            sys.exit(run(report))
        except Exception:
            Path(report).write_text(json.dumps({"success": False, "error": traceback.format_exc()}), encoding="utf-8")
            sys.exit(1)
    from hlgbridge.gui import main
    sys.exit(main())
