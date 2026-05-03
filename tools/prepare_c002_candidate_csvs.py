import argparse
import csv
import hashlib
import json
import re
import shutil
from collections import Counter
from pathlib import Path


CSV_FILES = [
    "c002-asset-mapping.csv",
    "c002-curriculum-standard.csv",
    "c002-exam-point.csv",
    "c002-external-ai-candidate.csv",
    "c002-formal-knowledge.csv",
    "c002-processing-summary.csv",
    "c002-textbook-chapter.csv",
]


def read_csv(path):
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader), list(reader.fieldnames or [])


def write_csv(path, rows, headers):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)


def split_multi(value):
    return [item.strip() for item in (value or "").split(";") if item.strip()]


def join_multi(values):
    return ";".join(values)


def slug_material_id(name, index):
    lower = name.lower()
    if "课程标准" in name:
        prefix = "curriculum"
    elif "教材" in name:
        prefix = "textbook"
    elif "年报" in name:
        prefix = "exam-report"
    elif "中考" in name:
        prefix = "local-exam"
    else:
        prefix = "source"

    year_match = re.search(r"(20\d{2})", name)
    year = f"-{year_match.group(1)}" if year_match else ""
    digest = hashlib.sha1(name.encode("utf-8")).hexdigest()[:8]
    return f"{prefix}{year}-{index:03d}-{digest}"


def infer_source_type(name):
    if "课程标准" in name:
        return "curriculum_standard"
    if "教材" in name:
        return "textbook"
    if "年报" in name:
        return "exam_analysis_report"
    if "中考" in name:
        return "local_exam_paper"
    return "unknown"


def infer_year(name):
    match = re.search(r"(20\d{2})", name)
    return int(match.group(1)) if match else None


def infer_grade_or_scope(name, source_type):
    if "八上" in name:
        return "grade_8_volume_1"
    if "八下" in name:
        return "grade_8_volume_2"
    if "九全" in name:
        return "grade_9_full"
    if source_type in {"local_exam_paper", "exam_analysis_report"}:
        return "grade_9"
    return "junior_middle_school"


def infer_region(name, source_type):
    if "广州" in name:
        return "Guangzhou"
    if source_type == "curriculum_standard":
        return "China"
    return ""


def infer_permissions(source_type):
    if source_type == "curriculum_standard":
        return "public_or_official_reference"
    return "pending_source_workbench_review"


def material_manifest(source_names):
    materials = []
    mapping = {}
    for index, name in enumerate(sorted(source_names), start=1):
        material_id = slug_material_id(name, index)
        source_type = infer_source_type(name)
        mapping[name] = material_id
        materials.append(
            {
                "materialId": material_id,
                "originalFileName": name,
                "sourceType": source_type,
                "title": Path(name).stem,
                "publisherOrAuthority": "pending_source_workbench_review",
                "editionOrVersion": "pending_source_workbench_review",
                "year": infer_year(name),
                "region": infer_region(name, source_type),
                "gradeOrScope": infer_grade_or_scope(name, source_type),
                "localPath": f"D:/KQG_Data/source_materials/staging/{name}",
                "sha256": "PENDING_SOURCE_UPLOAD_SHA256",
                "licenseOrPermission": infer_permissions(source_type),
                "sharingAllowed": False,
                "containsStudentPii": False,
                "anonymizationStatus": "not_applicable",
                "mayUseForKnowledgeExtraction": source_type in {"textbook", "curriculum_standard", "local_exam_paper"},
                "mayUseForExamPointExtraction": source_type in {"local_exam_paper", "exam_analysis_report"},
                "mayUseForTrendAnalysis": source_type in {"local_exam_paper", "exam_analysis_report"},
                "notes": "Generated from candidate CSV references. Replace sha256 after uploading the original file through the source material workbench.",
            }
        )

    return {
        "manifestVersion": "knowledge-source-materials.v1",
        "purpose": "C002 source-derived junior physics ontology candidate import",
        "subject": "physics",
        "stage": "junior_middle_school",
        "region": "Guangzhou",
        "reviewOwner": "pending_teacher_or_group_review",
        "materials": materials,
    }, mapping


def replace_material_refs(value, material_ids):
    refs = []
    for item in split_multi(value):
        refs.append(material_ids.get(item, item))
    return join_multi(refs)


def collect_source_names(all_rows):
    names = set()
    for rows, _headers in all_rows.values():
        for row in rows:
            for field in ("source_material_ids", "source_files"):
                if field in row:
                    names.update(split_multi(row.get(field, "")))
    return names


def clean_curriculum(rows):
    fixes = []
    for row in rows:
        parent = row.get("parent_stable_id", "").strip()
        if parent.startswith("KPHY-"):
            row["parent_stable_id"] = ""
            if parent not in split_multi(row.get("knowledge_stable_ids", "")):
                refs = split_multi(row.get("knowledge_stable_ids", ""))
                refs.insert(0, parent)
                row["knowledge_stable_ids"] = join_multi(refs)
            note = row.get("notes", "").strip()
            suffix = "parent_stable_id cleared because original value was a knowledge_stable_id"
            row["notes"] = f"{note}; {suffix}" if note else suffix
            fixes.append(row["stable_id"])
    return fixes


def clean_mappings(rows):
    changed_related = []
    for row in rows:
        original = row.get("mapping_type", "").strip()
        if original == "related":
            row["mapping_type"] = "broader"
            note = row.get("notes", "").strip()
            suffix = "original_mapping_type=related; treated as broader candidate alignment for DB constraint compatibility; keep pending_review"
            row["notes"] = f"{note}; {suffix}" if note else suffix
            row["auto_apply_allowed"] = "false"
            row["review_status"] = "pending_review"
            row["rollback_required"] = "true"
            changed_related.append(row["mapping_id"])
    return changed_related


def build_trend_rows(mapping_rows):
    headers = [
        "stable_id",
        "title",
        "subject",
        "stage",
        "region",
        "year_range",
        "source_material_ids",
        "evidence_locations",
        "target_exam_point_ids",
        "confidence",
        "review_status",
        "production_eligible",
        "notes",
    ]
    rows = []
    for row in mapping_rows:
        if row.get("source_asset_type") != "trend_summary":
            continue
        rows.append(
            {
                "stable_id": row["source_stable_id"],
                "title": f"考情趋势观察 {row['source_stable_id']}",
                "subject": "physics",
                "stage": "junior_middle_school",
                "region": "Guangzhou",
                "year_range": "2016-2025",
                "source_material_ids": row.get("source_material_ids", ""),
                "evidence_locations": row.get("evidence_locations", ""),
                "target_exam_point_ids": row.get("target_stable_id", ""),
                "confidence": row.get("confidence", ""),
                "review_status": "pending_review",
                "production_eligible": "false",
                "notes": "candidate trend summary generated to make trend_summary mappings non-dangling",
            }
        )
    return rows, headers


def validate(cleaned):
    issues = []
    sets = {}
    for name, (rows, _headers) in cleaned.items():
        key = name.removeprefix("c002-").removesuffix(".csv").replace("-", "_")
        ids = set()
        for id_field in ("stable_id", "candidate_id", "mapping_id"):
            if rows and id_field in rows[0]:
                values = [row[id_field].strip() for row in rows if row.get(id_field, "").strip()]
                duplicates = [value for value, count in Counter(values).items() if count > 1]
                for duplicate in duplicates:
                    issues.append(f"{name}: duplicate {id_field}: {duplicate}")
                ids.update(values)
        sets[key] = ids

    knowledge = {row["stable_id"] for row in cleaned["c002-formal-knowledge.csv"][0]}
    curriculum = {row["stable_id"] for row in cleaned["c002-curriculum-standard.csv"][0]}
    exam = {row["stable_id"] for row in cleaned["c002-exam-point.csv"][0]}
    textbook = {row["stable_id"] for row in cleaned["c002-textbook-chapter.csv"][0]}
    trend = {row["stable_id"] for row in cleaned.get("c002-trend-summary.csv", ([], []))[0]}
    type_sets = {
        "knowledge_point": knowledge,
        "curriculum_standard_item": curriculum,
        "exam_point": exam,
        "textbook_chapter": textbook,
        "trend_summary": trend,
    }

    for name, (rows, headers) in cleaned.items():
        for row in rows:
            if "review_status" in headers and row.get("review_status") != "pending_review":
                issues.append(f"{name}: non-pending review_status for {row}")
            if "production_eligible" in headers and row.get("production_eligible") != "false":
                issues.append(f"{name}: production_eligible must stay false for {row}")

    for row in cleaned["c002-formal-knowledge.csv"][0]:
        for ref in split_multi(row.get("curriculum_refs", "")):
            if ref not in curriculum:
                issues.append(f"c002-formal-knowledge.csv: missing curriculum ref {ref} on {row['stable_id']}")
        for ref in split_multi(row.get("local_exam_refs", "")):
            if ref not in exam:
                issues.append(f"c002-formal-knowledge.csv: missing exam ref {ref} on {row['stable_id']}")

    for row in cleaned["c002-asset-mapping.csv"][0]:
        if row.get("mapping_type") not in {"equivalent", "split", "merge", "broader", "narrower", "renamed", "deprecated"}:
            issues.append(f"c002-asset-mapping.csv: invalid mapping_type {row.get('mapping_type')} on {row['mapping_id']}")
        for side in ("source", "target"):
            asset_type = row.get(f"{side}_asset_type")
            stable_id = row.get(f"{side}_stable_id")
            if asset_type in type_sets and stable_id not in type_sets[asset_type]:
                issues.append(f"c002-asset-mapping.csv: missing {side} ref {asset_type}:{stable_id} on {row['mapping_id']}")

    return issues


def report_text(stats, issues):
    lines = [
        "# C002 Candidate CSV Validation Report",
        "",
        "## Result",
        "",
        "Result: " + ("pass" if not issues else "fail"),
        "",
        "## Generated Files",
        "",
    ]
    for item in stats["generated_files"]:
        lines.append(f"- `{item}`")
    lines.extend([
        "",
        "## Fixes Applied",
        "",
        f"- Cleared curriculum `parent_stable_id` values that pointed to knowledge IDs: {stats['curriculum_parent_fixes']}",
        f"- Converted `mapping_type=related` to `broader` with notes and pending review: {stats['related_mapping_fixes']}",
        f"- Generated trend summary rows for dangling `trend_summary` mappings: {stats['trend_summary_rows']}",
        f"- Generated source material manifest entries: {stats['manifest_materials']}",
        "",
        "## Remaining Issues",
        "",
    ])
    if issues:
        lines.extend(f"- {issue}" for issue in issues)
    else:
        lines.append("- None for candidate import precheck. Activation still requires source upload hash verification and human review.")
    lines.extend([
        "",
        "## Database Boundary",
        "",
        "These files are suitable only for candidate/pending_review import. They must not be imported as active or production eligible assets.",
        "",
    ])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--report-path", required=True)
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    report_path = Path(args.report_path)
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    all_rows = {}
    for name in CSV_FILES:
        path = input_dir / name
        if not path.exists():
            raise FileNotFoundError(path)
        all_rows[name] = read_csv(path)

    manifest, material_ids = material_manifest(collect_source_names(all_rows))

    cleaned = {}
    curriculum_parent_fixes = []
    related_mapping_fixes = []
    for name, (rows, headers) in all_rows.items():
        rows = [dict(row) for row in rows]
        for row in rows:
            for field in ("source_material_ids", "source_files"):
                if field in row:
                    row[field] = replace_material_refs(row.get(field, ""), material_ids)
        if name == "c002-curriculum-standard.csv":
            curriculum_parent_fixes = clean_curriculum(rows)
        if name == "c002-asset-mapping.csv":
            related_mapping_fixes = clean_mappings(rows)
        cleaned[name] = (rows, headers)

    trend_rows, trend_headers = build_trend_rows(cleaned["c002-asset-mapping.csv"][0])
    if trend_rows:
        cleaned["c002-trend-summary.csv"] = (trend_rows, trend_headers)

    for name, (rows, headers) in cleaned.items():
        write_csv(output_dir / name, rows, headers)

    manifest_path = output_dir / "source-material-manifest.candidate.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    issues = validate(cleaned)
    stats = {
        "generated_files": sorted([path.name for path in output_dir.glob("*")]),
        "curriculum_parent_fixes": len(curriculum_parent_fixes),
        "related_mapping_fixes": len(related_mapping_fixes),
        "trend_summary_rows": len(trend_rows),
        "manifest_materials": len(manifest["materials"]),
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(report_text(stats, issues), encoding="utf-8")

    print(json.dumps({"status": "pass" if not issues else "fail", **stats, "issue_count": len(issues)}, ensure_ascii=False, indent=2))
    return 0 if not issues else 1


if __name__ == "__main__":
    raise SystemExit(main())
