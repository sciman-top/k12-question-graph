from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
import uuid
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HELPER_PATH = REPO_ROOT / "tools" / "real005b-runtime-roots.ps1"


def ps_literal(value: Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def invoke_initializer(source: Path, runtime: Path) -> subprocess.CompletedProcess[str]:
    command = (
        f". {ps_literal(HELPER_PATH)}; "
        f"Initialize-Real005bRuntimeRoots -RepoRoot {ps_literal(REPO_ROOT)} "
        f"-RuntimeFileStoreRoot {ps_literal(runtime)} "
        f"-SourceFileStoreRoot {ps_literal(source)} | ConvertTo-Json -Compress"
    )
    return subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        capture_output=True,
        check=False,
        encoding="utf-8",
        errors="replace",
    )


class Real005BRuntimeRootsTests(unittest.TestCase):
    def test_same_source_and_runtime_reuses_files_without_deleting_them(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            file_store = Path(temp_dir) / "file_store"
            original = file_store / "original"
            generated = file_store / "generated"
            original.mkdir(parents=True)
            generated.mkdir()
            sentinel = original / "sentinel.pdf"
            sentinel.write_bytes(b"preserve-me")

            result = invoke_initializer(file_store, file_store)

            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertTrue(report["ReusesSourceFileStore"])
            self.assertEqual(sentinel.read_bytes(), b"preserve-me")

    def test_different_runtime_outside_repo_tmp_is_rejected_without_deleting(self) -> None:
        with tempfile.TemporaryDirectory() as source_dir, tempfile.TemporaryDirectory() as runtime_dir:
            source = Path(source_dir) / "file_store"
            (source / "original").mkdir(parents=True)
            (source / "generated").mkdir()
            runtime = Path(runtime_dir) / "file_store"
            (runtime / "original").mkdir(parents=True)
            sentinel = runtime / "original" / "sentinel.pdf"
            sentinel.write_bytes(b"preserve-me")

            result = invoke_initializer(source, runtime)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must stay under", result.stderr)
            self.assertEqual(sentinel.read_bytes(), b"preserve-me")

    def test_different_runtime_under_repo_tmp_links_source_directories(self) -> None:
        test_root = REPO_ROOT / "tmp" / f"real005b-runtime-test-{uuid.uuid4().hex}"
        try:
            source = test_root / "source" / "file_store"
            runtime = test_root / "runtime" / "data" / "file_store"
            (source / "original").mkdir(parents=True)
            (source / "generated").mkdir()
            (source / "original" / "sentinel.pdf").write_bytes(b"linked")

            result = invoke_initializer(source, runtime)

            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertFalse(report["ReusesSourceFileStore"])
            self.assertEqual((runtime / "original" / "sentinel.pdf").read_bytes(), b"linked")
        finally:
            if test_root.exists():
                subprocess.run(
                    [
                        "pwsh",
                        "-NoProfile",
                        "-Command",
                        f"Remove-Item -LiteralPath {ps_literal(test_root)} -Recurse -Force",
                    ],
                    check=False,
                    capture_output=True,
                    encoding="utf-8",
                    errors="replace",
                )


if __name__ == "__main__":
    unittest.main()
