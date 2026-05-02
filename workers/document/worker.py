import argparse
import json
import pathlib
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--job-id", required=True)
    parser.add_argument("--relative-path", required=True)
    parser.add_argument("--file-root", required=True)
    parser.add_argument("--simulate-failure", action="store_true")
    args = parser.parse_args()

    if args.simulate_failure:
        print("simulated worker failure", file=sys.stderr)
        return 2

    file_root = pathlib.Path(args.file_root)
    target = file_root / pathlib.PurePosixPath(args.relative_path)
    if not target.exists():
        print(f"input file missing: {target}", file=sys.stderr)
        return 3

    print(
        json.dumps(
            {
                "status": "ok",
                "jobId": args.job_id,
                "relativePath": args.relative_path,
                "sizeBytes": target.stat().st_size,
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
