import argparse
import hashlib
import json
import pathlib
import platform
import re
import sys
import time
import zipfile
import xml.etree.ElementTree as ET


WORD_NS = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "m": "http://schemas.openxmlformats.org/officeDocument/2006/math",
}


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


def element_text(element: ET.Element) -> str:
    return "".join(text for text in element.itertext()).strip()


def paragraph_type(text: str) -> str:
    normalized = text.strip()
    if normalized.startswith(("A.", "B.", "C.", "D.", "A．", "B．", "C．", "D．")):
        return "option"
    if normalized.startswith(("答案", "Answer")):
        return "answer"
    if normalized.startswith(("解析", "Explanation")):
        return "explanation"
    if normalized:
        return "question_stem"
    return "paragraph"


def parse_docx_blocks(target: pathlib.Path) -> tuple[list[dict], list[str]]:
    warnings: list[str] = []
    blocks: list[dict] = []

    with zipfile.ZipFile(target) as docx:
        document_xml = docx.read("word/document.xml")

    root = ET.fromstring(document_xml)
    body = root.find("w:body", WORD_NS)
    if body is None:
        return blocks, ["OpenXML document body missing"]

    for child in list(body):
        tag = child.tag.rsplit("}", 1)[-1]
        if tag == "p":
            text = element_text(child)
            has_formula = child.find(".//m:oMath", WORD_NS) is not None or child.find(".//m:oMathPara", WORD_NS) is not None
            if not text and not has_formula:
                continue

            block_type = "formula" if has_formula else paragraph_type(text)
            blocks.append(
                {
                    "id": f"block_{len(blocks) + 1:04d}",
                    "pageNumber": 1,
                    "blockType": block_type,
                    "textPreview": text[:500],
                    "sourceRegion": {
                        "source": "openxml",
                        "element": "w:p",
                        "index": len(blocks),
                    },
                }
            )
        elif tag == "tbl":
            rows = []
            for row in child.findall("w:tr", WORD_NS):
                rows.append([element_text(cell) for cell in row.findall("w:tc", WORD_NS)])
            blocks.append(
                {
                    "id": f"block_{len(blocks) + 1:04d}",
                    "pageNumber": 1,
                    "blockType": "table",
                    "textPreview": json.dumps(rows, ensure_ascii=False)[:500],
                    "sourceRegion": {
                        "source": "openxml",
                        "element": "w:tbl",
                        "index": len(blocks),
                    },
                    "table": {
                        "rows": rows,
                    },
                }
            )

    if not blocks:
        warnings.append("OpenXML document parsed but no supported blocks were found")

    return blocks, warnings


def decode_pdf_literal(raw: bytes) -> str:
    text = raw.decode("latin-1")
    text = text.replace("\\(", "(").replace("\\)", ")").replace("\\\\", "\\")
    return text


def parse_pdf_objects(payload: bytes) -> dict[int, bytes]:
    objects: dict[int, bytes] = {}
    pattern = re.compile(rb"(?m)(\d+)\s+0\s+obj\s*(.*?)\s*endobj", re.DOTALL)
    for match in pattern.finditer(payload):
        objects[int(match.group(1))] = match.group(2)
    return objects


def parse_text_pdf_pages(target: pathlib.Path) -> tuple[list[dict], list[str]]:
    payload = target.read_bytes()
    objects = parse_pdf_objects(payload)
    warnings: list[str] = []
    pages: list[dict] = []

    page_refs = []
    for object_id, body in objects.items():
        if b"/Type /Page" not in body or b"/Type /Pages" in body:
            continue
        content_match = re.search(rb"/Contents\s+(\d+)\s+0\s+R", body)
        if content_match:
            page_refs.append((object_id, int(content_match.group(1))))

    for page_number, (page_object_id, content_object_id) in enumerate(sorted(page_refs), start=1):
        content_object = objects.get(content_object_id, b"")
        stream_match = re.search(rb"stream\r?\n?(.*?)\r?\n?endstream", content_object, re.DOTALL)
        if not stream_match:
            warnings.append(f"PDF page {page_number} content stream missing")
            continue

        stream = stream_match.group(1)
        text_items = [decode_pdf_literal(match.group(1)) for match in re.finditer(rb"\((.*?)\)\s*Tj", stream, re.DOTALL)]
        blocks = []
        for index, text in enumerate(item.strip() for item in text_items if item.strip()):
            blocks.append(
                {
                    "id": f"block_{len(blocks) + 1:04d}",
                    "pageNumber": page_number,
                    "blockType": paragraph_type(text),
                    "textPreview": text[:500],
                    "sourceRegion": {
                        "source": "pdf_text",
                        "pageObject": page_object_id,
                        "contentObject": content_object_id,
                        "textIndex": index,
                    },
                }
            )

        pages.append(
            {
                "pageNumber": page_number,
                "width": None,
                "height": None,
                "unit": "unknown",
                "layoutBlocks": blocks,
            }
        )

    if not pages:
        warnings.append("PDF parsed but no text pages were found")

    return pages, warnings


def pdf_page_object_ids(payload: bytes) -> list[int]:
    objects = parse_pdf_objects(payload)
    page_ids = []
    for object_id, body in objects.items():
        if b"/Type /Page" in body and b"/Type /Pages" not in body:
            page_ids.append(object_id)
    return sorted(page_ids)


def pdf_has_image_objects(payload: bytes) -> bool:
    return b"/Subtype /Image" in payload or b"/XObject" in payload


def build_ocr_review_pages(page_count: int, source: str, warning: str, page_objects: list[int] | None = None) -> list[dict]:
    pages = []
    for index in range(page_count):
        page_number = index + 1
        source_region = {
            "source": source,
            "confidence": 0.0,
            "reviewStatus": "pending_review",
            "takeoverRequired": True,
        }
        if page_objects and index < len(page_objects):
            source_region["pageObject"] = page_objects[index]

        pages.append(
            {
                "pageNumber": page_number,
                "width": None,
                "height": None,
                "unit": "unknown",
                "layoutBlocks": [
                    {
                        "id": "block_0001",
                        "pageNumber": page_number,
                        "blockType": "ocr_candidate",
                        "textPreview": warning,
                        "confidence": 0.0,
                        "reviewStatus": "pending_review",
                        "takeoverRequired": True,
                        "sourceRegion": source_region,
                    }
                ],
            }
        )
    return pages


def parse_scanned_pdf_ocr_review(target: pathlib.Path) -> tuple[list[dict], list[str]]:
    payload = target.read_bytes()
    page_objects = pdf_page_object_ids(payload)
    page_count = max(1, len(page_objects))
    warning = "OCR engine unavailable; scanned PDF page requires manual review takeover"
    warnings = [warning]
    if not pdf_has_image_objects(payload):
        warnings.append("PDF has no extractable text stream or detectable image XObject")
    return build_ocr_review_pages(page_count, "pdf_scanned_ocr_review", warning, page_objects), warnings


def parse_scanned_image_ocr_review(target: pathlib.Path) -> tuple[list[dict], list[str]]:
    warning = "OCR engine unavailable; scanned image requires manual review takeover"
    if target.stat().st_size == 0:
        warning = "Invalid scanned image input; manual review takeover required"
    return build_ocr_review_pages(1, "image_ocr_review", warning), [warning]


def build_document_model(job_id: str, relative_path: str, target: pathlib.Path) -> dict:
    warnings = []
    adapter_name = "placeholder_document_adapter"
    adapter_version = "0.1"
    pages = None

    if target.suffix.lower() == ".docx":
        blocks, warnings = parse_docx_blocks(target)
        adapter_name = "openxml_docx_adapter"
        adapter_version = "0.1"
    elif target.suffix.lower() == ".pdf":
        pages, warnings = parse_text_pdf_pages(target)
        blocks = []
        adapter_name = "pdf_text_adapter"
        adapter_version = "0.1"
        if not any(page["layoutBlocks"] for page in pages):
            pages, warnings = parse_scanned_pdf_ocr_review(target)
            adapter_name = "scanned_ocr_review_adapter"
            adapter_version = "0.1"
    elif target.suffix.lower() in {".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff"}:
        pages, warnings = parse_scanned_image_ocr_review(target)
        blocks = []
        adapter_name = "scanned_ocr_review_adapter"
        adapter_version = "0.1"
    else:
        preview = read_text_preview(target)
        blocks = [
            {
                "id": "block_0001",
                "pageNumber": 1,
                "blockType": "raw_document",
                "textPreview": preview,
                "sourceRegion": None,
            }
        ]
        warnings = ["placeholder adapter: no Docling/OpenXML/PaddleOCR parsing executed"]

    if pages is None:
        pages = [
            {
                "pageNumber": 1,
                "width": None,
                "height": None,
                "unit": "unknown",
                "layoutBlocks": blocks,
            }
        ]

    document_model = {
        "schemaVersion": "document-model.v0.1",
        "jobId": job_id,
        "source": {
            "relativePath": relative_path,
            "inputSha256": sha256_file(target),
            "sizeBytes": target.stat().st_size,
        },
        "pages": pages,
    }
    document_model["_adapter"] = {
        "name": adapter_name,
        "version": adapter_version,
        "warnings": warnings,
    }
    return document_model


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
    adapter = document_model.pop("_adapter")
    output_sha256 = sha256_json(document_model)
    elapsed_ms = int((time.perf_counter() - started) * 1000)
    diagnostics = [
        {
            "adapterName": adapter["name"],
            "adapterVersion": adapter["version"],
            "toolName": "python",
            "toolVersion": platform.python_version(),
            "commandArgs": {
                "relativePath": args.relative_path,
                "simulateFailure": args.simulate_failure,
            },
            "durationMs": elapsed_ms,
            "inputSha256": document_model["source"]["inputSha256"],
            "outputSha256": output_sha256,
            "warnings": adapter["warnings"],
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
