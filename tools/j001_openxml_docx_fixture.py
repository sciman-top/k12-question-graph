import pathlib
import zipfile


CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
"""

RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
"""

DOCUMENT = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
  <w:body>
    <w:p><w:r><w:t>题干：一个物体受到恒力作用，运动状态如何变化？</w:t></w:r></w:p>
    <w:p><w:r><w:t>A. 保持静止</w:t></w:r></w:p>
    <w:p><w:r><w:t>B. 速度发生变化</w:t></w:r></w:p>
    <w:p><w:r><w:t>答案：B</w:t></w:r></w:p>
    <w:p><w:r><w:t>解析：根据牛顿第二定律，合力会改变物体运动状态。</w:t></w:r></w:p>
    <w:tbl>
      <w:tr><w:tc><w:p><w:r><w:t>物理量</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>单位</w:t></w:r></w:p></w:tc></w:tr>
      <w:tr><w:tc><w:p><w:r><w:t>力</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>N</w:t></w:r></w:p></w:tc></w:tr>
    </w:tbl>
    <w:p><w:r><w:t>公式：</w:t></w:r><m:oMath><m:r><m:t>F=ma</m:t></m:r></m:oMath></w:p>
  </w:body>
</w:document>
"""


def create_fixture(path: pathlib.Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as docx:
        docx.writestr("[Content_Types].xml", CONTENT_TYPES)
        docx.writestr("_rels/.rels", RELS)
        docx.writestr("word/document.xml", DOCUMENT)


if __name__ == "__main__":
    create_fixture(pathlib.Path("tmp/j001-openxml-docx/j001-golden.docx"))
