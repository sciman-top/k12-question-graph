from __future__ import annotations

import argparse
import json
import re
import zipfile
from collections import OrderedDict
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET


DEFAULT_OUTPUT_ROOT = Path("tmp/f002-score-import")
DEFAULT_REPORT = Path("docs/evidence/f002-score-import-report.json")


ROWS = [
    ["student_key", "display_code", "total_score", "q1_score", "q2_score"],
    ["syn-student-001", "SYN-001", "8", "3", "5"],
    ["syn-student-002", "SYN-002", "6", "2", "4"],
    ["", "SYN-BAD", "12", "7", "5"],
]

FIELD_MAPPING = OrderedDict(
    [
        ("mode", "draft_test"),
        ("productionEligible", False),
        ("templateKey", "f002-synthetic-score-template"),
        ("version", 1),
        ("sourceHeaders", ROWS[0]),
        ("fields", OrderedDict([
            ("student_key", "student_key"),
            ("display_code", "display_code"),
            ("total_score", "total_score"),
            ("q1_score", "item_scores.q1"),
            ("q2_score", "item_scores.q2"),
        ])),
        ("itemMaxScores", OrderedDict([("q1", 3), ("q2", 5)])),
        ("migrationPolicy", OrderedDict([
            ("dynamicAsset", "excel_score_field_mapping"),
            ("reviewStatus", "pending_review"),
            ("supportsOneToMany", True),
            ("requiresRollbackSnapshot", True),
        ])),
    ]
)


def column_name(index: int) -> str:
    value = ""
    current = index + 1
    while current:
        current, remainder = divmod(current - 1, 26)
        value = chr(65 + remainder) + value
    return value


def cell_xml(row_index: int, col_index: int, value: str) -> str:
    ref = f"{column_name(col_index)}{row_index + 1}"
    escaped = (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )
    return f'<c r="{ref}" t="inlineStr"><is><t>{escaped}</t></is></c>'


def sheet_xml() -> str:
    rows = []
    for row_index, row in enumerate(ROWS):
        cells = "".join(cell_xml(row_index, col_index, value) for col_index, value in enumerate(row))
        rows.append(f'<row r="{row_index + 1}">{cells}</row>')
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    %s
  </sheetData>
</worksheet>
""" % "\n    ".join(rows)


def create_xlsx(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as workbook:
        workbook.writestr("[Content_Types].xml", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>
""")
        workbook.writestr("_rels/.rels", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
""")
        workbook.writestr("xl/_rels/workbook.xml.rels", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>
""")
        workbook.writestr("xl/workbook.xml", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="SyntheticScores" sheetId="1" r:id="rId1"/></sheets>
</workbook>
""")
        workbook.writestr("xl/worksheets/sheet1.xml", sheet_xml())


def read_xlsx(path: Path) -> list[dict[str, str]]:
    with zipfile.ZipFile(path) as workbook:
        xml = workbook.read("xl/worksheets/sheet1.xml")
    root = ET.fromstring(xml)
    ns = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    grid: dict[tuple[int, int], str] = {}
    for cell in root.findall(".//x:c", ns):
        ref = cell.attrib["r"]
        match = re.fullmatch(r"([A-Z]+)([0-9]+)", ref)
        if not match:
            continue
        col_letters, row_text = match.groups()
        col = 0
        for char in col_letters:
            col = col * 26 + ord(char) - 64
        text = "".join(node.text or "" for node in cell.findall(".//x:t", ns))
        grid[(int(row_text) - 1, col - 1)] = text

    headers = [grid.get((0, index), "") for index in range(len(ROWS[0]))]
    records: list[dict[str, str]] = []
    for row_index in range(1, len(ROWS)):
        records.append({header: grid.get((row_index, col_index), "") for col_index, header in enumerate(headers)})
    return records


def validate(records: list[dict[str, str]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    imported: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []
    for index, record in enumerate(records, start=2):
        row_errors: list[str] = []
        if not record.get("student_key"):
            row_errors.append("missing_student_key")
        try:
            total = float(record.get("total_score", ""))
            q1 = float(record.get("q1_score", ""))
            q2 = float(record.get("q2_score", ""))
        except ValueError:
            row_errors.append("invalid_score_number")
            total = q1 = q2 = 0
        if q1 > FIELD_MAPPING["itemMaxScores"]["q1"]:
            row_errors.append("q1_score_exceeds_max")
        if q2 > FIELD_MAPPING["itemMaxScores"]["q2"]:
            row_errors.append("q2_score_exceeds_max")
        if abs((q1 + q2) - total) > 0.001:
            row_errors.append("total_score_mismatch")
        if row_errors:
            errors.append({"rowNumber": index, "errors": row_errors, "raw": record})
        else:
            imported.append({"rowNumber": index, "studentKey": record["student_key"], "totalScore": total, "items": {"q1": q1, "q2": q2}, "raw": record})
    return imported, errors


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="F002 synthetic score import fixture")
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    workbook_path = args.output_root / "f002-synthetic-score-template.xlsx"
    mapping_path = args.output_root / "f002-score-field-mapping.json"
    create_xlsx(workbook_path)
    write_json(mapping_path, FIELD_MAPPING)

    records = read_xlsx(workbook_path)
    imported, errors = validate(records)
    status = "pass" if len(imported) == 2 and len(errors) == 1 else "fail"
    report = OrderedDict(
        [
            ("status", status),
            ("task", "F002"),
            ("mode", "draft_test"),
            ("productionEligible", False),
            ("realStudentDataUsed", False),
            ("workbookPath", str(workbook_path)),
            ("mappingPath", str(mapping_path)),
            ("rowCount", len(records)),
            ("importedCount", len(imported)),
            ("errorCount", len(errors)),
            ("importedRows", imported),
            ("errors", errors),
            ("fieldMappingDynamicAsset", True),
            ("templateReusable", True),
            ("summaryChinese", OrderedDict([
                ("title", "F002 Excel 字段映射导入合同报告"),
                ("result", "通过" if status == "pass" else "失败"),
                ("boundary", "仅使用 synthetic Excel fixture，不使用真实学生数据，不写生产学情口径。"),
            ])),
        ]
    )
    write_json(args.report, report)
    print(json.dumps({"status": status, "task": "F002", "workbook": str(workbook_path), "imported": len(imported), "errors": len(errors)}, ensure_ascii=False))
    return 0 if status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
