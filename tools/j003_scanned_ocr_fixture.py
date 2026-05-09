from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


OCR_FIXTURE_TEXT = "1. 咸鱼放在冰箱冷冻室里一晚，冷冻室内有咸鱼味。"


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for candidate in (Path(r"C:\Windows\Fonts\simhei.ttf"), Path(r"C:\Windows\Fonts\simsun.ttc")):
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def create_scanned_image(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (1100, 220), "white")
    draw = ImageDraw.Draw(image)
    font = load_font(42)
    draw.text((30, 42), OCR_FIXTURE_TEXT, fill="black", font=font)
    draw.text((30, 116), "问：这说明分子在不停地做无规则运动。", fill="black", font=font)
    image.save(path)


def create_scanned_pdf(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image_path = path.with_suffix(".png")
    create_scanned_image(image_path)
    Image.open(image_path).save(path, "PDF", resolution=200.0)


def create_invalid_image(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"")


if __name__ == "__main__":
    root = Path("tmp/j003-scanned-ocr")
    create_scanned_pdf(root / "j003-scanned.pdf")
    create_scanned_image(root / "j003-scanned.png")
    create_invalid_image(root / "j003-invalid.png")
