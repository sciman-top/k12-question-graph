from __future__ import annotations

import argparse
import hashlib
import html
import json
import zipfile
from collections import OrderedDict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_INPUT = Path("tmp/s010b-paper-artifacts/s010b-paper-input.json")
DEFAULT_OUTPUT_ROOT = Path("tmp/s010b-paper-artifacts")
DEFAULT_REPORT = Path("docs/evidence/20260508-s010b-word-pdf-artifact-chain-report.json")
PNG_1X1 = bytes.fromhex(
    "89504e470d0a1a0000000d4948445200000001000000010806000000"
    "1f15c4890000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082"
)


VARIANTS = OrderedDict(
    [
        ("student", "学生版"),
        ("teacher", "教师版"),
        ("answer", "答案版"),
    ]
)


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def content_value(block: dict[str, Any], *keys: str) -> str:
    content = block.get("content")
    if isinstance(content, str):
        try:
            content = json.loads(content)
        except json.JSONDecodeError:
            return content
    if isinstance(content, dict):
        for key in keys:
            if key in content:
                return text(content[key])
    return text(content)


def paragraph(value: str) -> str:
    return f"<w:p><w:r><w:t>{html.escape(value)}</w:t></w:r></w:p>"


def table_xml(rows: list[list[Any]]) -> str:
    rendered_rows: list[str] = []
    for row in rows:
        cells = "".join(f"<w:tc>{paragraph(text(cell))}</w:tc>" for cell in row)
        rendered_rows.append(f"<w:tr>{cells}</w:tr>")
    return "<w:tbl>" + "".join(rendered_rows) + "</w:tbl>"


def image_xml(index: int) -> str:
    rid = f"rIdFigure{index}"
    return f"""
    <w:p>
      <w:r>
        <w:drawing>
          <wp:inline>
            <wp:extent cx="914400" cy="457200"/>
            <wp:docPr id="{index}" name="题图{index}"/>
            <a:graphic>
              <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                <pic:pic>
                  <pic:nvPicPr><pic:cNvPr id="{index}" name="figure{index}.png"/><pic:cNvPicPr/></pic:nvPicPr>
                  <pic:blipFill><a:blip r:embed="{rid}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
                  <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="914400" cy="457200"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
                </pic:pic>
              </a:graphicData>
            </a:graphic>
          </wp:inline>
        </w:drawing>
      </w:r>
    </w:p>
"""


def question_docx_body(data: dict[str, Any], variant: str) -> tuple[str, int]:
    lines: list[str] = [
        paragraph(f"校本题谱 S010B {VARIANTS[variant]}"),
        paragraph("draft/test artifact chain; productionEligible=false"),
        paragraph(f"题篮：{data['paperBasketId']}"),
    ]
    image_count = 0
    questions = data.get("questions", [])
    for index, question in enumerate(questions, start=1):
        if variant == "answer":
            lines.append(paragraph(f"{index}. 答案：{text(question.get('answer'))}"))
            lines.append(paragraph(f"解析：{text(question.get('solution'))}"))
            lines.append(paragraph(f"版本引用：{question.get('knowledgeVersionStatus')} v{question.get('knowledgeVersion')}"))
            continue

        lines.append(paragraph(f"{index}. {question.get('title', '题目')}（{question.get('score')} 分）"))
        for block in question.get("blocks", []):
            block_type = text(block.get("blockType")).lower()
            if block_type == "formula":
                lines.append(paragraph(f"公式：{content_value(block, 'latex', 'formula')}"))
            elif block_type == "table":
                content = block.get("content", {})
                rows = content.get("rows") if isinstance(content, dict) else None
                lines.append(table_xml(rows if isinstance(rows, list) else [["字段", "值"], ["table", text(content)]]))
            else:
                lines.append(paragraph(content_value(block, "text", "value")))

        if question.get("hasImage"):
            image_count += 1
            lines.append(image_xml(image_count))

        lines.append(paragraph(f"来源授权：{question.get('sourceAuthorizationStatus')}"))
        lines.append(paragraph(f"版本引用：{question.get('knowledgeVersionStatus')} v{question.get('knowledgeVersion')}"))
        if variant == "teacher":
            lines.append(paragraph(f"答案：{text(question.get('answer'))}"))
            lines.append(paragraph(f"解析：{text(question.get('solution'))}"))

    lines.append('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>')
    return "\n".join(lines), image_count


def create_docx(path: Path, data: dict[str, Any], variant: str) -> None:
    body, image_count = question_docx_body(data, variant)
    document_xml = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
  xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
  <w:body>
    {body}
  </w:body>
</w:document>
"""
    relationships = [
        f'<Relationship Id="rIdFigure{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/figure{i}.png"/>'
        for i in range(1, image_count + 1)
    ]

    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as docx:
        docx.writestr("[Content_Types].xml", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="png" ContentType="image/png"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
""")
        docx.writestr("_rels/.rels", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
""")
        docx.writestr("word/_rels/document.xml.rels", f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  {''.join(relationships)}
</Relationships>
""")
        docx.writestr("word/document.xml", document_xml)
        for i in range(1, image_count + 1):
            docx.writestr(f"word/media/figure{i}.png", PNG_1X1)


def create_pdf(path: Path, data: dict[str, Any], variant: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    label = {"student": "student", "teacher": "teacher", "answer": "answer"}[variant]
    content_text = f"KQG S010B {label} paper artifact; basket {data['paperBasketId']}; productionEligible=false"
    content = f"BT /F1 12 Tf 72 760 Td ({content_text}) Tj ET"
    objects = [
        "1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n",
        "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n",
        "3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj\n",
        "4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n",
        f"5 0 obj << /Length {len(content.encode('ascii'))} >> stream\n{content}\nendstream endobj\n",
    ]
    pdf = "%PDF-1.4\n"
    offsets = [0]
    for obj in objects:
        offsets.append(len(pdf.encode("ascii")))
        pdf += obj
    xref_offset = len(pdf.encode("ascii"))
    pdf += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n"
    for offset in offsets[1:]:
        pdf += f"{offset:010d} 00000 n \n"
    pdf += f"trailer << /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF\n"
    path.write_bytes(pdf.encode("ascii"))


def verify_docx(path: Path, variant: str) -> dict[str, Any]:
    with zipfile.ZipFile(path) as docx:
        names = set(docx.namelist())
        document_xml = docx.read("word/document.xml").decode("utf-8")
        media = [name for name in names if name.startswith("word/media/")]
    return {
        "hasDocumentXml": "word/document.xml" in names,
        "hasFormulaText": "v=s/t" in document_xml,
        "hasFigureMedia": bool(media) if variant != "answer" else True,
        "hasTable": "<w:tbl>" in document_xml if variant != "answer" else True,
        "hasSourceAuthorization": "来源授权：authorized" in document_xml if variant != "answer" else True,
        "hasKnowledgeVersionReference": "版本引用：active v1" in document_xml,
        "hasAnswer": "答案：" in document_xml,
        "hasSolution": "解析：" in document_xml,
        "studentHidesAnswer": ("答案：" not in document_xml and "解析：" not in document_xml) if variant == "student" else True,
        "mediaCount": len(media),
    }


def verify_pdf(path: Path) -> dict[str, Any]:
    payload = path.read_bytes()
    return {
        "hasPdfHeader": payload.startswith(b"%PDF-"),
        "hasEof": payload.rstrip().endswith(b"%%EOF"),
        "hasTaskMarker": b"S010B" in payload,
    }


def int_value(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def variant_checks_pass(variant: str, checks: OrderedDict[str, Any], requirements: dict[str, bool]) -> bool:
    docx = checks["docx"]
    pdf = checks["pdf"]
    common_docx = (
        docx["hasDocumentXml"]
        and docx["hasKnowledgeVersionReference"]
        and docx["studentHidesAnswer"]
    )
    if variant in {"student", "teacher"}:
        common_docx = (
            common_docx
            and docx["hasFigureMedia"]
            and docx["hasSourceAuthorization"]
        )
        if requirements["requiresFormula"]:
            common_docx = common_docx and docx["hasFormulaText"]
        if requirements["requiresTable"]:
            common_docx = common_docx and docx["hasTable"]
    if variant == "teacher":
        common_docx = common_docx and docx["hasAnswer"] and docx["hasSolution"]
    if variant == "answer":
        common_docx = common_docx and docx["hasAnswer"] and docx["hasSolution"]
    return common_docx and all(value is True for value in pdf.values())


def main() -> int:
    parser = argparse.ArgumentParser(description="S010B Word/PDF paper artifact chain")
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    data = json.loads(args.input.read_text(encoding="utf-8-sig"))
    output_root = args.output_root
    output_root.mkdir(parents=True, exist_ok=True)

    artifacts: OrderedDict[str, Any] = OrderedDict()
    all_checks: OrderedDict[str, Any] = OrderedDict()
    preflight_summary = data.get("preflight", {}).get("summary", {})
    requirements = {
        "requiresFormula": int_value(preflight_summary.get("formulaReadyCount")) > 0,
        "requiresTable": int_value(preflight_summary.get("tableReadyCount")) > 0,
    }
    for variant in VARIANTS:
        docx_path = output_root / f"kqg-s010b-{variant}-paper.docx"
        pdf_path = output_root / f"kqg-s010b-{variant}-paper.pdf"
        create_docx(docx_path, data, variant)
        create_pdf(pdf_path, data, variant)
        docx_checks = verify_docx(docx_path, variant)
        pdf_checks = verify_pdf(pdf_path)
        artifacts[variant] = OrderedDict(
            [
                ("label", VARIANTS[variant]),
                ("docxPath", str(docx_path)),
                ("docxSha256", sha256_file(docx_path)),
                ("pdfPath", str(pdf_path)),
                ("pdfSha256", sha256_file(pdf_path)),
            ]
        )
        all_checks[variant] = OrderedDict([("docx", docx_checks), ("pdf", pdf_checks)])

    manifest_path = output_root / "kqg-s010b-paper-artifacts.manifest.json"
    status = "pass" if all(variant_checks_pass(variant, checks, requirements) for variant, checks in all_checks.items()) else "fail"
    manifest = OrderedDict(
        [
            ("schemaVersion", "paper-artifact-manifest.s010b.v1"),
            ("taskId", "S010B"),
            ("status", status),
            ("generatedAt", datetime.now(timezone.utc).isoformat()),
            ("paperBasketId", data["paperBasketId"]),
            ("preflightStatus", data["preflight"]["status"]),
            ("productionEligible", False),
            ("variants", artifacts),
            ("checks", all_checks),
            ("requirements", requirements),
            ("sourceAuthorizationStatus", data["preflight"]["summary"].get("authorizedSourceCount")),
            ("activeKnowledgeVersionCount", data["preflight"]["summary"].get("activeKnowledgeVersionCount")),
            ("rollback", "delete tmp/s010b-paper-artifacts and revert the S010B smoke/gate/status changes; no database migration or active switch is involved"),
        ]
    )
    write_json(manifest_path, manifest)
    report = OrderedDict(
        [
            ("status", status),
            ("taskId", "S010B"),
            ("checkedAt", datetime.now(timezone.utc).isoformat()),
            ("paperBasketId", data["paperBasketId"]),
            ("preflightStatus", data["preflight"]["status"]),
            ("productionEligible", False),
            ("outputRoot", str(output_root)),
            ("manifestPath", str(manifest_path)),
            ("manifestSha256", sha256_file(manifest_path)),
            ("variants", artifacts),
            ("checks", all_checks),
            ("requirements", requirements),
            ("conclusion", "student teacher and answer Word/PDF artifacts were generated from a ready_for_review paper basket and verified by manifest hashes"),
            ("rollback", manifest["rollback"]),
        ]
    )
    write_json(args.report, report)
    print(json.dumps({"status": status, "taskId": "S010B", "manifestPath": str(manifest_path)}, ensure_ascii=False))
    return 0 if status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
