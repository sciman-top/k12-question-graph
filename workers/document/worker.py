import argparse
import hashlib
import json
import pathlib
import platform
import re
import shutil
import subprocess
import sys
import time
import tempfile
import zipfile
import xml.etree.ElementTree as ET


WORD_NS = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "m": "http://schemas.openxmlformats.org/officeDocument/2006/math",
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKER_TEMP_ROOT = REPO_ROOT / "tmp" / "worker-temp"
MAX_INPUT_BYTES = 128 * 1024 * 1024
MAX_DOCX_DOCUMENT_XML_BYTES = 32 * 1024 * 1024
MAX_DOCX_RELATIONSHIPS_XML_BYTES = 4 * 1024 * 1024
MAX_DOCX_DOCUMENT_XML_COMPRESSION_RATIO = 200


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


def create_worker_temp_dir(prefix: str) -> pathlib.Path:
    WORKER_TEMP_ROOT.mkdir(parents=True, exist_ok=True)
    return pathlib.Path(tempfile.mkdtemp(prefix=prefix, dir=str(WORKER_TEMP_ROOT)))


def resolve_input_path(file_root: pathlib.Path, relative_path: str) -> pathlib.Path:
    root = file_root.resolve()
    relative = pathlib.PurePosixPath(relative_path)
    if not relative.parts or relative.is_absolute() or any(part in {"", ".", ".."} for part in relative.parts):
        raise ValueError("input path must be a normalized relative path")

    target = (root / pathlib.Path(*relative.parts)).resolve()
    try:
        target.relative_to(root)
    except ValueError as exc:
        raise ValueError("input path escapes the configured file root") from exc
    return target


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


def formula_payload(element: ET.Element) -> dict:
    formulas = []
    for formula in element.findall(".//m:oMath", WORD_NS) + element.findall(".//m:oMathPara", WORD_NS):
        omml = ET.tostring(formula, encoding="unicode")
        text = element_text(formula)
        if not omml:
            continue
        formulas.append(
            {
                "sourceFormat": "omml",
                "omml": omml,
                "latex": text,
                "mathml": "",
                "text": text,
                "confidence": 1.0,
                "reviewStatus": "verified",
                "fallbackImageRequired": False,
            }
        )
    return {
        "source": "openxml",
        "sourceFormat": "omml",
        "formulas": formulas,
    }


def parse_docx_blocks(target: pathlib.Path) -> tuple[list[dict], list[str]]:
    warnings: list[str] = []
    blocks: list[dict] = []

    try:
        with zipfile.ZipFile(target) as docx:
            document_info = docx.getinfo("word/document.xml")
            compression_ratio = document_info.file_size / max(document_info.compress_size, 1)
            if document_info.file_size > MAX_DOCX_DOCUMENT_XML_BYTES:
                return [], ["OpenXML document.xml exceeds the safe uncompressed size limit"]
            if compression_ratio > MAX_DOCX_DOCUMENT_XML_COMPRESSION_RATIO:
                return [], ["OpenXML document.xml exceeds the safe compression ratio"]

            document_xml = docx.read(document_info)
            rel_targets: dict[str, str] = {}
            try:
                rels_info = docx.getinfo("word/_rels/document.xml.rels")
            except KeyError:
                rels_info = None
            if rels_info is not None:
                rels_ratio = rels_info.file_size / max(rels_info.compress_size, 1)
                if (
                    rels_info.file_size > MAX_DOCX_RELATIONSHIPS_XML_BYTES
                    or rels_ratio > MAX_DOCX_DOCUMENT_XML_COMPRESSION_RATIO
                ):
                    warnings.append("OpenXML relationships exceed safe archive limits; image links require review")
                else:
                    rels_root = ET.fromstring(docx.read(rels_info))
                    for rel in rels_root:
                        rel_id = rel.attrib.get("Id")
                        target_attr = rel.attrib.get("Target")
                        rel_type = rel.attrib.get("Type", "")
                        if rel_id and target_attr and rel_type.endswith("/image"):
                            rel_targets[rel_id] = target_attr

        root = ET.fromstring(document_xml)
    except (zipfile.BadZipFile, zipfile.LargeZipFile, KeyError, ET.ParseError, OSError) as exc:
        return [], [f"Invalid OpenXML document: {exc}"]
    body = root.find("w:body", WORD_NS)
    if body is None:
        return blocks, ["OpenXML document body missing"]

    for child in list(body):
        tag = child.tag.rsplit("}", 1)[-1]
        if tag == "p":
            text = element_text(child)
            has_formula = child.find(".//m:oMath", WORD_NS) is not None or child.find(".//m:oMathPara", WORD_NS) is not None
            image_refs = [
                blip.attrib.get(f"{{{WORD_NS['r']}}}embed")
                for blip in child.findall(".//a:blip", WORD_NS)
                if blip.attrib.get(f"{{{WORD_NS['r']}}}embed")
            ]
            if not text and not has_formula and not image_refs:
                continue

            if text or has_formula:
                block_type = "formula" if has_formula else paragraph_type(text)
                block = {
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
                if has_formula:
                    block["formula"] = formula_payload(child)
                blocks.append(block)

            for rel_id in image_refs:
                blocks.append(
                    {
                        "id": f"block_{len(blocks) + 1:04d}",
                        "pageNumber": 1,
                        "blockType": "image",
                        "textPreview": rel_targets.get(rel_id, rel_id),
                        "sourceRegion": {
                            "source": "openxml",
                            "element": "w:drawing",
                            "relationshipId": rel_id,
                            "target": rel_targets.get(rel_id),
                            "index": len(blocks),
                        },
                        "asset": {
                            "relationshipId": rel_id,
                            "target": rel_targets.get(rel_id),
                            "assetType": "image",
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


def split_pdf_text_blocks(text: str, page_number: int, body_started: bool) -> tuple[list[dict], bool]:
    lines = [line.strip() for line in text.splitlines()]
    groups: list[tuple[str, list[str]]] = []
    current_kind = "document_header"
    current_lines: list[str] = []
    question_pattern = re.compile(r"^(\d{1,2})\s*[\.．、]\s*(.+)$")
    option_pattern = re.compile(r"^[ABCD][\.．]\s*(.+)$")
    section_pattern = re.compile(r"^(第[一二三四]部分|[一二三四]、|参考答案)")

    for line in lines:
        if not line:
            continue

        if not body_started:
            current_kind = "document_header"
            current_lines.append(line)
            if section_pattern.search(line):
                body_started = True
            continue

        next_kind = None
        starts_new_question = False
        if question_pattern.match(line):
            next_kind = "question_stem"
            starts_new_question = True
        elif option_pattern.match(line):
            next_kind = "option"
        elif line.startswith(("答案", "参考答案")) or "参考答案" in line:
            next_kind = "answer"
        elif "解析" in line:
            next_kind = "explanation"
        elif not current_lines:
            next_kind = "document_header"

        if current_lines and (starts_new_question or (next_kind and next_kind != current_kind)):
            groups.append((current_kind, current_lines))
            current_lines = []

        if next_kind:
            current_kind = next_kind

        current_lines.append(line)

    if current_lines:
        groups.append((current_kind, current_lines))

    blocks = []
    for index, (block_type, block_lines) in enumerate(groups):
        preview = " ".join(block_lines).strip()
        if not preview:
            continue
        blocks.append(
            {
                "id": f"block_{len(blocks) + 1:04d}",
                "pageNumber": page_number,
                "blockType": block_type,
                "textPreview": preview[:1000],
                "confidence": 0.88 if block_type == "question_stem" else 0.78,
                "reviewStatus": "pending_review",
                "takeoverRequired": block_type != "question_stem",
                "sourceRegion": {
                    "source": "pdftotext_layout",
                    "pageNumber": page_number,
                    "textGroupIndex": index,
                },
            }
        )

    return blocks, body_started


def parse_pdf_with_pdftotext(target: pathlib.Path) -> tuple[list[dict], list[str]]:
    pdftotext = shutil.which("pdftotext")
    if not pdftotext:
        return [], ["pdftotext unavailable; falling back to internal PDF parser"]

    tmp_dir = create_worker_temp_dir("kqg-pdftotext-")
    try:
        output_path = tmp_dir / "document.txt"
        try:
            completed = subprocess.run(
                [pdftotext, "-layout", "-enc", "UTF-8", str(target), str(output_path)],
                text=True,
                capture_output=True,
                timeout=60,
            )
        except subprocess.TimeoutExpired:
            return [], ["pdftotext timed out while extracting PDF text"]
        except OSError as exc:
            return [], [f"pdftotext failed to start: {exc}"]
        if completed.returncode != 0:
            warning = completed.stderr.strip() or completed.stdout.strip() or "pdftotext failed"
            return [], [warning]

        text = output_path.read_text(encoding="utf-8", errors="replace")
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)

    pages = []
    body_started = False
    for page_number, page_text in enumerate(text.split("\f"), start=1):
        blocks, body_started = split_pdf_text_blocks(page_text, page_number, body_started)
        if not blocks and not page_text.strip():
            continue
        pages.append(
            {
                "pageNumber": page_number,
                "width": None,
                "height": None,
                "unit": "unknown",
                "layoutBlocks": blocks,
            }
        )

    if not pages or not any(page["layoutBlocks"] for page in pages):
        return [], ["pdftotext produced no usable text blocks"]

    return pages, []


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


def load_rapidocr_engine():
    try:
        from rapidocr_onnxruntime import RapidOCR
    except Exception as exc:
        return None, f"rapidocr_onnxruntime unavailable: {exc}"

    try:
        return RapidOCR(), ""
    except Exception as exc:
        return None, f"RapidOCR initialization failed: {exc}"


def normalize_rapidocr_result(result) -> list[dict]:
    lines: list[dict] = []
    if not result:
        return lines

    for item in result:
        if not isinstance(item, (list, tuple)) or len(item) < 3:
            continue
        box, text, confidence = item[0], str(item[1]).strip(), item[2]
        if not text:
            continue
        try:
            confidence_value = float(confidence)
        except (TypeError, ValueError):
            confidence_value = 0.0

        xs = [float(point[0]) for point in box if isinstance(point, (list, tuple)) and len(point) >= 2]
        ys = [float(point[1]) for point in box if isinstance(point, (list, tuple)) and len(point) >= 2]
        source_region = {
            "source": "rapidocr_onnxruntime",
            "confidence": round(confidence_value, 4),
            "reviewStatus": "pending_review",
            "takeoverRequired": confidence_value < 0.9,
        }
        if xs and ys:
            source_region.update(
                {
                    "x": min(xs),
                    "y": min(ys),
                    "width": max(xs) - min(xs),
                    "height": max(ys) - min(ys),
                    "unit": "pixel",
                }
            )

        lines.append(
            {
                "text": text,
                "confidence": confidence_value,
                "sourceRegion": source_region,
            }
        )
    return lines


def ocr_lines_to_pages(page_lines: list[list[dict]], source: str) -> list[dict]:
    pages: list[dict] = []
    for page_index, lines in enumerate(page_lines):
        page_number = page_index + 1
        blocks = []
        for line_index, line in enumerate(lines):
            confidence = line["confidence"]
            blocks.append(
                {
                    "id": f"block_{line_index + 1:04d}",
                    "pageNumber": page_number,
                    "blockType": paragraph_type(line["text"]),
                    "textPreview": line["text"][:500],
                    "confidence": round(confidence, 4),
                    "reviewStatus": "pending_review",
                    "takeoverRequired": confidence < 0.9,
                    "sourceRegion": line["sourceRegion"] | {"pageNumber": page_number, "source": source},
                }
            )
        pages.append(
            {
                "pageNumber": page_number,
                "width": None,
                "height": None,
                "unit": "pixel",
                "layoutBlocks": blocks,
            }
        )
    return pages


def parse_image_with_rapidocr(target: pathlib.Path) -> tuple[list[dict], list[str]]:
    engine, error = load_rapidocr_engine()
    if engine is None:
        return [], [error]

    try:
        result, elapsed = engine(str(target))
    except Exception as exc:
        return [], [f"RapidOCR image recognition failed: {exc}"]

    lines = normalize_rapidocr_result(result)
    warnings = [f"RapidOCR elapsed={elapsed}"]
    if not lines:
        warnings.append("RapidOCR produced no text lines")
    return ocr_lines_to_pages([lines], "rapidocr_image_ocr"), warnings


def resolve_pdftoppm() -> str | None:
    candidates = ["pdftoppm.exe", "pdftoppm"] if platform.system() == "Windows" else ["pdftoppm"]
    return next((resolved for candidate in candidates if (resolved := shutil.which(candidate))), None)


def render_pdf_pages_with_pdftoppm(target: pathlib.Path, output_dir: pathlib.Path) -> tuple[list[pathlib.Path], list[str]]:
    pdftoppm = resolve_pdftoppm()
    if pdftoppm is None:
        return [], ["pdftoppm unavailable; scanned PDF cannot be rendered for local OCR"]

    prefix = output_dir / "page"
    command = [pdftoppm, "-r", "200", "-png", str(target), str(prefix)]
    try:
        completed = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
    except subprocess.TimeoutExpired:
        return [], ["pdftoppm timed out while rendering scanned PDF"]
    except OSError as exc:
        return [], [f"pdftoppm failed to start: {exc}"]

    warnings: list[str] = []
    if completed.returncode != 0:
        message = completed.stderr.strip() or completed.stdout.strip() or f"exit_code={completed.returncode}"
        warnings.append(f"pdftoppm failed: {message}")
        return [], warnings

    rendered = sorted(output_dir.glob("page-*.png"))
    if not rendered:
        warnings.append("pdftoppm produced no page images")
    return rendered, warnings


def parse_scanned_pdf_with_rapidocr(target: pathlib.Path) -> tuple[list[dict], list[str]]:
    engine, error = load_rapidocr_engine()
    if engine is None:
        return [], [error]

    temp_dir = create_worker_temp_dir("kqg-pdf-ocr-")
    try:
        page_images, warnings = render_pdf_pages_with_pdftoppm(target, temp_dir)
        if not page_images:
            return [], warnings

        page_lines: list[list[dict]] = []
        for page_image in page_images:
            try:
                result, elapsed = engine(str(page_image))
            except Exception as exc:
                warnings.append(f"RapidOCR PDF page recognition failed for {page_image.name}: {exc}")
                page_lines.append([])
                continue

            lines = normalize_rapidocr_result(result)
            if not lines:
                warnings.append(f"RapidOCR produced no text lines for {page_image.name}")
            else:
                warnings.append(f"RapidOCR {page_image.name} elapsed={elapsed}")
            page_lines.append(lines)

        pages = ocr_lines_to_pages(page_lines, "rapidocr_pdf_ocr")
        if not any(page["layoutBlocks"] for page in pages):
            return [], warnings + ["RapidOCR produced no usable scanned PDF text blocks"]
        return pages, warnings
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


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


def pdf_text_is_too_sparse(pages: list[dict]) -> bool:
    if len(pages) < 2:
        return False
    text_character_count = sum(
        len(str(block.get("textPreview") or "").strip())
        for page in pages
        for block in page.get("layoutBlocks", [])
    )
    return text_character_count < len(pages) * 40


def build_document_model(job_id: str, relative_path: str, target: pathlib.Path) -> dict:
    warnings = []
    adapter_name = "unsupported_document_adapter"
    adapter_version = "0.1"
    pages = None

    if target.suffix.lower() == ".docx":
        blocks, warnings = parse_docx_blocks(target)
        adapter_name = "openxml_docx_adapter"
        adapter_version = "0.1"
    elif target.suffix.lower() == ".pdf":
        pages, warnings = parse_pdf_with_pdftotext(target)
        if not any(page["layoutBlocks"] for page in pages):
            pages, warnings = parse_text_pdf_pages(target)
        blocks = []
        adapter_name = "pdf_text_adapter"
        adapter_version = "0.1"
        requires_ocr = not any(page["layoutBlocks"] for page in pages) or pdf_text_is_too_sparse(pages)
        if requires_ocr:
            sparse_warning = "PDF text layer is empty or too sparse; RapidOCR fallback selected"
            pages, ocr_warnings = parse_scanned_pdf_with_rapidocr(target)
            warnings = warnings + [sparse_warning] + ocr_warnings
            adapter_name = "rapidocr_scanned_pdf_adapter"
            adapter_version = "0.1"
            if not any(page["layoutBlocks"] for page in pages):
                review_pages, review_warnings = parse_scanned_pdf_ocr_review(target)
                pages = review_pages
                warnings = warnings + review_warnings
                adapter_name = "scanned_ocr_review_adapter"
    elif target.suffix.lower() in {".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff"}:
        pages, warnings = parse_image_with_rapidocr(target)
        blocks = []
        adapter_name = "rapidocr_image_adapter"
        adapter_version = "0.1"
        if not any(page["layoutBlocks"] for page in pages):
            review_pages, review_warnings = parse_scanned_image_ocr_review(target)
            pages = review_pages
            warnings = warnings + review_warnings
            adapter_name = "scanned_ocr_review_adapter"
    else:
        raise ValueError(f"unsupported_document_type:{target.suffix.lower() or '<none>'}")

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
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8")

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

    try:
        target = resolve_input_path(pathlib.Path(args.file_root), args.relative_path)
    except ValueError as exc:
        print(f"invalid input path: {exc}", file=sys.stderr)
        return 4
    if not target.is_file():
        print(f"input file missing: {target}", file=sys.stderr)
        return 3
    if target.stat().st_size > MAX_INPUT_BYTES:
        print(f"input file exceeds {MAX_INPUT_BYTES} bytes", file=sys.stderr)
        return 5

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
