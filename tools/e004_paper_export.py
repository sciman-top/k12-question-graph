from __future__ import annotations

import argparse
import json
import zipfile
from collections import OrderedDict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_OUTPUT_ROOT = Path("tmp/e004-paper-export")
DEFAULT_REPORT = Path("docs/evidence/e004-paper-export-report.json")
PNG_1X1 = bytes.fromhex(
    "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
    "1f15c4890000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082"
)


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def docx_document_xml() -> str:
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
  xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
  <w:body>
    <w:p><w:r><w:t>校本题谱 draft_test 导出样卷</w:t></w:r></w:p>
    <w:p><w:r><w:t>productionEligible=false; formal C002 is not active.</w:t></w:r></w:p>
    <w:p><w:r><w:t>sourceAuthorization=synthetic_internal_authorized; no real student data.</w:t></w:r></w:p>
    <w:p><w:r><w:t>1. 关于惯性的说法，下列哪项正确？</w:t></w:r></w:p>
    <w:p><w:r><w:t>公式：F=ma</w:t></w:r></w:p>
    <w:p>
      <w:r>
        <w:drawing>
          <wp:inline>
            <wp:extent cx="914400" cy="457200"/>
            <wp:docPr id="1" name="题图1"/>
            <a:graphic>
              <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                <pic:pic>
                  <pic:nvPicPr><pic:cNvPr id="1" name="figure1.png"/><pic:cNvPicPr/></pic:nvPicPr>
                  <pic:blipFill><a:blip r:embed="rIdFigure1"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
                  <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="914400" cy="457200"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
                </pic:pic>
              </a:graphicData>
            </a:graphic>
          </wp:inline>
        </w:drawing>
      </w:r>
    </w:p>
    <w:tbl>
      <w:tr><w:tc><w:p><w:r><w:t>物理量</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>单位</w:t></w:r></w:p></w:tc></w:tr>
      <w:tr><w:tc><w:p><w:r><w:t>力</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>N</w:t></w:r></w:p></w:tc></w:tr>
    </w:tbl>
    <w:p><w:r><w:t>答案：B</w:t></w:r></w:p>
    <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
  </w:body>
</w:document>
"""


def create_docx(path: Path) -> None:
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
        docx.writestr("word/_rels/document.xml.rels", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdFigure1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/figure1.png"/>
</Relationships>
""")
        docx.writestr("word/document.xml", docx_document_xml())
        docx.writestr("word/media/figure1.png", PNG_1X1)


def create_pdf(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Minimal PDF with ASCII text; the DOCX is the primary Word/WPS fidelity artifact.
    content = "BT /F1 12 Tf 72 760 Td (KQG draft_test paper export) Tj 0 -24 Td (Q1 formula: F=ma; table and figure are preserved in DOCX) Tj 0 -24 Td (sourceAuthorization=synthetic_internal_authorized; no real student data) Tj ET"
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


def verify_docx(path: Path) -> dict[str, Any]:
    with zipfile.ZipFile(path) as docx:
        names = set(docx.namelist())
        document_xml = docx.read("word/document.xml").decode("utf-8")
        media = [name for name in names if name.startswith("word/media/")]
    return {
        "hasDocumentXml": "word/document.xml" in names,
        "hasFormulaText": "F=ma" in document_xml,
        "hasFigureMedia": bool(media),
        "hasTable": "<w:tbl>" in document_xml,
        "hasAnswer": "答案：B" in document_xml,
        "hasAuthorizationText": "sourceAuthorization=synthetic_internal_authorized" in document_xml,
        "mediaCount": len(media),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="E004 draft/test paper export")
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    output_root = args.output_root
    docx_path = output_root / "kqg-e004-draft-test-paper.docx"
    pdf_path = output_root / "kqg-e004-draft-test-paper.pdf"
    manifest_path = output_root / "kqg-e004-draft-test-paper.manifest.json"

    create_docx(docx_path)
    create_pdf(pdf_path)
    docx_checks = verify_docx(docx_path)
    pdf_bytes = pdf_path.read_bytes()
    pdf_checks = {
        "hasPdfHeader": pdf_bytes.startswith(b"%PDF-"),
        "hasEof": pdf_bytes.rstrip().endswith(b"%%EOF"),
        "hasFormulaText": b"F=ma" in pdf_bytes,
    }

    status = "pass" if all(docx_checks.values()) and all(pdf_checks.values()) else "fail"
    manifest = OrderedDict(
        [
            ("mode", "draft_test"),
            ("productionEligible", False),
            ("formalC002Required", False),
            ("sourceAuthorization", "synthetic_internal_authorized"),
            ("realStudentDataUsed", False),
            ("authorizationText", "sourceAuthorization=synthetic_internal_authorized; no real student data."),
            ("exportedAt", datetime.now(timezone.utc).isoformat()),
            ("artifacts", {"docx": str(docx_path), "pdf": str(pdf_path)}),
            ("checks", {"docx": docx_checks, "pdf": pdf_checks}),
        ]
    )
    write_json(manifest_path, manifest)
    report = OrderedDict(
        [
            ("status", status),
            ("task", "E004"),
            ("mode", "draft_test"),
            ("productionEligible", False),
            ("formalC002Required", False),
            ("sourceAuthorization", "synthetic_internal_authorized"),
            ("realStudentDataUsed", False),
            ("outputRoot", str(output_root)),
            ("docxPath", str(docx_path)),
            ("pdfPath", str(pdf_path)),
            ("manifestPath", str(manifest_path)),
            ("docxChecks", docx_checks),
            ("pdfChecks", pdf_checks),
            ("summaryChinese", {
                "title": "E004 Word/PDF 导出 MVP 报告",
                "result": "通过" if status == "pass" else "失败",
                "boundary": "draft/test 导出，不依赖正式 C002，不声明生产试卷口径。",
            }),
        ]
    )
    write_json(args.report, report)
    print(json.dumps({"status": status, "task": "E004", "docx": str(docx_path), "pdf": str(pdf_path)}, ensure_ascii=False))
    return 0 if status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
