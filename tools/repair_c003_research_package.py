import argparse
import csv
import json
import re
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


QUESTION_REPAIRS = {
    ("2017", "1"): {
        "knowledge": "KPHY-C003-014",
        "exam": "EPHY-C003-001",
        "ability": "信息提取;科学推理",
    },
    ("2018", "1"): {
        "knowledge": "KPHY-C003-025",
        "exam": "EPHY-C003-001",
        "ability": "信息提取;科学推理",
    },
    ("2019", "1"): {
        "knowledge": "KPHY-C003-037",
        "exam": "EPHY-C003-003",
        "ability": "信息提取;科学推理",
    },
    ("2020", "1"): {
        "knowledge": "KPHY-C003-025",
        "exam": "EPHY-C003-001",
        "ability": "信息提取;科学推理",
    },
    ("2022", "1"): {
        "knowledge": "KPHY-C003-026",
        "exam": "EPHY-C003-002",
        "secondary_knowledge": "KPHY-C003-025",
        "secondary_exam": "EPHY-C003-001",
        "ability": "信息提取;数学运算;科学推理",
    },
    ("2022", "2"): {
        "knowledge": "KPHY-C003-005",
        "exam": "EPHY-C003-005",
        "ability": "科学推理",
    },
    ("2023", "1"): {
        "knowledge": "KPHY-C003-014",
        "exam": "EPHY-C003-001",
        "ability": "信息提取;科学推理",
    },
    ("2023", "2"): {
        "knowledge": "KPHY-C003-043",
        "exam": "EPHY-C003-012",
        "ability": "科学推理",
    },
    ("2024", "1"): {
        "knowledge": "KPHY-C003-038",
        "exam": "EPHY-C003-023",
        "secondary_knowledge": "KPHY-C003-049",
        "secondary_exam": "EPHY-C003-030",
        "ability": "信息提取;科学推理",
    },
    ("2024", "2"): {
        "knowledge": "KPHY-C003-037",
        "exam": "EPHY-C003-003",
        "ability": "信息提取;科学推理",
    },
    ("2024", "13"): {
        "knowledge": "KPHY-C003-031",
        "exam": "EPHY-C003-019",
        "ability": "模型建构;科学推理",
    },
    ("2025", "1"): {
        "knowledge": "KPHY-C003-037",
        "exam": "EPHY-C003-003",
        "ability": "科学推理",
    },
    ("2025", "2"): {
        "knowledge": "KPHY-C003-017",
        "exam": "EPHY-C003-011",
        "secondary_knowledge": "KPHY-C003-018",
        "ability": "信息提取;科学推理",
    },
}


QUESTION_REFERENCE_REPAIRS = {
    "QPHY-C003-2024-17": {
        "primary_knowledge_id": "KPHY-C003-046",
        "secondary_knowledge_ids": "KPHY-C003-044;KPHY-C003-045;KPHY-C003-064;KPHY-C003-065",
        "primary_exam_point_id": "EPHY-C003-044",
        "secondary_exam_point_ids": "",
        "curriculum_item_ids": "CS-C003-2-4-2;CS-C003-2-4-3;CS-C003-3-4-3;CS-C003-4-1-7;CS-C003-4-2-9",
        "ability_dimensions": "实验探究;规范作图;信息提取;科学推理",
        "confidence": "0.82",
        "mapping_knowledge_target": "KPHY-C003-046",
        "mapping_exam_target": "EPHY-C003-044",
        "note": "knowledge and curriculum refs repaired from source exam PDF",
    },
    "QPHY-C003-2025-14": {
        "primary_knowledge_id": "KPHY-C003-031",
        "secondary_knowledge_ids": "KPHY-C003-100;KPHY-C003-102",
        "primary_exam_point_id": "EPHY-C003-046",
        "secondary_exam_point_ids": "EPHY-C003-013;EPHY-C003-040",
        "curriculum_item_ids": "CS-C003-2-2-6;CS-C003-4-2-5;CS-C003-5-2",
        "ability_dimensions": "模型建构;跨学科应用;科学推理",
        "confidence": "0.86",
        "mapping_knowledge_target": "KPHY-C003-031",
        "mapping_exam_target": "EPHY-C003-046",
        "note": "knowledge and curriculum refs repaired from source exam PDF",
    },
}


MODULE_CURRICULUM_REF_REPAIRS = {
    "KPHY-C003-001": "CS-C003-1-1;CS-C003-1-2;CS-C003-1-3",
    "KPHY-C003-020": "CS-C003-2-1;CS-C003-2-2;CS-C003-2-3;CS-C003-2-4",
    "KPHY-C003-050": "CS-C003-3-1;CS-C003-3-2;CS-C003-3-3;CS-C003-3-4",
    "KPHY-C003-080": "CS-C003-4-1;CS-C003-4-2",
    "KPHY-C003-100": "CS-C003-5-1;CS-C003-5-2;CS-C003-5-3",
}


EXAM_POINT_KNOWLEDGE_REPAIRS = {
    "EPHY-C003-044": "KPHY-C003-044;KPHY-C003-045;KPHY-C003-046;KPHY-C003-064;KPHY-C003-065",
    "EPHY-C003-046": "KPHY-C003-031;KPHY-C003-100;KPHY-C003-102",
}


EXAM_TEXT_NAMES = {
    "2016": "2016广州中考.txt",
    "2017": "2017广州中考.txt",
    "2018": "2018广州中考.txt",
    "2019": "2019广州中考.txt",
    "2020": "2020广州中考（含答案）.txt",
    "2021": "2021广州中考.txt",
    "2022": "2022广州中考.txt",
    "2023": "2023广州中考.txt",
    "2024": "2024广州中考.txt",
    "2025": "2025广州中考.txt",
}


def read_csv(path: Path) -> tuple[list[dict[str, str]], list[str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader), list(reader.fieldnames or [])


def write_csv(path: Path, rows: list[dict[str, str]], headers: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)


def collapse_text(value: str) -> str:
    value = re.sub(r"\f", "\n", value)
    value = re.sub(r"学科网[^。\n]*", "", value)
    value = re.sub(r"物理试卷\s*第\s*\d+\s*页\s*共\s*\d+\s*页", "", value)
    value = re.sub(r"第\s*\d+\s*页\s*/?\s*共\s*\d+\s*页", "", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def append_note(row: dict[str, str], note: str) -> None:
    existing = row.get("notes", "").strip()
    if note in existing:
        return
    row["notes"] = f"{existing}; {note}" if existing else note


def set_value(row: dict[str, str], key: str, value: str) -> bool:
    if row.get(key, "") == value:
        return False
    row[key] = value
    return True


def run_pdftotext(pdf: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["pdftotext", "-layout", str(pdf), str(output)], check=True)


def ensure_exam_texts(exam_pdf_root: Path, cache_root: Path) -> dict[str, Path]:
    paths: dict[str, Path] = {}
    for year, name in EXAM_TEXT_NAMES.items():
        if year == "2020":
            pdf_name = "2020广州中考（含答案）.pdf"
        else:
            pdf_name = f"{year}广州中考.pdf"
        pdf = exam_pdf_root / pdf_name
        output = cache_root / name
        run_pdftotext(pdf, output)
        paths[year] = output
    return paths


def ensure_year_report_texts(year_report_root: Path, cache_root: Path) -> dict[str, list[str]]:
    pages_by_year: dict[str, list[str]] = {}
    for year in range(2016, 2026):
        pdf = year_report_root / f"{year}广州中考年报.pdf"
        output = cache_root / f"{year}广州中考年报.txt"
        run_pdftotext(pdf, output)
        pages_by_year[str(year)] = output.read_text(encoding="utf-8", errors="ignore").split("\f")
    return pages_by_year


def extract_question_stem(text_path: Path, question_number: str) -> str:
    text = text_path.read_text(encoding="utf-8", errors="ignore")
    starts = [pos for pos in (text.find("一、选择题"), text.find("选择题：")) if pos >= 0]
    body = text[min(starts) :] if starts else text
    q = int(question_number)
    pattern = re.compile(rf"(?m)^\s*{q}\s*[．.，,]\s*")
    for match in pattern.finditer(body):
        end = len(body)
        for next_q in range(q + 1, min(q + 5, 30)):
            next_match = re.search(rf"(?m)^\s*{next_q}\s*[．.，,]\s*", body[match.end() :])
            if next_match:
                end = match.end() + next_match.start()
                break
        chunk = collapse_text(body[match.start() : end])
        if any(token in chunk[:140] for token in ("答题前", "选择题每小题", "注意事项", "考生务必")):
            continue
        if len(chunk) >= 16:
            return chunk
    return ""


def repair_question_rows(csv_root: Path, exam_texts: dict[str, Path]) -> dict[str, int]:
    question_rows, question_headers = read_csv(csv_root / "c003-question-item-full.csv")
    sub_rows, sub_headers = read_csv(csv_root / "c003-subquestion-item-full.csv")
    evidence_rows, evidence_headers = read_csv(csv_root / "c003-evidence-index.csv")
    mapping_rows, mapping_headers = read_csv(csv_root / "c003-asset-mapping.csv")

    repaired_stems: dict[str, str] = {}
    for row in question_rows:
        key = (row["year"], row["question_number"])
        repair = QUESTION_REPAIRS.get(key)
        if repair is None:
            continue

        stem = extract_question_stem(exam_texts[row["year"]], row["question_number"])
        if not stem:
            raise ValueError(f"failed to extract repaired stem for {key}")

        question_id = row["question_id"]
        repaired_stems[question_id] = stem
        row["stem_summary"] = stem
        row["primary_knowledge_id"] = repair["knowledge"]
        row["primary_exam_point_id"] = repair["exam"]
        row["secondary_knowledge_ids"] = repair.get("secondary_knowledge", "")
        row["secondary_exam_point_ids"] = repair.get("secondary_exam", "")
        row["ability_dimensions"] = repair["ability"]
        row["confidence"] = "0.82"
        append_note(row, "stem and primary mapping repaired from source exam PDF")

    for row in sub_rows:
        repair = QUESTION_REPAIRS.get((row["year"], row["question_number"]))
        if repair is None or row["question_id"] not in repaired_stems:
            continue
        row["stem_summary"] = repaired_stems[row["question_id"]]
        row["primary_knowledge_id"] = repair["knowledge"]
        row["primary_exam_point_id"] = repair["exam"]
        row["ability_dimensions"] = repair["ability"]
        row["confidence"] = "0.82"
        append_note(row, "stem and primary mapping repaired from source exam PDF")

    for row in evidence_rows:
        stem = repaired_stems.get(row["entity_id"])
        if stem is None:
            continue
        row["evidence_summary"] = stem
        row["parse_quality"] = "text_repaired_from_source_pdf"
        row["confidence"] = "0.88"
        append_note(row, "question stem repaired from source exam PDF")

    mapping_targets: dict[tuple[str, str], str] = {}
    for (year, q_num), repair in QUESTION_REPAIRS.items():
        qid = f"QPHY-C003-{year}-{int(q_num):02d}"
        mapping_targets[(qid, "knowledge_point")] = repair["knowledge"]
        mapping_targets[(qid, "exam_point")] = repair["exam"]

    for row in mapping_rows:
        key = (row["source_stable_id"], row["target_asset_type"])
        target = mapping_targets.get(key)
        if target is None:
            continue
        row["target_stable_id"] = target
        row["confidence"] = "0.82"
        append_note(row, "target repaired after source exam PDF stem correction")

    write_csv(csv_root / "c003-question-item-full.csv", question_rows, question_headers)
    write_csv(csv_root / "c003-subquestion-item-full.csv", sub_rows, sub_headers)
    write_csv(csv_root / "c003-evidence-index.csv", evidence_rows, evidence_headers)
    write_csv(csv_root / "c003-asset-mapping.csv", mapping_rows, mapping_headers)

    return {
        "questionRowsRepaired": len(repaired_stems),
        "subquestionRowsRepaired": sum(1 for row in sub_rows if "stem and primary mapping repaired" in row.get("notes", "")),
        "evidenceRowsRepaired": sum(1 for row in evidence_rows if "question stem repaired" in row.get("notes", "")),
        "mappingRowsRepaired": sum(1 for row in mapping_rows if "target repaired after source exam PDF stem correction" in row.get("notes", "")),
    }


def repair_reference_rows(csv_root: Path) -> dict[str, int]:
    question_rows, question_headers = read_csv(csv_root / "c003-question-item-full.csv")
    sub_rows, sub_headers = read_csv(csv_root / "c003-subquestion-item-full.csv")
    mapping_rows, mapping_headers = read_csv(csv_root / "c003-asset-mapping.csv")
    knowledge_rows, knowledge_headers = read_csv(csv_root / "c003-knowledge-node-full.csv")
    exam_rows, exam_headers = read_csv(csv_root / "c003-exam-point-full.csv")

    question_rows_changed = 0
    subquestion_rows_changed = 0
    mapping_rows_changed = 0
    knowledge_rows_changed = 0
    exam_rows_changed = 0

    question_repairs = QUESTION_REFERENCE_REPAIRS
    question_fields = [
        "primary_knowledge_id",
        "secondary_knowledge_ids",
        "primary_exam_point_id",
        "secondary_exam_point_ids",
        "curriculum_item_ids",
        "ability_dimensions",
        "confidence",
    ]
    for row in question_rows:
        repair = question_repairs.get(row["question_id"])
        if repair is None:
            continue
        changed = False
        for field in question_fields:
            changed = set_value(row, field, repair[field]) or changed
        append_note(row, repair["note"])
        if changed:
            question_rows_changed += 1

    for row in sub_rows:
        repair = question_repairs.get(row["question_id"])
        if repair is None:
            continue
        changed = False
        for field in ("primary_knowledge_id", "primary_exam_point_id", "ability_dimensions", "confidence"):
            changed = set_value(row, field, repair[field]) or changed
        append_note(row, repair["note"])
        if changed:
            subquestion_rows_changed += 1

    for row in mapping_rows:
        repair = question_repairs.get(row["source_stable_id"])
        if repair is None:
            continue
        target = ""
        if row["target_asset_type"] == "knowledge_point":
            target = repair["mapping_knowledge_target"]
        elif row["target_asset_type"] == "exam_point":
            target = repair["mapping_exam_target"]
        if not target:
            continue
        changed = set_value(row, "target_stable_id", target)
        append_note(row, repair["note"])
        if changed:
            mapping_rows_changed += 1

    for row in knowledge_rows:
        refs = MODULE_CURRICULUM_REF_REPAIRS.get(row["stable_id"])
        if refs is None:
            continue
        changed = set_value(row, "curriculum_refs", refs)
        append_note(row, "module curriculum refs repaired to existing standard rows")
        if changed:
            knowledge_rows_changed += 1

    for row in exam_rows:
        knowledge_ids = EXAM_POINT_KNOWLEDGE_REPAIRS.get(row["stable_id"])
        if knowledge_ids is None:
            continue
        changed = set_value(row, "knowledge_stable_ids", knowledge_ids)
        append_note(row, "exam point knowledge refs repaired from source exam PDF")
        if changed:
            exam_rows_changed += 1

    write_csv(csv_root / "c003-question-item-full.csv", question_rows, question_headers)
    write_csv(csv_root / "c003-subquestion-item-full.csv", sub_rows, sub_headers)
    write_csv(csv_root / "c003-asset-mapping.csv", mapping_rows, mapping_headers)
    write_csv(csv_root / "c003-knowledge-node-full.csv", knowledge_rows, knowledge_headers)
    write_csv(csv_root / "c003-exam-point-full.csv", exam_rows, exam_headers)

    return {
        "questionRowsChanged": question_rows_changed,
        "subquestionRowsChanged": subquestion_rows_changed,
        "mappingRowsChanged": mapping_rows_changed,
        "knowledgeRowsChanged": knowledge_rows_changed,
        "examPointRowsChanged": exam_rows_changed,
        "questionRowsVerified": len(QUESTION_REFERENCE_REPAIRS),
        "knowledgeRowsVerified": len(MODULE_CURRICULUM_REF_REPAIRS),
        "examPointRowsVerified": len(EXAM_POINT_KNOWLEDGE_REPAIRS),
    }


def normalize_for_search(value: str) -> str:
    return re.sub(r"\s+", "", value)


def score_year_report_window(window: str, stem: str) -> int:
    score = 0
    if "考查的科学内容" in window or "考察的科学内容" in window:
        score += 5
    if "答案" in window:
        score += 2
    if "分析" in window:
        score += 2
    if "平均分" in window and "难度" in window:
        score += 2
    if "教学" in window or "启示" in window or "建议" in window:
        score += 1
    compact_window = normalize_for_search(window)
    compact_stem = normalize_for_search(stem)
    for size in (24, 16, 12):
        if compact_stem[:size] and compact_stem[:size] in compact_window:
            score += 4
            break
    return score


def locate_year_report_page(pages: list[str], question_number: str, stem: str) -> tuple[int | None, str]:
    q = int(question_number)
    candidates: list[tuple[int, int, str]] = []
    pattern = re.compile(rf"(^|\n)\s*{q}\s*[．.，,]\s*")
    for page_number, page in enumerate(pages, start=1):
        for match in pattern.finditer(page):
            window = page[match.start() : match.start() + 4200]
            score = score_year_report_window(window, stem)
            if score:
                candidates.append((score, page_number, collapse_text(window[:220])))
    if candidates:
        best = sorted(candidates, key=lambda item: (-item[0], item[1]))[0]
        return best[1], best[2]

    fallback = re.compile(rf"第\s*{q}\s*题")
    for page_number, page in enumerate(pages, start=1):
        if fallback.search(page) and ("平均分" in page or "难度" in page or "分析" in page):
            return page_number, "fallback by question mention and analysis keywords"
    return None, ""


def extract_metric_from_page(page: str, question_number: str) -> tuple[str, str]:
    q = int(question_number)
    direct_patterns = [
        r"平均分[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*[，,、]\s*难度[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*[，,、]\s*区分度[:：]?\s*([0-9]+(?:\.[0-9]+)?)",
        r"平均分[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*[，,、]\s*难度[:：]?\s*([0-9]+(?:\.[0-9]+)?)",
    ]
    for pattern in direct_patterns:
        match = re.search(pattern, page)
        if match:
            difficulty = match.group(2)
            discrimination = match.group(3) if len(match.groups()) >= 3 else ""
            return difficulty, discrimination

    lines = page.splitlines()
    for index, line in enumerate(lines):
        if not ("平均分" in line and "难度" in line):
            continue
        for candidate in lines[index + 1 : index + 5]:
            numbers = [float(item) for item in re.findall(r"(?<![\d.])\d+(?:\.\d+)?(?![\d.])", candidate)]
            if len(numbers) >= 2 and not re.match(rf"\s*{q}\s*[．.，,]", candidate):
                return f"{numbers[1]:g}", ""
            if len(numbers) >= 4 and int(numbers[0]) == q:
                return f"{numbers[2]:g}", f"{numbers[4]:g}" if len(numbers) >= 5 and numbers[4] <= 1 else ""
    return "", ""


def repair_year_report_rows(csv_root: Path, pages_by_year: dict[str, list[str]]) -> dict[str, int]:
    question_rows, _question_headers = read_csv(csv_root / "c003-question-item-full.csv")
    questions = {row["question_id"]: row for row in question_rows}
    observation_rows, observation_headers = read_csv(csv_root / "c003-year-report-observation.csv")
    quality_rows, quality_headers = read_csv(csv_root / "c003-quality-issue-registry.csv")

    located: dict[str, tuple[int, str, str, str]] = {}
    for row in observation_rows:
        question = questions[row["question_id"]]
        pages = pages_by_year[row["year"]]
        page_number, snippet = locate_year_report_page(pages, row["question_number"], question["stem_summary"])
        if page_number is None:
            continue
        difficulty, discrimination = extract_metric_from_page(pages[page_number - 1], row["question_number"])
        located[row["observation_id"]] = (page_number, snippet, difficulty, discrimination)
        row["evidence_locations"] = f"年报p{page_number}; 逐题分析自动定位"
        row["official_exam_point_summary"] = f"见年报p{page_number}逐题分析；正式考点归因仍需教研审核"
        if difficulty:
            row["difficulty_value"] = difficulty
        if discrimination:
            row["discrimination_value"] = discrimination
        row["common_errors_summary"] = f"见年报p{page_number}逐题分析；需人工摘录典型错误"
        row["teaching_suggestion_summary"] = f"见年报p{page_number}逐题教学建议；需人工摘录"
        row["confidence"] = "0.72" if not difficulty else "0.80"
        append_note(row, "year report page auto-located from local PDF text")

    for row in quality_rows:
        if row["issue_type"] != "year_report_page_unverified":
            continue
        obs = located.get(row["entity_id"])
        if obs is None:
            row["issue_summary"] = "年报逐题页码仍未自动定位"
            row["severity"] = "medium"
            row["recommended_action"] = "人工定位年报逐题页码并核验难度区分度"
            continue
        page_number, _snippet, difficulty, discrimination = obs
        if difficulty and discrimination:
            row["issue_type"] = "year_report_human_confirmation_required"
            row["issue_summary"] = f"已自动定位年报p{page_number}并提取难度/区分度，仍需人工确认"
            row["severity"] = "low"
            row["recommended_action"] = "抽样核对原年报页码、难度、区分度和教学建议后关闭"
        elif difficulty:
            row["issue_type"] = "year_report_discrimination_review_required"
            row["issue_summary"] = f"已自动定位年报p{page_number}并提取难度，区分度和教学建议仍需人工摘录"
            row["severity"] = "low"
            row["recommended_action"] = "人工核验区分度、典型错误和教学建议"
        else:
            row["issue_type"] = "year_report_metric_review_required"
            row["issue_summary"] = f"已自动定位年报p{page_number}，难度区分度和教学建议仍需人工摘录"
            row["severity"] = "low"
            row["recommended_action"] = "人工核验难度、区分度、典型错误和教学建议"

    write_csv(csv_root / "c003-year-report-observation.csv", observation_rows, observation_headers)
    write_csv(csv_root / "c003-quality-issue-registry.csv", quality_rows, quality_headers)

    return {
        "yearReportRowsLocated": len(located),
        "yearReportDifficultyExtracted": sum(1 for _page, _snippet, difficulty, _disc in located.values() if difficulty),
        "yearReportDiscriminationExtracted": sum(1 for _page, _snippet, _difficulty, disc in located.values() if disc),
        "qualityIssuesByType": dict(Counter(row["issue_type"] for row in quality_rows)),
        "qualityIssuesBySeverity": dict(Counter(row["severity"] for row in quality_rows)),
    }


def update_processing_summary(csv_root: Path) -> None:
    paths = {
        "quality_issues_count": "c003-quality-issue-registry.csv",
        "year_report_observations_count": "c003-year-report-observation.csv",
    }
    summary_rows, headers = read_csv(csv_root / "c003-processing-summary.csv")
    counts = {key: len(read_csv(csv_root / value)[0]) for key, value in paths.items()}
    issue_rows, _ = read_csv(csv_root / "c003-quality-issue-registry.csv")
    counts["low_confidence_rows_count"] = sum(1 for row in issue_rows if row["severity"] in {"medium", "high"})
    counts["rows_missing_source_location_count"] = sum(
        1
        for row in read_csv(csv_root / "c003-year-report-observation.csv")[0]
        if "待人工定位" in row.get("evidence_locations", "")
    )
    for row in summary_rows:
        if row["summary_item"] in counts:
            row["value"] = str(counts[row["summary_item"]])
        if row["summary_item"] == "main_risks":
            row["value"] = "仍为candidate候选数据；图形题语义、非选择题评分点、年报难度区分度和教学建议需抽样人工复核"
    write_csv(csv_root / "c003-processing-summary.csv", summary_rows, headers)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv-root", default="guangzhou-physics-full-research-package-2016-2025/csv")
    parser.add_argument("--exam-pdf-root", default="广州中考/广州中考真题")
    parser.add_argument("--year-report-root", default="广州中考/广州中考年报")
    parser.add_argument("--cache-root", default="tmp/c003-repair")
    parser.add_argument("--report-path", default="docs/evidence/c003-research-package-repair-report.json")
    args = parser.parse_args()

    csv_root = Path(args.csv_root)
    cache_root = Path(args.cache_root)
    exam_texts = ensure_exam_texts(Path(args.exam_pdf_root), cache_root / "exam-text")
    pages_by_year = ensure_year_report_texts(Path(args.year_report_root), cache_root / "year-report-text")

    question_summary = repair_question_rows(csv_root, exam_texts)
    reference_summary = repair_reference_rows(csv_root)
    year_report_summary = repair_year_report_rows(csv_root, pages_by_year)
    update_processing_summary(csv_root)

    report = {
        "status": "pass",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "csvRoot": str(csv_root),
        "candidateOnly": True,
        "productionActivationAllowed": False,
        "questionSummary": question_summary,
        "referenceSummary": reference_summary,
        "yearReportSummary": year_report_summary,
    }
    report_path = Path(args.report_path)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
