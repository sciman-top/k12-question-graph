from pathlib import Path


def pdf_stream(lines: list[str]) -> str:
    body = ["BT", "/F1 12 Tf", "72 720 Td"]
    for index, line in enumerate(lines):
        if index:
            body.append("0 -18 Td")
        body.append(f"({line}) Tj")
    body.append("ET")
    return "\n".join(body)


def create_fixture(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    page1 = pdf_stream([
        "Q1 stem: constant force changes motion state.",
        "A. keep still",
        "B. speed changes",
    ])
    page2 = pdf_stream([
        "Answer: B",
        "Explanation: force can change motion state.",
    ])
    objects = [
        "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
        "2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>\nendobj\n",
        "3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n",
        f"4 0 obj\n<< /Length {len(page1.encode('latin-1'))} >>\nstream\n{page1}\nendstream\nendobj\n",
        "5 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>\nendobj\n",
        f"6 0 obj\n<< /Length {len(page2.encode('latin-1'))} >>\nstream\n{page2}\nendstream\nendobj\n",
    ]
    payload = "%PDF-1.4\n" + "".join(objects) + "trailer\n<< /Root 1 0 R >>\n%%EOF\n"
    path.write_bytes(payload.encode("latin-1"))


if __name__ == "__main__":
    create_fixture(Path("tmp/j002-text-pdf/j002-golden.pdf"))
