from __future__ import annotations

import json
import re
import sys
from pathlib import PurePath
from typing import Any


DIRECT_WINDOWS_POWERSHELL_PATTERNS = (
    re.compile(
        r"(^|[\s;&|()])(?:&\s*)?(?:['\"]?[^'\"\s]*[\\/])?"
        r"powershell(?:\.exe)?['\"]?(?=$|[\s;&|()])",
        re.IGNORECASE,
    ),
    re.compile(r"(^|\s)&\s*powershell(?:\.exe)?\b", re.IGNORECASE),
    re.compile(
        r"\bpowershell(?:\.exe)?\s+-(NoProfile|ExecutionPolicy|File|Command)\b",
        re.IGNORECASE,
    ),
    re.compile(r"(^|\s)powershell(?:\.exe)?\s", re.IGNORECASE),
)

SENSITIVE_FILE_NAMES = {
    ".env",
    "target.json",
    "id_rsa",
    "id_ed25519",
}


def _load_input() -> dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("hook input must be a JSON object")
    return data


def _tool_input(payload: dict[str, Any]) -> dict[str, Any]:
    raw = payload.get("tool_input")
    return raw if isinstance(raw, dict) else {}


def _path_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).replace("\\", "/")


def _is_sensitive_path(path_text: str) -> bool:
    normalized = _path_text(path_text).strip()
    if not normalized:
        return False
    parts = {part.lower() for part in PurePath(normalized).parts}
    lowered = normalized.lower()
    if parts.intersection(SENSITIVE_FILE_NAMES):
        return True
    return ".env." in lowered or "id_rsa" in lowered or "id_ed25519" in lowered


def _uses_direct_windows_powershell(command: str) -> bool:
    return any(pattern.search(command) for pattern in DIRECT_WINDOWS_POWERSHELL_PATTERNS)


def _block(reason: str) -> int:
    print(reason, file=sys.stderr)
    return 2


def main() -> int:
    try:
        payload = _load_input()
    except Exception as exc:
        return _block(f"Blocked by governed Claude Code hook: invalid hook input ({exc}).")

    tool_name = str(payload.get("tool_name") or "")
    tool_input = _tool_input(payload)

    if tool_name == "Bash":
        command = str(tool_input.get("command") or "")
        if _uses_direct_windows_powershell(command):
            return _block(
                "Blocked by governed Claude Code hook: use pwsh / PowerShell 7 or a repo helper "
                "instead of direct powershell.exe invocation."
            )

    if tool_name == "Read":
        path_text = _path_text(tool_input.get("file_path") or tool_input.get("path"))
        if _is_sensitive_path(path_text):
            return _block(
                "Blocked by governed Claude Code hook: sensitive local configuration or key material "
                "must not be read by default."
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
