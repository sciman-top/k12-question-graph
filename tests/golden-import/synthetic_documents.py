"""合成能力样例文档构造器(纯 stdlib、确定性输出)。

golden 输出回归的输入端:与 tests/golden-import/registry.json 的能力意图对应,
但内容全部合成,不含任何真实学生、学校或版权材料。
"""

from __future__ import annotations

import pathlib
import zipfile

DOCX_BLOCK_CASE = "docx-blocks"
PDF_TEXT_QUESTIONS_CASE = "pdf-text-questions"
PDF_SPARSE_OCR_TAKEOVER_CASE = "pdf-sparse-ocr-takeover"

ALL_CASES = (DOCX_BLOCK_CASE, PDF_TEXT_QUESTIONS_CASE, PDF_SPARSE_OCR_TAKEOVER_CASE)


def build_capability_docx(path: pathlib.Path) -> None:
    stem = "<w:p><w:r><w:t xml:space=\"preserve\">1. 下列关于声现象的说法正确的是</w:t></w:r></w:p>"
    option = "<w:p><w:r><w:t xml:space=\"preserve\">A. 声音由物体振动产生</w:t></w:r></w:p>"
    answer = "<w:p><w:r><w:t xml:space=\"preserve\">答案:B</w:t></w:r></w:p>"
    explanation = "<w:p><w:r><w:t xml:space=\"preserve\">解析:声音由振动产生。</w:t></w:r></w:p>"
    table = (
        "<w:tbl>"
        "<w:tr><w:tc><w:p><w:r><w:t>装置</w:t></w:r></w:p></w:tc>"
        "<w:tc><w:p><w:r><w:t>现象</w:t></w:r></w:p></w:tc></w:tr>"
        "<w:tr><w:tc><w:p><w:r><w:t>音叉</w:t></w:r></w:p></w:tc>"
        "<w:tc><w:p><w:r><w:t>发声时轻球被弹开</w:t></w:r></w:p></w:tc></w:tr>"
        "</w:tbl>"
    )
    formula = (
        "<w:p><m:oMathPara><m:oMath><m:r><m:t>v=s/t</m:t></m:r></m:oMath></m:oMathPara></w:p>"
    )
    image = (
        "<w:p><w:r><w:drawing>"
        "<a:blip r:embed=\"rId7\"/>"
        "</w:drawing></w:r></w:p>"
    )
    document_xml = (
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
        "xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\" "
        "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
        "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        f"<w:body>{stem}{option}{answer}{explanation}{table}{formula}{image}</w:body></w:document>"
    )
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("word/document.xml", document_xml)


def _pdf_object(number: int, body: str) -> bytes:
    return f"{number} 0 obj\n{body}\nendobj\n".encode("utf-8")


def _content_stream(lines: list[str]) -> str:
    statements = "\n".join(f"({line}) Tj" for line in lines)
    return f"<< /Length {len(statements.encode('utf-8'))} >>\nstream\n{statements}\nendstream"


def build_text_question_pdf(path: pathlib.Path) -> None:
    # 单页、足量文本:命中内部文本 PDF 解析器,不触发 OCR 分支。
    page_one_content = _content_stream(
        [
            "2016 学年学业水平检测",
            "1. 关于声现象,下列说法正确的是",
            "A. 声音由物体振动产生",
            "B. 声音可以在真空中传播",
            "答案 A",
            "解析:真空不能传声。",
        ]
    )
    parts = [
        b"%PDF-1.4\n",
        _pdf_object(1, "<< /Type /Catalog /Pages 2 0 R >>"),
        _pdf_object(2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
        _pdf_object(3, "<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>"),
        _pdf_object(4, page_one_content),
        b"trailer\n<< /Root 1 0 R >>\n%%EOF",
    ]
    path.write_bytes(b"".join(parts))


def build_sparse_scanned_pdf(path: pathlib.Path) -> None:
    # 两页、每页极少字符:触发稀疏判定 -> OCR 不可用 -> fail-closed 人工接管块。
    page_one_content = _content_stream(["x"])
    page_two_content = _content_stream(["y"])
    parts = [
        b"%PDF-1.4\n",
        _pdf_object(1, "<< /Type /Catalog /Pages 2 0 R >>"),
        _pdf_object(2, "<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>"),
        _pdf_object(3, "<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>"),
        _pdf_object(4, page_one_content),
        _pdf_object(5, "<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>"),
        _pdf_object(6, page_two_content),
        b"trailer\n<< /Root 1 0 R >>\n%%EOF",
    ]
    path.write_bytes(b"".join(parts))


CASE_BUILDERS = {
    DOCX_BLOCK_CASE: (build_capability_docx, "original/capability.docx"),
    PDF_TEXT_QUESTIONS_CASE: (build_text_question_pdf, "original/text-questions.pdf"),
    PDF_SPARSE_OCR_TAKEOVER_CASE: (build_sparse_scanned_pdf, "original/sparse-scanned.pdf"),
}
