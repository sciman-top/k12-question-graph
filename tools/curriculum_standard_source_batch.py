from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from pypdf import PdfReader


SCHEMA_VERSION = "curriculum-standard-source-batch.v1"
MANIFEST_VERSION = "knowledge-source-materials.v1"
STATE_FILE_NAME = "source-batch-state.json"
INVENTORY_FILE_NAME = "source-batch-inventory.json"
MANIFEST_BACKUP_SUFFIX = ".cek002.bak"


class SourceBatchError(RuntimeError):
    pass


@dataclass(frozen=True)
class MaterialFacts:
    material_id: str
    file_name: str
    size_bytes: int
    modified_at_utc: str
    sha256: str
    page_count: int
    text_character_count: int
    non_empty_page_count: int
    require_text_layer: bool = True


EXPECTED_MATERIAL = MaterialFacts(
    material_id="curriculum-physics-junior-2022-2025-revision",
    file_name="《义务教育物理课程标准·日常修订版》(2022年版2025年修订).pdf",
    size_bytes=1_689_021,
    modified_at_utc="2026-07-27T17:24:48.282099+00:00",
    sha256="e00a5665e7e17ea6bdd6236d9366c51c63bbe6cc0eabf83ac3d0a529c487dd8c",
    page_count=67,
    text_character_count=37_615,
    non_empty_page_count=67,
)

INVENTORY_FIELDS = (
    "materialId",
    "fileName",
    "sizeBytes",
    "modifiedAtUtc",
    "sha256",
    "pdfMagicValid",
    "pageCount",
    "textCharacterCount",
    "nonEmptyPageCount",
    "sourcePath",
    "destinationPath",
)


def utc_iso(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat(timespec="microseconds")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inspect_pdf(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise SourceBatchError(f"source PDF does not exist: {path}")
    with path.open("rb") as stream:
        if stream.read(5) != b"%PDF-":
            raise SourceBatchError(f"invalid PDF magic: {path}")

    try:
        reader = PdfReader(str(path))
        page_text = [page.extract_text() or "" for page in reader.pages]
    except Exception as exc:
        raise SourceBatchError(f"cannot inspect PDF {path}: {exc}") from exc

    stat = path.stat()
    return {
        "fileName": path.name,
        "sizeBytes": stat.st_size,
        "modifiedAtUtc": utc_iso(stat.st_mtime),
        "sha256": sha256_file(path),
        "pdfMagicValid": True,
        "pageCount": len(reader.pages),
        "textCharacterCount": sum(len(text) for text in page_text),
        "nonEmptyPageCount": sum(bool(text.strip()) for text in page_text),
    }


def validate_facts(inspected: dict[str, Any], expected: MaterialFacts) -> None:
    expected_values = {
        "fileName": expected.file_name,
        "sizeBytes": expected.size_bytes,
        "modifiedAtUtc": expected.modified_at_utc,
        "sha256": expected.sha256,
        "pageCount": expected.page_count,
        "textCharacterCount": expected.text_character_count,
        "nonEmptyPageCount": expected.non_empty_page_count,
    }
    drift = {
        key: {"expected": expected_value, "actual": inspected.get(key)}
        for key, expected_value in expected_values.items()
        if inspected.get(key) != expected_value
    }
    if drift:
        raise SourceBatchError(f"source fact drift: {json.dumps(drift, ensure_ascii=False, sort_keys=True)}")
    if expected.require_text_layer and (
        inspected["textCharacterCount"] < 1
        or inspected["nonEmptyPageCount"] != inspected["pageCount"]
    ):
        raise SourceBatchError("OCR text layer is missing from one or more PDF pages")


def resolve_inventory(
    source_path: Path,
    destination_root: Path,
    mode: str,
    expected: MaterialFacts,
) -> dict[str, Any]:
    source_path = source_path.resolve()
    destination_path = (destination_root / expected.file_name).resolve()
    if source_path.name != expected.file_name:
        raise SourceBatchError(
            f"source file name does not match fixed material identity: {source_path.name}"
        )
    if source_path == destination_path:
        raise SourceBatchError("source and destination paths must differ")

    source_exists = source_path.exists()
    destination_exists = destination_path.exists()
    if source_exists and destination_exists:
        raise SourceBatchError("both source and destination contain the curriculum standard PDF")

    expected_location = "destination" if mode in {"rollback", "rollback_dry_run"} else "source"
    current_path = destination_path if destination_exists else source_path
    current_location = "destination" if destination_exists else "source"
    if not current_path.exists():
        raise SourceBatchError("the fixed curriculum standard PDF is missing from both locations")
    if current_location != expected_location:
        raise SourceBatchError(
            f"mode {mode} requires the PDF at {expected_location}, found it at {current_location}"
        )

    inspected = inspect_pdf(current_path)
    validate_facts(inspected, expected)
    return {
        "materialId": expected.material_id,
        **inspected,
        "sourcePath": str(source_path),
        "destinationPath": str(destination_path),
        "currentLocation": current_location,
    }


def inventory_digest(inventory: dict[str, Any]) -> str:
    stable = {key: inventory[key] for key in INVENTORY_FIELDS}
    payload = json.dumps(stable, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def write_json_atomic(payload: Any, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            newline="\n",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as stream:
            json.dump(payload, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            temporary = Path(stream.name)
        temporary.replace(path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def write_csv_atomic(inventory: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8-sig",
            newline="",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as stream:
            writer = csv.DictWriter(stream, fieldnames=INVENTORY_FIELDS)
            writer.writeheader()
            writer.writerow({key: inventory[key] for key in INVENTORY_FIELDS})
            temporary = Path(stream.name)
        temporary.replace(path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def read_manifest(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SourceBatchError(f"cannot parse local source manifest {path}: {exc}") from exc
    if not isinstance(value, dict) or not isinstance(value.get("materials"), list):
        raise SourceBatchError("local source manifest must be an object with a materials array")
    if value.get("manifestVersion") != MANIFEST_VERSION:
        raise SourceBatchError(f"unsupported local manifest version: {value.get('manifestVersion')}")
    return value


def curriculum_manifest_entry(inventory: dict[str, Any]) -> dict[str, Any]:
    return {
        "materialId": inventory["materialId"],
        "sourceType": "curriculum_standard",
        "title": "义务教育物理课程标准 日常修订版",
        "publisherOrAuthority": "中华人民共和国教育部",
        "editionOrVersion": "2022_2025_revision",
        "year": 2025,
        "region": "China",
        "gradeOrScope": "junior_middle_school",
        "localPath": Path(inventory["destinationPath"]).as_posix(),
        "sha256": inventory["sha256"],
        "sizeBytes": inventory["sizeBytes"],
        "modifiedAtUtc": inventory["modifiedAtUtc"],
        "pageCount": inventory["pageCount"],
        "textLayer": {
            "present": True,
            "nonEmptyPageCount": inventory["nonEmptyPageCount"],
            "characterCount": inventory["textCharacterCount"],
            "extractor": "pypdf==6.14.2",
        },
        "licenseOrPermission": "user_authorized_local_knowledge_extraction",
        "sharingAllowed": False,
        "containsStudentPii": False,
        "anonymizationStatus": "not_applicable",
        "mayUseForKnowledgeExtraction": True,
        "mayUseForExamPointExtraction": False,
        "mayUseForTrendAnalysis": False,
        "notes": "Local source only. Candidate extraction requires evidence anchors and human review.",
    }


def prepare_manifest(path: Path, inventory: dict[str, Any]) -> dict[str, Any]:
    current = read_manifest(path)
    if current is None:
        current = {
            "manifestVersion": MANIFEST_VERSION,
            "purpose": "Curriculum standard evidence extraction",
            "subject": "physics",
            "stage": "junior_middle_school",
            "region": "China",
            "reviewOwner": "local_teacher_review_pending",
            "materials": [],
        }

    desired = curriculum_manifest_entry(inventory)
    matches = [item for item in current["materials"] if item.get("materialId") == inventory["materialId"]]
    if len(matches) > 1:
        raise SourceBatchError(f"duplicate materialId in local manifest: {inventory['materialId']}")
    if matches and matches[0] != desired:
        raise SourceBatchError(f"local manifest materialId conflict: {inventory['materialId']}")
    if not matches:
        current["materials"].append(desired)
    return current


def manifest_backup_path(manifest_path: Path) -> Path:
    return Path(f"{manifest_path}{MANIFEST_BACKUP_SUFFIX}")


def move_and_validate(
    source: Path,
    destination: Path,
    expected: MaterialFacts,
) -> dict[str, Any]:
    if not source.is_file():
        raise SourceBatchError(f"move source does not exist: {source}")
    if destination.exists():
        raise SourceBatchError(f"move destination conflict: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(destination))
    try:
        inspected = inspect_pdf(destination)
        validate_facts(inspected, expected)
        return inspected
    except Exception:
        if destination.exists() and not source.exists():
            source.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(destination), str(source))
        raise


def validate_rollback_state(
    state_path: Path,
    manifest_path: Path,
    inventory: dict[str, Any],
) -> dict[str, Any]:
    if not state_path.is_file():
        raise SourceBatchError(f"rollback state is missing: {state_path}")
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SourceBatchError(f"cannot parse rollback state {state_path}: {exc}") from exc
    if state.get("materialId") != inventory["materialId"]:
        raise SourceBatchError("rollback state materialId mismatch")
    if state.get("inventoryDigest") != inventory_digest(inventory):
        raise SourceBatchError("rollback state inventory digest mismatch")

    manifest = read_manifest(manifest_path)
    if manifest is None:
        raise SourceBatchError("local manifest is missing before rollback")
    matches = [item for item in manifest["materials"] if item.get("materialId") == inventory["materialId"]]
    if matches != [curriculum_manifest_entry(inventory)]:
        raise SourceBatchError("local manifest curriculum entry drifted after apply")

    backup_path = manifest_backup_path(manifest_path)
    existed_before = bool(state.get("manifestExistedBefore"))
    if existed_before != backup_path.is_file():
        raise SourceBatchError("local manifest backup state mismatch")
    return state


def apply_stage(
    inventory: dict[str, Any],
    manifest_path: Path,
    state_path: Path,
    external_inventory_path: Path,
    expected: MaterialFacts,
) -> None:
    manifest_path = manifest_path.resolve()
    backup_path = manifest_backup_path(manifest_path)
    if state_path.exists() or external_inventory_path.exists() or backup_path.exists():
        raise SourceBatchError("apply state already exists; validate or roll back the existing batch first")
    next_manifest = prepare_manifest(manifest_path, inventory)
    manifest_existed = manifest_path.is_file()
    if manifest_existed:
        backup_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(manifest_path, backup_path)

    source = Path(inventory["sourcePath"])
    destination = Path(inventory["destinationPath"])
    moved = False
    try:
        move_and_validate(source, destination, expected)
        moved = True
        write_json_atomic(next_manifest, manifest_path)
        write_json_atomic(
            {
                "schemaVersion": SCHEMA_VERSION,
                "materialId": inventory["materialId"],
                "inventoryDigest": inventory_digest(inventory),
                "manifestPath": str(manifest_path),
                "manifestExistedBefore": manifest_existed,
                "manifestBackupPath": str(backup_path) if manifest_existed else "",
                "sourcePath": inventory["sourcePath"],
                "destinationPath": inventory["destinationPath"],
            },
            state_path,
        )
        write_json_atomic(inventory, external_inventory_path)
    except Exception:
        if moved and destination.exists() and not source.exists():
            source.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(destination), str(source))
        if manifest_existed and backup_path.exists():
            shutil.copy2(backup_path, manifest_path)
        elif not manifest_existed and manifest_path.exists():
            manifest_path.unlink()
        for generated in (state_path, external_inventory_path):
            if generated.exists():
                generated.unlink()
        if backup_path.exists():
            backup_path.unlink()
        raise


def rollback_stage(
    inventory: dict[str, Any],
    manifest_path: Path,
    state_path: Path,
    external_inventory_path: Path,
    expected: MaterialFacts,
) -> None:
    state = validate_rollback_state(state_path, manifest_path, inventory)
    backup_path = manifest_backup_path(manifest_path)
    current_manifest = manifest_path.read_bytes()
    source = Path(inventory["sourcePath"])
    destination = Path(inventory["destinationPath"])
    moved = False
    try:
        move_and_validate(destination, source, expected)
        moved = True
        if state["manifestExistedBefore"]:
            shutil.copy2(backup_path, manifest_path)
        else:
            manifest_path.unlink()
        for generated in (state_path, external_inventory_path):
            if generated.exists():
                generated.unlink()
        if backup_path.exists():
            backup_path.unlink()
    except Exception:
        if moved and source.exists() and not destination.exists():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(source), str(destination))
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_bytes(current_manifest)
        raise


def build_report(
    inventory: dict[str, Any],
    mode: str,
    manifest_path: Path,
    hash_parity_checked: bool,
) -> dict[str, Any]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "status": "pass",
        "mode": mode,
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "materialId": inventory["materialId"],
        "physicalFileCount": 1,
        "sourceType": "curriculum_standard",
        "inventoryDigest": inventory_digest(inventory),
        "pdfIntegrityPass": True,
        "textLayerPass": inventory["nonEmptyPageCount"] == inventory["pageCount"],
        "hashParityChecked": hash_parity_checked,
        "hashParityPass": True if hash_parity_checked else None,
        "inventoryState": (
            "destination" if mode in {"apply", "rollback_dry_run"} else "source"
        ),
        "manifestPath": str(manifest_path.resolve()),
        "manifestUpdated": mode == "apply",
        "rollbackReady": mode in {"apply", "rollback_dry_run"},
        "databaseWrite": False,
        "fileStoreWrite": False,
        "c002ActiveWrite": False,
        "inventory": inventory,
        "rollback": (
            "Run the same wrapper with -Rollback. It restores only this PDF and the saved local manifest state."
        ),
        "completionBoundary": (
            "This report proves source inventory and reversible local staging only; it does not prove "
            "SourceDocument registration, curriculum extraction, review, or production activation."
        ),
    }


def run_stage(
    source_path: Path,
    destination_root: Path,
    mode: str,
    report_path: Path,
    inventory_csv_path: Path,
    manifest_path: Path,
    *,
    expected: MaterialFacts = EXPECTED_MATERIAL,
) -> dict[str, Any]:
    if mode not in {"dry_run", "apply", "rollback", "rollback_dry_run"}:
        raise ValueError(f"unsupported mode: {mode}")
    source_path = source_path.resolve()
    destination_root = destination_root.resolve()
    manifest_path = manifest_path.resolve()
    inventory = resolve_inventory(source_path, destination_root, mode, expected)
    state_path = destination_root.parent / STATE_FILE_NAME
    external_inventory_path = destination_root.parent / INVENTORY_FILE_NAME

    if mode == "dry_run":
        prepare_manifest(manifest_path, inventory)
    elif mode == "apply":
        apply_stage(inventory, manifest_path, state_path, external_inventory_path, expected)
    elif mode == "rollback_dry_run":
        validate_rollback_state(state_path, manifest_path, inventory)
    else:
        rollback_stage(inventory, manifest_path, state_path, external_inventory_path, expected)

    report = build_report(
        inventory,
        mode,
        manifest_path,
        hash_parity_checked=mode in {"apply", "rollback"},
    )
    write_json_atomic(report, report_path.resolve())
    write_csv_atomic(inventory, inventory_csv_path.resolve())
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Stage the fixed junior-physics curriculum standard PDF")
    parser.add_argument("--source-file", required=True)
    parser.add_argument("--destination-root", required=True)
    parser.add_argument("--manifest", required=True)
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
            Path(args.source_file),
            Path(args.destination_root),
            selected_mode,
            Path(args.report),
            Path(args.inventory_csv),
            Path(args.manifest),
        )
    except SourceBatchError as exc:
        print(json.dumps({"status": "blocked", "mode": selected_mode, "error": str(exc)}, ensure_ascii=False))
        return 2
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
