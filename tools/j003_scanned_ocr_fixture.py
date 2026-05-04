from pathlib import Path


def create_scanned_pdf(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image_payload = "synthetic scanned page image bytes"
    objects = [
        "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
        "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n",
        "3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << /XObject << /Im1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n",
        f"4 0 obj\n<< /Type /XObject /Subtype /Image /Width 64 /Height 64 /ColorSpace /DeviceGray /BitsPerComponent 8 /Length {len(image_payload)} >>\nstream\n{image_payload}\nendstream\nendobj\n",
        "5 0 obj\n<< /Length 16 >>\nstream\nq /Im1 Do Q\nendstream\nendobj\n",
    ]
    payload = "%PDF-1.4\n" + "".join(objects) + "trailer\n<< /Root 1 0 R >>\n%%EOF\n"
    path.write_bytes(payload.encode("latin-1"))


def create_invalid_image(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"")


if __name__ == "__main__":
    root = Path("tmp/j003-scanned-ocr")
    create_scanned_pdf(root / "j003-scanned.pdf")
    create_invalid_image(root / "j003-invalid.png")
