from __future__ import annotations

import argparse
import json
import subprocess
import sys
import zipfile
from collections import OrderedDict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
import locale

from e004_paper_export import PNG_1X1, create_docx as create_export_docx, create_pdf, verify_docx


DEFAULT_FILE_ROOT = Path("tmp/j004-fidelity")
DEFAULT_REPORT = Path("docs/evidence/j004-fidelity-regression-report.json")


CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="png" ContentType="image/png"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
"""

ROOT_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
"""

DOCUMENT_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdFigure1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/j004-figure.png"/>
</Relationships>
"""

DOCUMENT_XML = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
  xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
  <w:body>
    <w:p><w:r><w:t>题干：观察题图中的弹簧测力计，判断拉力大小。</w:t></w:r></w:p>
    <w:p><w:r><w:t>A. 1 N</w:t></w:r></w:p>
    <w:p><w:r><w:t>B. 2 N</w:t></w:r></w:p>
    <w:p><w:r><w:t>公式：</w:t></w:r><m:oMath><m:r><m:t>F=ma</m:t></m:r></m:oMath></w:p>
    <w:p>
      <w:r>
        <w:drawing>
          <wp:inline>
            <wp:extent cx="914400" cy="457200"/>
            <wp:docPr id="1" name="J004题图"/>
            <a:graphic>
              <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                <pic:pic>
                  <pic:nvPicPr><pic:cNvPr id="1" name="j004-figure.png"/><pic:cNvPicPr/></pic:nvPicPr>
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
      <w:tr><w:tc><w:p><w:r><w:t>测量次数</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>拉力/N</w:t></w:r></w:p></w:tc></w:tr>
      <w:tr><w:tc><w:p><w:r><w:t>1</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>2</w:t></w:r></w:p></w:tc></w:tr>
    </w:tbl>
    <w:p><w:r><w:t>答案：B</w:t></w:r></w:p>
    <w:p><w:r><w:t>解析：示数为 2 N。</w:t></w:r></w:p>
  </w:body>
</w:document>
"""


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def create_import_docx(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as docx:
        docx.writestr("[Content_Types].xml", CONTENT_TYPES)
        docx.writestr("_rels/.rels", ROOT_RELS)
        docx.writestr("word/_rels/document.xml.rels", DOCUMENT_RELS)
        docx.writestr("word/document.xml", DOCUMENT_XML)
        docx.writestr("word/media/j004-figure.png", PNG_1X1)


def run_worker(file_root: Path, relative_path: str) -> dict[str, Any]:
    completed = subprocess.run(
        [
            sys.executable,
            "workers/document/worker.py",
            "--job-id",
            "j004-fidelity",
            "--relative-path",
            relative_path,
            "--file-root",
            str(file_root),
        ],
        check=True,
        capture_output=True,
    )
    for encoding in ("utf-8", locale.getpreferredencoding(False), "gb18030"):
        try:
            return json.loads(completed.stdout.decode(encoding))
        except UnicodeDecodeError:
            continue
    return json.loads(completed.stdout.decode("utf-8", errors="replace"))


def flatten_blocks(worker_json: dict[str, Any]) -> list[dict[str, Any]]:
    blocks: list[dict[str, Any]] = []
    for page in worker_json["documentModel"]["pages"]:
        blocks.extend(page.get("layoutBlocks", []))
    return blocks


def build_question_draft(blocks: list[dict[str, Any]]) -> dict[str, Any]:
    question_blocks = []
    assets = []
    for index, block in enumerate(blocks):
        block_type = block["blockType"]
        if block_type == "image":
            assets.append(
                {
                    "assetType": "image",
                    "purpose": "question_figure",
                    "sourceRegion": block["sourceRegion"],
                    "target": block.get("asset", {}).get("target"),
                }
            )
            continue
        question_blocks.append(
            {
                "blockType": block_type,
                "sortOrder": index,
                "sourceRegion": block["sourceRegion"],
                "content": block.get("table") or {"text": block["textPreview"]},
            }
        )
    return {
        "mode": "draft_test",
        "productionEligible": False,
        "status": "draft",
        "blocks": question_blocks,
        "assets": assets,
    }


def assert_fidelity(name: str, value: bool) -> None:
    if not value:
        raise AssertionError(f"J004 fidelity check failed: {name}")


def main() -> int:
    parser = argparse.ArgumentParser(description="J004 formula/table/figure import-export fidelity regression")
    parser.add_argument("--file-root", type=Path, default=DEFAULT_FILE_ROOT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    input_docx = args.file_root / "j004-import-golden.docx"
    output_root = args.file_root / "export"
    output_docx = output_root / "j004-export-regression.docx"
    output_pdf = output_root / "j004-export-regression.pdf"
    create_import_docx(input_docx)

    worker_json = run_worker(args.file_root, "j004-import-golden.docx")
    blocks = flatten_blocks(worker_json)
    block_types = [block["blockType"] for block in blocks]
    question_draft = build_question_draft(blocks)

    import_checks = OrderedDict(
        [
            ("adapterName", worker_json["adapterDiagnostics"][0]["adapterName"]),
            ("hasFormulaBlock", "formula" in block_types),
            ("hasTableBlock", "table" in block_types),
            ("hasImageBlock", "image" in block_types),
            ("hasImageRelationshipTarget", any(block.get("asset", {}).get("target") for block in blocks if block["blockType"] == "image")),
        ]
    )
    draft_checks = OrderedDict(
        [
            ("mode", question_draft["mode"]),
            ("productionEligible", question_draft["productionEligible"]),
            ("formulaBlocks", sum(1 for block in question_draft["blocks"] if block["blockType"] == "formula")),
            ("tableBlocks", sum(1 for block in question_draft["blocks"] if block["blockType"] == "table")),
            ("imageAssets", len(question_draft["assets"])),
            ("sourceRegionsPreserved", all(block.get("sourceRegion") for block in question_draft["blocks"]) and all(asset.get("sourceRegion") for asset in question_draft["assets"])),
        ]
    )

    create_export_docx(output_docx)
    create_pdf(output_pdf)
    export_checks = verify_docx(output_docx)
    pdf_checks = {
        "hasPdfHeader": output_pdf.read_bytes().startswith(b"%PDF-"),
        "hasEof": output_pdf.read_bytes().rstrip().endswith(b"%%EOF"),
        "hasFormulaText": b"F=ma" in output_pdf.read_bytes(),
    }

    assert_fidelity("OpenXML adapter", import_checks["adapterName"] == "openxml_docx_adapter")
    for key in ("hasFormulaBlock", "hasTableBlock", "hasImageBlock", "hasImageRelationshipTarget"):
        assert_fidelity(f"import {key}", bool(import_checks[key]))
    assert_fidelity("draft_test mode", draft_checks["mode"] == "draft_test")
    assert_fidelity("draft non-production", draft_checks["productionEligible"] is False)
    assert_fidelity("draft formula preserved", draft_checks["formulaBlocks"] >= 1)
    assert_fidelity("draft table preserved", draft_checks["tableBlocks"] >= 1)
    assert_fidelity("draft image asset preserved", draft_checks["imageAssets"] >= 1)
    assert_fidelity("source regions preserved", draft_checks["sourceRegionsPreserved"] is True)
    for key in ("hasFormulaText", "hasTable", "hasFigureMedia"):
        assert_fidelity(f"export docx {key}", bool(export_checks[key]))
    assert_fidelity("export pdf header", pdf_checks["hasPdfHeader"] and pdf_checks["hasEof"])

    report = OrderedDict(
        [
            ("status", "pass"),
            ("task", "J004"),
            ("mode", "draft_test"),
            ("productionEligible", False),
            ("externalAiCalls", 0),
            ("realStudentDataUsed", False),
            ("inputDocx", str(input_docx)),
            ("exportDocx", str(output_docx)),
            ("exportPdf", str(output_pdf)),
            ("importChecks", import_checks),
            ("draftChecks", draft_checks),
            ("exportChecks", {"docx": export_checks, "pdf": pdf_checks}),
            ("rollback", "git restore tracked files; remove tmp/j004-fidelity and docs/evidence/j004-fidelity-regression-report.json"),
            ("createdAt", datetime.now(timezone.utc).isoformat()),
            ("summaryChinese", "J004 已验证公式、表格、题图从 OpenXML 导入解析到 draft question 再到 Word/PDF 导出均未丢失；仅 synthetic draft/test，不具备生产资格。"),
        ]
    )
    write_json(args.report, report)
    print(json.dumps({"status": "pass", "task": "J004", "report": str(args.report)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
