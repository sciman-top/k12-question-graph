import pathlib
import sys
import unittest
from unittest import mock


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOLS_ROOT = REPO_ROOT / "tools"
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

import host_capability_diagnostic  # noqa: E402


class HostCapabilityDiagnosticTests(unittest.TestCase):
    def test_command_path_prefers_pdftoppm_executable_on_windows(self) -> None:
        candidates = {
            "pdftoppm.exe": r"C:\tools\poppler\pdftoppm.exe",
            "pdftoppm": r"C:\broken-wrapper\pdftoppm.cmd",
        }
        with (
            mock.patch.object(host_capability_diagnostic.os, "name", "nt"),
            mock.patch.object(
                host_capability_diagnostic.shutil,
                "which",
                side_effect=candidates.get,
            ) as which,
        ):
            resolved = host_capability_diagnostic.command_path("pdftoppm")

        self.assertEqual(resolved, candidates["pdftoppm.exe"])
        which.assert_called_once_with("pdftoppm.exe")


if __name__ == "__main__":
    unittest.main()
