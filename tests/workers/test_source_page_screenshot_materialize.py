from __future__ import annotations

import importlib.util
import struct
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "tools" / "source_page_screenshot_materialize.py"
SPEC = importlib.util.spec_from_file_location("source_page_screenshot_materialize", MODULE_PATH)
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = module
SPEC.loader.exec_module(module)


class SourcePageScreenshotMaterializeTests(unittest.TestCase):
    def test_builds_api_compatible_relative_path(self) -> None:
        self.assertEqual(
            module.relative_page_path(
                "curriculum_physics_junior_2022_2025_revision",
                2025,
                "ec5db25f-4336-4dc7-9d34-870e76ea0c8a",
                31,
            ),
            "generated/curriculum-physics-junior-2022-2025-revision/source-pages/2025/"
            "ec5db25f-4336-4dc7-9d34-870e76ea0c8a/page-031.png",
        )
        with self.assertRaisesRegex(ValueError, "unsafe material batch key"):
            module.relative_page_path("../outside", 2025, "doc", 1)

    def test_validates_png_signature_dimensions_and_nonempty_payload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "page.png"
            path.write_bytes(
                b"\x89PNG\r\n\x1a\n"
                + struct.pack(">I", 13)
                + b"IHDR"
                + struct.pack(">II", 1200, 1600)
                + b"\x08\x02\x00\x00\x00"
                + b"0" * 2048
            )
            quality = module.validate_png(path)
            self.assertEqual((quality["width"], quality["height"]), (1200, 1600))

            path.write_bytes(b"not a png")
            with self.assertRaisesRegex(ValueError, "invalid PNG"):
                module.validate_png(path)


if __name__ == "__main__":
    unittest.main()
