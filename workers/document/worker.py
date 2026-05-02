import argparse
import hashlib
import json
import pathlib
import platform
import sys
import time


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_json(value: dict) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def read_text_preview(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf-8")[:500]
    except UnicodeDecodeError:
        return ""


def build_document_model(job_id: str, relative_path: str, target: pathlib.Path) -> dict:
    preview = read_text_preview(target)
    block = {
        "id": "block_0001",
        "pageNumber": 1,
        "blockType": "raw_document",
        "textPreview": preview,
        "sourceRegion": None,
    }

    return {
        "schemaVersion": "document-model.v0.1",
        "jobId": job_id,
        "source": {
            "relativePath": relative_path,
            "inputSha256": sha256_file(target),
            "sizeBytes": target.stat().st_size,
        },
        "pages": [
            {
                "pageNumber": 1,
                "width": None,
                "height": None,
                "unit": "unknown",
                "layoutBlocks": [block],
            }
        ],
    }


def main() -> int:
    started = time.perf_counter()
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

    document_model = build_document_model(args.job_id, args.relative_path, target)
    output_sha256 = sha256_json(document_model)
    elapsed_ms = int((time.perf_counter() - started) * 1000)
    diagnostics = [
        {
            "adapterName": "placeholder_document_adapter",
            "adapterVersion": "0.1",
            "toolName": "python",
            "toolVersion": platform.python_version(),
            "commandArgs": {
                "relativePath": args.relative_path,
                "simulateFailure": args.simulate_failure,
            },
            "durationMs": elapsed_ms,
            "inputSha256": document_model["source"]["inputSha256"],
            "outputSha256": output_sha256,
            "warnings": [
                "placeholder adapter: no Docling/OpenXML/PaddleOCR parsing executed"
            ],
            "errors": [],
        }
    ]

    print(
        json.dumps(
            {
                "status": "ok",
                "jobId": args.job_id,
                "relativePath": args.relative_path,
                "sizeBytes": target.stat().st_size,
                "documentModel": document_model,
                "adapterDiagnostics": diagnostics,
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
