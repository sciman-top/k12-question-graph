from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from pypdf import PdfReader


YEARS = tuple(range(2015, 2026))
BATCH_KEY = "guangzhou-physics-2015-2025-20260726-v2"
SCHEMA_VERSION = "1.0"
INVENTORY_FIELDS = (
    "year",
    "fileName",
    "logicalRoles",
    "sizeBytes",
    "modifiedAtUtc",
    "sha256",
    "pdfMagicValid",
    "pageCount",
    "textCharacterCount",
    "sourcePath",
    "destinationPath",
)


class BatchStageError(RuntimeError):
    pass


@dataclass(frozen=True)
class SourceFile:
    path: Path
    location: str


def utc_iso(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def classify_file_name(file_name: str) -> tuple[int, list[str]]:
    if len(file_name) < 4 or not file_name[:4].isdigit():
        raise BatchStageError(f"cannot infer year from PDF name: {file_name}")
    year = int(file_name[:4])
    if year not in YEARS:
        raise BatchStageError(f"year outside 2015-2025: {file_name}")
    if "广州中考" not in file_name:
        raise BatchStageError(f"unexpected source name: {file_name}")

    if "年报" in file_name:
        return year, ["exam_year_report"]
    if "含答案" in file_name:
        return year, ["exam_paper", "answer_solution"]
    if any(marker in file_name for marker in ("参考答案", "答案", "解析版")):
        return year, ["answer_solution"]
    return year, ["exam_paper"]


def inspect_pdf(source: SourceFile, source_root: Path, destination_root: Path) -> dict[str, object]:
    path = source.path
    with path.open("rb") as stream:
        magic_valid = stream.read(5) == b"%PDF-"
    if not magic_valid:
        raise BatchStageError(f"invalid PDF magic: {path}")

    try:
        reader = PdfReader(str(path))
        page_count = len(reader.pages)
        text_character_count = sum(len(page.extract_text() or "") for page in reader.pages)
    except Exception as exc:
        raise BatchStageError(f"cannot inspect PDF {path}: {exc}") from exc
    if page_count < 1:
        raise BatchStageError(f"PDF has no pages: {path}")

    year, logical_roles = classify_file_name(path.name)
    source_path = source_root / path.name
    destination_path = destination_root / path.name
    stat = path.stat()
    return {
        "year": year,
        "fileName": path.name,
        "logicalRoles": logical_roles,
        "sizeBytes": stat.st_size,
        "modifiedAtUtc": utc_iso(stat.st_mtime),
        "sha256": sha256_file(path),
        "pdfMagicValid": True,
        "pageCount": page_count,
        "textCharacterCount": text_character_count,
        "sourcePath": str(source_path.resolve()),
        "destinationPath": str(destination_path.resolve()),
        "currentLocation": source.location,
    }


def discover_files(source_root: Path, destination_root: Path) -> list[SourceFile]:
    names = {
        path.name
        for root in (source_root, destination_root)
        if root.exists()
        for path in root.glob("*.pdf")
    }
    files: list[SourceFile] = []
    for name in sorted(names):
        source_path = source_root / name
        destination_path = destination_root / name
        if source_path.exists() and destination_path.exists():
            raise BatchStageError(f"source and destination both contain {name}")
        if source_path.exists():
            files.append(SourceFile(source_path, "source"))
        elif destination_path.exists():
            files.append(SourceFile(destination_path, "destination"))
    return files


def validate_inventory(inventory: list[dict[str, object]]) -> None:
    if len(inventory) != 32:
        raise BatchStageError(f"expected 32 physical PDFs, found {len(inventory)}")

    logical_counts = {role: 0 for role in ("exam_paper", "answer_solution", "exam_year_report")}
    coverage = {year: set() for year in YEARS}
    hashes: set[str] = set()
    for item in inventory:
        file_hash = str(item["sha256"])
        if file_hash in hashes:
            raise BatchStageError(f"duplicate PDF content in batch: {item['fileName']}")
        hashes.add(file_hash)
        year = int(item["year"])
        for role in item["logicalRoles"]:
            coverage[year].add(str(role))
            logical_counts[str(role)] += 1

    expected_roles = {"exam_paper", "answer_solution", "exam_year_report"}
    incomplete = {year: sorted(expected_roles - roles) for year, roles in coverage.items() if roles != expected_roles}
    if incomplete:
        raise BatchStageError(f"incomplete or unexpected yearly role coverage: {incomplete}")
    if logical_counts != {"exam_paper": 11, "answer_solution": 11, "exam_year_report": 11}:
        raise BatchStageError(f"unexpected logical role counts: {logical_counts}")


def inventory_digest(inventory: list[dict[str, object]]) -> str:
    stable_inventory = [{key: item[key] for key in INVENTORY_FIELDS} for item in inventory]
    payload = json.dumps(stable_inventory, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def assert_locations(inventory: list[dict[str, object]], expected: str) -> None:
    unexpected = [str(item["fileName"]) for item in inventory if item["currentLocation"] != expected]
    if unexpected:
        raise BatchStageError(f"expected every PDF at {expected}; unexpected files: {unexpected}")


def move_inventory(inventory: list[dict[str, object]], direction: str) -> list[str]:
    if direction not in {"apply", "rollback"}:
        raise ValueError(f"unsupported direction: {direction}")
    from_key, to_key = (
        ("sourcePath", "destinationPath") if direction == "apply" else ("destinationPath", "sourcePath")
    )
    moved: list[tuple[Path, Path, str]] = []
    try:
        for item in inventory:
            source = Path(str(item[from_key]))
            destination = Path(str(item[to_key]))
            if destination.exists():
                raise BatchStageError(f"destination conflict: {destination}")
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(source), str(destination))
            actual_hash = sha256_file(destination)
            if actual_hash != item["sha256"]:
                raise BatchStageError(f"hash changed while moving {item['fileName']}")
            moved.append((source, destination, str(item["sha256"])))
    except Exception:
        for original, moved_path, expected_hash in reversed(moved):
            if moved_path.exists() and not original.exists() and sha256_file(moved_path) == expected_hash:
                original.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(moved_path), str(original))
        raise
    return [str(item["fileName"]) for item in inventory]


def write_csv(inventory: Iterable[dict[str, object]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=INVENTORY_FIELDS)
        writer.writeheader()
        for item in inventory:
            row = {key: item[key] for key in INVENTORY_FIELDS}
            row["logicalRoles"] = "|".join(str(role) for role in item["logicalRoles"])
            writer.writerow(row)


def write_json(report: dict[str, object], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def run_stage(
    source_root: Path,
    destination_root: Path,
    mode: str,
    report_path: Path,
    inventory_csv_path: Path,
) -> dict[str, object]:
    source_root = source_root.resolve()
    destination_root = destination_root.resolve()
    if source_root == destination_root:
        raise BatchStageError("source and destination roots must differ")

    inventory = [inspect_pdf(item, source_root, destination_root) for item in discover_files(source_root, destination_root)]
    validate_inventory(inventory)
    before_digest = inventory_digest(inventory)
    expected_location = "destination" if mode in {"rollback", "rollback_dry_run"} else "source"
    assert_locations(inventory, expected_location)

    moved_files: list[str] = []
    if mode in {"apply", "rollback"}:
        moved_files = move_inventory(inventory, mode)
        after_inventory = [
            inspect_pdf(
                SourceFile(
                    Path(str(item["destinationPath"] if mode == "apply" else item["sourcePath"])),
                    "destination" if mode == "apply" else "source",
                ),
                source_root,
                destination_root,
            )
            for item in inventory
        ]
        if inventory_digest(after_inventory) != before_digest:
            reverse_direction = "rollback" if mode == "apply" else "apply"
            move_inventory(after_inventory, reverse_direction)
            raise BatchStageError("inventory digest changed after move")

    logical_counts = {
        role: sum(role in item["logicalRoles"] for item in inventory)
        for role in ("exam_paper", "answer_solution", "exam_year_report")
    }
    report: dict[str, object] = {
        "schemaVersion": SCHEMA_VERSION,
        "status": "pass",
        "mode": mode,
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "batchKey": BATCH_KEY,
        "sourceRoot": str(source_root),
        "destinationRoot": str(destination_root),
        "physicalFileCount": len(inventory),
        "logicalSourceCount": sum(logical_counts.values()),
        "logicalRoleCounts": logical_counts,
        "yearsCovered": list(YEARS),
        "inventoryDigest": before_digest,
        "pdfIntegrityPass": True,
        "hashParityChecked": mode in {"apply", "rollback"},
        "hashParityPass": True if mode in {"apply", "rollback"} else None,
        "inventoryState": "pre_operation",
        "movedFiles": moved_files,
        "inventory": inventory,
        "rollback": (
            "Run the same wrapper with -Rollback; it only moves PDFs from this batch destination back to the recorded source root."
        ),
        "completionBoundary": "This report proves source inventory and file staging only; it does not prove database import or teacher review.",
    }
    write_json(report, report_path)
    write_csv(inventory, inventory_csv_path)
    if mode == "apply":
        write_json(report, destination_root.parent / "source-batch-inventory.json")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Stage the Guangzhou physics 2015-2025 source PDF batch")
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--destination-root", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--inventory-csv", required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--rollback", action="store_true")
    mode.add_argument("--validate-rollback", action="store_true")
    args = parser.parse_args()

    selected_mode = (
        "apply"
        if args.apply
        else "rollback"
        if args.rollback
        else "rollback_dry_run"
        if args.validate_rollback
        else "dry_run"
    )
    try:
        report = run_stage(
            Path(args.source_root),
            Path(args.destination_root),
            selected_mode,
            Path(args.report),
            Path(args.inventory_csv),
        )
    except BatchStageError as exc:
        print(json.dumps({"status": "blocked", "mode": selected_mode, "error": str(exc)}, ensure_ascii=False))
        return 2
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
