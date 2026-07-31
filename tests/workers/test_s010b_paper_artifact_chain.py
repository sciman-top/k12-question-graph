from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "tools" / "s010b_paper_artifact_chain.py"
SPEC = importlib.util.spec_from_file_location("s010b_paper_artifact_chain", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class S010BPaperArtifactChainTests(unittest.TestCase):
    def test_short_single_question_paper_has_proportional_text_threshold(self) -> None:
        self.assertEqual(MODULE.minimum_substantive_text_length(1), 50)
        self.assertEqual(MODULE.minimum_substantive_text_length(20), 400)

    def test_answer_variant_preserves_source_and_knowledge_version(self) -> None:
        body, image_paths = MODULE.question_docx_body(
            {
                "basketTitle": "测试卷",
                "questions": [
                    {
                        "title": "速度计算",
                        "answer": "5m/s",
                        "solution": "速度等于路程除以时间。",
                        "sourceAuthorizationStatus": "authorized",
                        "knowledgeVersionStatus": "active",
                        "knowledgeVersion": 1,
                    }
                ],
            },
            "answer",
        )

        self.assertEqual(image_paths, [])
        self.assertIn("来源授权：authorized", body)
        self.assertIn("版本引用：active v1", body)


if __name__ == "__main__":
    unittest.main()
