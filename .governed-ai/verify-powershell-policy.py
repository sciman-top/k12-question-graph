from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

DIRECT_WINDOWS_POWERSHELL_PATTERNS = (
    re.compile(r"(^|\s)&\s*powershell(?:\.exe)?\b", re.IGNORECASE),
    re.compile(r"\bpowershell(?:\.exe)?\s+-(NoProfile|ExecutionPolicy|File|Command)\b", re.IGNORECASE),
    re.compile(r"shell\s*:\s*powershell\b", re.IGNORECASE),
    re.compile(r"^-\s*powershell\s*:", re.IGNORECASE),
    re.compile(r"FilePath\s*=\s*['\"]powershell\.exe['\"]", re.IGNORECASE),
)
TEXT_SUFFIXES = {".ps1", ".psm1", ".cmd", ".bat", ".yml", ".yaml"}
SKIP_PARTS = {
    ".git",
    ".runtime",
    ".worktrees",
    "artifacts",
    "bin",
    "imports",
    "node_modules",
    "obj",
    "packages",
}


def _line_is_comment(line: str) -> bool:
    stripped = line.strip()
    return stripped.startswith("#") or stripped.startswith("//") or stripped.startswith("rem ")


def _iter_policy_files(repo_root: Path) -> list[Path]:
    files: list[Path] = []
    for path in repo_root.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(repo_root)
        if any(part in SKIP_PARTS for part in relative.parts):
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        files.append(path)
    return files


def main() -> int:
    violations: list[dict[str, str]] = []
    for path in _iter_policy_files(ROOT):
        relative = path.relative_to(ROOT)
        text = path.read_text(encoding="utf-8", errors="ignore")
        for line_number, line in enumerate(text.splitlines(), start=1):
            if _line_is_comment(line):
                continue
            if any(pattern.search(line) for pattern in DIRECT_WINDOWS_POWERSHELL_PATTERNS):
                violations.append(
                    {
                        "path": str(relative).replace("\\", "/"),
                        "line": str(line_number),
                        "text": line.strip(),
                    }
                )

    output = {
        "status": "pass" if not violations else "fail",
        "repo_root": str(ROOT),
        "violation_count": len(violations),
        "violations": violations,
        "remediation": "Use pwsh / PowerShell 7, or a Resolve-PowerShellExecutable helper that checks pwsh first. Only use powershell.exe behind an explicit legacy escape hatch.",
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))
    return 0 if not violations else 1


if __name__ == "__main__":
    raise SystemExit(main())
