import pathlib
import sys
import tempfile
import unittest

from PIL import Image, ImageDraw
from pypdf import PdfWriter


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOLS_ROOT = REPO_ROOT / "tools"
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

import guangzhou_physics_2016_2025_source_region_screenshots as screenshots  # noqa: E402


class GuangzhouSourceRegionScreenshotTests(unittest.TestCase):
    def test_generated_page_path_is_scoped_to_material_batch(self) -> None:
        path = screenshots.generated_page_relative_path(
            "guangzhou_physics_2015_2025_20260726_v2",
            2025,
            "source-id",
            8,
        )

        self.assertEqual(
            path,
            "generated/guangzhou-physics-2015-2025-20260726-v2/source-pages/2025/source-id/page-008.png",
        )

    def test_image_quality_rejects_blank_and_accepts_content(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            blank = root / "blank.png"
            content = root / "content.png"
            Image.new("RGB", (400, 300), "white").save(blank)
            content_image = Image.new("RGB", (400, 300), "white")
            ImageDraw.Draw(content_image).rectangle((50, 50, 350, 250), fill="black")
            content_image.save(content)

            self.assertFalse(screenshots.image_quality(blank)["nonBlank"])
            self.assertTrue(screenshots.image_quality(content)["nonBlank"])

    def test_pdf_page_count_uses_structured_reader(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = pathlib.Path(temp_dir) / "three-pages.pdf"
            writer = PdfWriter()
            for _ in range(3):
                writer.add_blank_page(width=100, height=100)
            with path.open("wb") as stream:
                writer.write(stream)

            self.assertEqual(screenshots.pdf_page_count(path), 3)


if __name__ == "__main__":
    unittest.main()
