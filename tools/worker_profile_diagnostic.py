from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def run_command(args: list[str], timeout: int = 10) -> dict[str, Any]:
    try:
        completed = subprocess.run(
            args,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
        )
        return {
            "available": completed.returncode == 0,
            "exitCode": completed.returncode,
            "stdout": completed.stdout.strip(),
            "stderr": completed.stderr.strip(),
        }
    except Exception as exc:
        return {
            "available": False,
            "exitCode": None,
            "stdout": "",
            "stderr": str(exc),
        }


def import_available(module_name: str) -> bool:
    code = f"import {module_name}; print('ok')"
    result = run_command([sys.executable, "-c", code], timeout=15)
    return result["available"] and result["stdout"].endswith("ok")


def get_windows_memory_gb() -> float | None:
    if platform.system().lower() != "windows" or not command_exists("powershell"):
        return None
    result = run_command(
        [
            "powershell",
            "-NoProfile",
            "-Command",
            "(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory",
        ]
    )
    if not result["available"]:
        return None
    try:
        return round(int(result["stdout"].splitlines()[-1]) / (1024**3), 2)
    except Exception:
        return None


def get_nvidia_gpu() -> dict[str, Any]:
    if not command_exists("nvidia-smi"):
        return {"available": False, "gpus": []}
    result = run_command(
        [
            "nvidia-smi",
            "--query-gpu=name,memory.total,driver_version",
            "--format=csv,noheader,nounits",
        ],
        timeout=15,
    )
    gpus = []
    if result["available"]:
        for line in result["stdout"].splitlines():
            parts = [part.strip() for part in line.split(",")]
            if len(parts) >= 3:
                gpus.append(
                    {
                        "name": parts[0],
                        "memoryMb": int(parts[1]) if parts[1].isdigit() else None,
                        "driverVersion": parts[2],
                    }
                )
    return {"available": bool(gpus), "gpus": gpus, "raw": result}


def recommend_profile(facts: dict[str, Any]) -> dict[str, Any]:
    rapidocr = facts["pythonModules"]["rapidocr_onnxruntime"]
    paddleocr = facts["pythonModules"]["paddleocr"]
    paddle = facts["pythonModules"]["paddle"]
    conda = facts["commands"]["conda"]
    docker = facts["commands"]["docker"]
    wsl = facts["commands"]["wsl"]
    gpu = facts["gpu"]["available"]
    max_gpu_mem = max([gpu_info.get("memoryMb") or 0 for gpu_info in facts["gpu"]["gpus"]] or [0])

    if rapidocr:
        default_profile = "direct_venv_lite"
        reason = "RapidOCR/ONNX is available in the current interpreter; use the lightweight local profile first."
    else:
        default_profile = "uv_venv_lite" if facts["commands"]["uv"] else "direct_venv_lite"
        reason = "RapidOCR/ONNX is not available yet; create an isolated lightweight environment before heavier OCR engines."

    available_profiles = [default_profile]
    if paddleocr or paddle or conda:
        available_profiles.append("conda_paddle_cpu")
    if docker or wsl or (gpu and max_gpu_mem >= 4096):
        available_profiles.append("wsl_or_docker_heavy")

    install_actions = []
    if not rapidocr:
        install_actions.append("create direct_venv_lite or uv_venv_lite and install workers/document/requirements.txt")
    if not (paddleocr and paddle):
        install_actions.append("prepare conda_paddle_cpu only after golden-set need is confirmed")
    if docker or wsl:
        install_actions.append("generate launcher/profile with path mapping before WSL/Docker execution")

    return {
        "recommendedDefaultProfile": default_profile,
        "reason": reason,
        "availableProfileCandidates": sorted(set(available_profiles)),
        "needsHumanConfirmationBefore": [
            "system driver or GPU runtime changes",
            "Docker Desktop or WSL installation",
            "cloud OCR token configuration",
            "switching the production default profile",
            "processing real non-anonymized materials",
        ],
        "nextInstallActions": install_actions,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="docs/evidence/worker-profile-diagnostic-report.json")
    args = parser.parse_args()

    commands = {
        "python": command_exists("python"),
        "uv": command_exists("uv"),
        "conda": command_exists("conda"),
        "docker": command_exists("docker"),
        "wsl": command_exists("wsl"),
        "pdftotext": command_exists("pdftotext"),
        "pdftoppm": command_exists("pdftoppm"),
        "tesseract": command_exists("tesseract"),
    }

    facts: dict[str, Any] = {
        "schemaVersion": "worker-profile-diagnostic.v1",
        "mode": "read_only",
        "host": {
            "platform": platform.platform(),
            "machine": platform.machine(),
            "processor": platform.processor(),
            "pythonExecutable": sys.executable,
            "pythonVersion": platform.python_version(),
            "cpuCount": os.cpu_count(),
            "memoryGb": get_windows_memory_gb(),
        },
        "commands": commands,
        "pythonModules": {
            "rapidocr_onnxruntime": import_available("rapidocr_onnxruntime"),
            "onnxruntime": import_available("onnxruntime"),
            "paddleocr": import_available("paddleocr"),
            "paddle": import_available("paddle"),
            "cv2": import_available("cv2"),
            "PIL": import_available("PIL"),
        },
        "gpu": get_nvidia_gpu(),
    }
    facts["recommendation"] = recommend_profile(facts)
    facts["guardrail"] = {
        "noInstallPerformed": True,
        "noNetworkRequired": True,
        "productionDefaultChanged": False,
        "failClosedPolicy": "missing OCR engines must fall back to pending_review/takeoverRequired",
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(facts, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(facts, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
