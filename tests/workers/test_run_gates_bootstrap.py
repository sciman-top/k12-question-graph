from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
RUN_GATES_PATH = REPO_ROOT / "tools" / "run-gates.ps1"


class RunGatesBootstrapTests(unittest.TestCase):
    def test_process_pause_checks_do_not_call_undefined_assert_true(self) -> None:
        script = RUN_GATES_PATH.read_text(encoding="utf-8-sig")

        self.assertNotIn(
            "Assert-True ($null -eq $stillRunning)",
            script,
            "run-gates must use its own explicit process check before entering try/finally",
        )


if __name__ == "__main__":
    unittest.main()
