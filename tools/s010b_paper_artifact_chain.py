from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import shutil
import struct
import subprocess
import tempfile
import zipfile
from collections import OrderedDict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_INPUT = Path("tmp/s010b-paper-artifacts/s010b-paper-input.json")
DEFAULT_OUTPUT_ROOT = Path("tmp/s010b-paper-artifacts")
DEFAULT_REPORT = Path("docs/evidence/20260508-s010b-word-pdf-artifact-chain-report.json")
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


def png_dimensions(path: Path) -> tuple[int, int]:
    payload = path.read_bytes()[:24]
    if len(payload) < 24 or payload[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"unsupported or invalid question image: {path}")
    return struct.unpack(">II", payload[16:24])


def image_xml(index: int, path: Path) -> str:
    rid = f"rIdFigure{index}"
    width, height = png_dimensions(path)
    max_width = 5_300_000
    max_height = 6_500_000
    scale = min(max_width / width, max_height / height)
    cx = max(914_400, int(width * scale))
    cy = max(457_200, int(height * scale))
    return f"""
    <w:p>
      <w:r>
        <w:drawing>
          <wp:inline>
            <wp:extent cx="{cx}" cy="{cy}"/>
            <wp:docPr id="{index}" name="题图{index}"/>
            <a:graphic>
              <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                <pic:pic>
                  <pic:nvPicPr><pic:cNvPr id="{index}" name="figure{index}.png"/><pic:cNvPicPr/></pic:nvPicPr>
                  <pic:blipFill><a:blip r:embed="{rid}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
                  <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
                </pic:pic>
              </a:graphicData>
            </a:graphic>
          </wp:inline>
        </w:drawing>
      </w:r>
    </w:p>
"""


def question_docx_body(data: dict[str, Any], variant: str) -> tuple[str, list[Path]]:
    lines: list[str] = [
        paragraph(f"{data.get('basketTitle', '校本题谱试卷草稿')}（{VARIANTS[variant]}）"),
        paragraph("校本题谱内部草稿，非正式发布"),
    ]
    image_paths: list[Path] = []
    questions = data.get("questions", [])
    for index, question in enumerate(questions, start=1):
        if variant == "answer":
            lines.append(paragraph(f"{index}. {question.get('title', '题目')}"))
            lines.append(paragraph(f"答案：{text(question.get('answer'))}"))
            lines.append(paragraph(f"解析：{text(question.get('solution'))}"))
            lines.append(paragraph(f"来源授权：{question.get('sourceAuthorizationStatus')}"))
            lines.append(paragraph(f"版本引用：{question.get('knowledgeVersionStatus')} v{question.get('knowledgeVersion')}"))
            continue

        lines.append(paragraph(f"{index}. {question.get('title', '题目')}（{question.get('score')} 分）"))
        seen_text: set[str] = set()
        has_image = bool(question.get("hasImage"))
        for block in question.get("blocks", []):
            block_type = text(block.get("blockType")).lower()
            if block_type == "answer":
                continue
            if block_type == "formula":
                lines.append(paragraph(f"公式：{content_value(block, 'latex', 'formula')}"))
            elif block_type == "table":
                content = block.get("content", {})
                rows = content.get("rows") if isinstance(content, dict) else None
                lines.append(table_xml(rows if isinstance(rows, list) else [["字段", "值"], ["table", text(content)]]))
            else:
                block_text = content_value(block, "text", "value").strip()
                normalized = " ".join(block_text.split())
                if not has_image and normalized and normalized not in seen_text:
                    seen_text.add(normalized)
                    lines.append(paragraph(block_text))

        if question.get("hasImage"):
            question_images = [Path(value) for value in question.get("imagePaths", []) if value]
            if not question_images:
                raise ValueError(f"question {index} declares an image but provides no imagePaths")
            image_path = question_images[0]
            if not image_path.is_file() or image_path.stat().st_size <= 1000:
                raise ValueError(f"question {index} image is missing or empty: {image_path}")
            image_paths.append(image_path)
            lines.append(image_xml(len(image_paths), image_path))

        lines.append(paragraph(f"来源授权：{question.get('sourceAuthorizationStatus')}"))
        lines.append(paragraph(f"版本引用：{question.get('knowledgeVersionStatus')} v{question.get('knowledgeVersion')}"))
        if variant == "teacher":
            lines.append(paragraph(f"答案：{text(question.get('answer'))}"))
            lines.append(paragraph(f"解析：{text(question.get('solution'))}"))

    lines.append('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>')
    return "\n".join(lines), image_paths


def create_docx(path: Path, data: dict[str, Any], variant: str) -> None:
    body, image_paths = question_docx_body(data, variant)
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
        for i in range(1, len(image_paths) + 1)
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
        for i, image_path in enumerate(image_paths, start=1):
            docx.writestr(f"word/media/figure{i}.png", image_path.read_bytes())


def create_pdf(path: Path, docx_path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    soffice = shutil.which("soffice") or next(
        (str(candidate) for candidate in (
            Path(r"C:\Program Files\LibreOffice\program\soffice.exe"),
            Path(r"C:\Program Files (x86)\LibreOffice\program\soffice.exe"),
        ) if candidate.is_file()),
        "",
    )
    if not soffice:
        raise RuntimeError("LibreOffice soffice is required for substantive PDF export")
    soffice_path = Path(soffice)
    if os.name == "nt" and soffice_path.name.lower() == "soffice.exe":
        console_launcher = soffice_path.with_name("soffice.com")
        if console_launcher.is_file():
            soffice = str(console_launcher)
    if path.exists():
        path.unlink()
    profile = Path(tempfile.mkdtemp(prefix=f"kqg-lo-{docx_path.stem}-"))
    completed = subprocess.run(
        [
            soffice,
            "--headless",
            f"-env:UserInstallation={profile.as_uri()}",
            "--convert-to",
            "pdf:writer_pdf_Export",
            "--outdir",
            str(path.parent.resolve()),
            str(docx_path.resolve()),
        ],
        capture_output=True,
        text=True,
        timeout=90,
        check=False,
    )
    shutil.rmtree(profile, ignore_errors=True)
    if completed.returncode != 0 or not path.is_file():
        raise RuntimeError(f"LibreOffice PDF conversion failed: {completed.stderr or completed.stdout}")


def verify_docx(path: Path, variant: str) -> dict[str, Any]:
    with zipfile.ZipFile(path) as docx:
        names = set(docx.namelist())
        document_xml = docx.read("word/document.xml").decode("utf-8")
        media = [name for name in names if name.startswith("word/media/")]
        media_sizes = [len(docx.read(name)) for name in media]
    return {
        "hasDocumentXml": "word/document.xml" in names,
        "hasFormulaText": "v=s/t" in document_xml,
        "hasFigureMedia": bool(media) if variant != "answer" else True,
        "hasTable": "<w:tbl>" in document_xml if variant != "answer" else True,
        "hasSourceAuthorization": "来源授权：authorized" in document_xml,
        "hasKnowledgeVersionReference": "版本引用：active v1" in document_xml,
        "hasAnswer": "答案：" in document_xml,
        "hasSolution": "解析：" in document_xml,
        "studentHidesAnswer": ("答案：" not in document_xml and "解析：" not in document_xml) if variant == "student" else True,
        "mediaCount": len(media),
        "allMediaSubstantive": all(size > 1000 for size in media_sizes) if media else variant == "answer",
    }


def minimum_substantive_text_length(expected_question_count: int) -> int:
    return max(50, expected_question_count * 20)


def verify_pdf(path: Path, expected_question_count: int) -> dict[str, Any]:
    from pypdf import PdfReader

    payload = path.read_bytes()
    reader = PdfReader(path)
    extracted_text = "\n".join((page.extract_text() or "") for page in reader.pages)
    return {
        "hasPdfHeader": payload.startswith(b"%PDF-"),
        "hasEof": payload.rstrip().endswith(b"%%EOF"),
        "hasTaskMarker": "校本题谱" in extracted_text,
        "pageCountPositive": len(reader.pages) >= 1,
        "fileSizeSubstantive": len(payload) > 10_000,
        "textLengthSubstantive": len(extracted_text.strip()) > minimum_substantive_text_length(expected_question_count),
        "pageCount": len(reader.pages),
        "fileSizeBytes": len(payload),
        "extractedTextLength": len(extracted_text.strip()),
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
        and docx["studentHidesAnswer"]
        and docx["hasSourceAuthorization"]
        and docx["hasKnowledgeVersionReference"]
    )
    if variant in {"student", "teacher"}:
        common_docx = (
            common_docx
            and docx["hasFigureMedia"]
            and docx["allMediaSubstantive"]
        )
        if requirements["requiresFormula"]:
            common_docx = common_docx and docx["hasFormulaText"]
        if requirements["requiresTable"]:
            common_docx = common_docx and docx["hasTable"]
    if variant == "teacher":
        common_docx = common_docx and docx["hasAnswer"] and docx["hasSolution"]
    if variant == "answer":
        common_docx = common_docx and docx["hasAnswer"] and docx["hasSolution"]
    return common_docx and all(pdf[key] is True for key in (
        "hasPdfHeader", "hasEof", "hasTaskMarker", "pageCountPositive",
        "fileSizeSubstantive", "textLengthSubstantive",
    ))


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
        create_pdf(pdf_path, docx_path)
        docx_checks = verify_docx(docx_path, variant)
        pdf_checks = verify_pdf(pdf_path, len(data.get("questions", [])))
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
