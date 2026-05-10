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

import worker_profile_diagnostic


def command_path(name: str) -> str | None:
    found = shutil.which(name)
    return str(Path(found)) if found else None


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


def version_probe(args: list[str], timeout: int = 10) -> dict[str, Any]:
    result = run_command(args, timeout=timeout)
    text = result["stdout"] or result["stderr"]
    first_line = next((line.strip() for line in text.splitlines() if line.strip()), "")
    return {
        "available": result["available"],
        "exitCode": result["exitCode"],
        "versionLine": first_line,
    }


def get_windows_memory_gb() -> float | None:
    return worker_profile_diagnostic.get_windows_memory_gb()


def disk_for_path(path_value: str) -> dict[str, Any]:
    path = Path(path_value)
    anchor = path.anchor or str(path)
    if not anchor:
        return {"path": path_value, "available": False, "reason": "path has no anchor"}
    try:
        usage = shutil.disk_usage(anchor)
        return {
            "path": path_value,
            "anchor": anchor,
            "available": True,
            "totalGb": round(usage.total / (1024**3), 2),
            "freeGb": round(usage.free / (1024**3), 2),
        }
    except Exception as exc:
        return {"path": path_value, "anchor": anchor, "available": False, "reason": str(exc)}


def load_installer_config(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        import yaml  # type: ignore

        parsed = yaml.safe_load(path.read_text(encoding="utf-8"))
        return parsed if isinstance(parsed, dict) else {}
    except Exception:
        return {}


def collect_worker_recommendation() -> dict[str, Any]:
    worker_facts: dict[str, Any] = {
        "commands": {
            "uv": command_path("uv") is not None,
            "conda": command_path("conda") is not None,
            "docker": command_path("docker") is not None,
            "wsl": command_path("wsl") is not None,
        },
        "pythonModules": {
            "rapidocr_onnxruntime": worker_profile_diagnostic.import_available("rapidocr_onnxruntime"),
            "onnxruntime": worker_profile_diagnostic.import_available("onnxruntime"),
            "paddleocr": worker_profile_diagnostic.import_available("paddleocr"),
            "paddle": worker_profile_diagnostic.import_available("paddle"),
        },
        "gpu": worker_profile_diagnostic.get_nvidia_gpu(),
    }
    return {
        "summary": worker_facts,
        "recommendation": worker_profile_diagnostic.recommend_profile(worker_facts),
    }


def detect_commands() -> dict[str, dict[str, Any]]:
    probes = {
        "dotnet": ["dotnet", "--version"],
        "node": ["node", "--version"],
        "npm": ["cmd", "/c", "npm", "--version"],
        "pwsh": ["pwsh", "--version"],
        "powershell": ["powershell", "-NoProfile", "-Command", "$PSVersionTable.PSVersion.ToString()"],
        "python": ["python", "--version"],
        "uv": ["uv", "--version"],
        "conda": ["conda", "--version"],
        "docker": ["docker", "--version"],
        "wsl": ["wsl", "--version"],
        "psql": ["psql", "--version"],
        "pg_dump": ["pg_dump", "--version"],
        "pg_restore": ["pg_restore", "--version"],
        "pg_config": ["pg_config", "--version"],
        "pdftotext": ["pdftotext", "-v"],
        "pdftoppm": ["pdftoppm", "-v"],
        "tesseract": ["tesseract", "--version"],
        "qpdf": ["qpdf", "--version"],
        "gswin64c": ["gswin64c", "--version"],
        "magick": ["magick", "--version"],
        "vips": ["vips", "--version"],
        "pandoc": ["pandoc", "--version"],
        "soffice": ["soffice", "--version"],
        "robocopy": ["robocopy", "/?"],
        "nvidia-smi": ["nvidia-smi", "--query-gpu=name,memory.total,driver_version", "--format=csv,noheader"],
        "ollama": ["ollama", "--version"],
        "llama-server": ["llama-server", "--version"],
        "llama-cli": ["llama-cli", "--version"],
        "vllm": ["vllm", "--version"],
        "lms": ["lms", "--version"],
    }
    commands: dict[str, dict[str, Any]] = {}
    for name, args in probes.items():
        path = command_path(name)
        commands[name] = {
            "present": path is not None,
            "path": path,
            "probe": version_probe(args, timeout=20) if path else {"available": False, "exitCode": None, "versionLine": ""},
        }
    return commands


def env_presence() -> dict[str, bool]:
    keys = [
        "OPENAI_API_KEY",
        "AZURE_OPENAI_API_KEY",
        "ANTHROPIC_API_KEY",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "NO_PROXY",
        "PGPASSWORD",
        "KQG_DATA_ROOT",
        "KQG_BACKUP_ROOT",
    ]
    return {key: bool(os.environ.get(key)) for key in keys}


def max_gpu_memory_mb(gpu_summary: dict[str, Any]) -> int:
    gpus = gpu_summary.get("gpus") if isinstance(gpu_summary, dict) else None
    if not isinstance(gpus, list):
        return 0
    values = [
        int(gpu.get("memoryTotalMb") or gpu.get("memoryMb") or 0)
        for gpu in gpus
        if isinstance(gpu, dict)
    ]
    return max(values) if values else 0


def recommend_ai_local_model_profile(facts: dict[str, Any]) -> dict[str, Any]:
    commands = facts["commands"]
    memory_gb = facts["host"].get("memoryGb") or 0
    cpu_count = facts["host"].get("cpuCount") or 0
    gpu_summary = facts["workerOcrProfile"]["summary"].get("gpu") or {}
    gpu_vram_mb = max_gpu_memory_mb(gpu_summary)

    runtime_candidates = {
        "ollama": commands["ollama"]["present"],
        "llama_cpp_server": commands["llama-server"]["present"],
        "llama_cpp_cli": commands["llama-cli"]["present"],
        "vllm": commands["vllm"]["present"],
        "lm_studio_lms": commands["lms"]["present"],
    }

    if gpu_vram_mb >= 16384 and memory_gb >= 64:
        status = "high_config_optional"
        recommended = "optional_local_llm_7b_14b_quantized_eval_only"
        model_class = "7b_14b_quantized"
    elif gpu_vram_mb >= 8192 and memory_gb >= 32:
        status = "good_config_optional"
        recommended = "optional_local_llm_7b_quantized_eval_only"
        model_class = "7b_quantized"
    elif gpu_vram_mb >= 4096 and memory_gb >= 24:
        status = "medium_config_optional"
        recommended = "optional_local_llm_3b_7b_quantized_eval_only"
        model_class = "3b_7b_quantized"
    elif memory_gb >= 16 and cpu_count >= 8:
        status = "cpu_only_optional_lite"
        recommended = "optional_local_llm_1_5b_3b_quantized_cpu_eval_only"
        model_class = "1_5b_3b_quantized_cpu"
    else:
        status = "not_recommended_for_local_llm"
        recommended = "keep_rules_first_and_cloud_or_manual_review_only"
        model_class = "none"

    return {
        "status": status,
        "recommended": recommended,
        "modelClass": model_class,
        "runtimeCandidates": runtime_candidates,
        "detectedGpuVramMb": gpu_vram_mb,
        "hostCapacity": {"cpuCount": cpu_count, "memoryGb": memory_gb},
        "allowedDraftTasks": [
            "OCR text cleanup candidates",
            "question wording normalization candidates",
            "knowledge tag candidates",
            "difficulty candidates",
            "commentary draft candidates",
        ],
        "blockedProductionTasks": [
            "OCR or formula recognition engine replacement",
            "direct active writes",
            "formal analytics",
            "authoritative tagging",
            "backup, restore, migration, or permission decisions",
        ],
        "requiresEvalBeforeDefault": True,
        "noModelDownloadPerformed": True,
        "noActiveWrite": True,
        "noCloudTokenRequired": True,
        "fallback": "rules_first_structured_outputs_or_teacher_pending_review",
    }


def recommend_profiles(facts: dict[str, Any]) -> dict[str, Any]:
    commands = facts["commands"]
    env = facts["envPresence"]
    storage = facts["storage"]
    worker = facts["workerOcrProfile"]["recommendation"]
    memory_gb = facts["host"].get("memoryGb") or 0
    cpu_count = facts["host"].get("cpuCount") or 0

    data_free = storage["dataRoot"].get("freeGb") if storage["dataRoot"].get("available") else None
    backup_free = storage["backupRoot"].get("freeGb") if storage["backupRoot"].get("available") else None

    runtime_status = "ready" if commands["dotnet"]["present"] and commands["node"]["present"] and commands["npm"]["present"] else "needs_install"
    database_status = "ready" if commands["psql"]["present"] and commands["pg_dump"]["present"] and commands["pg_restore"]["present"] else "needs_postgresql_cli_or_path"
    storage_status = "ready" if (data_free or 0) >= 10 and (backup_free or 0) >= 10 else "needs_capacity_review"
    export_status = "ready" if commands["pandoc"]["present"] and commands["qpdf"]["present"] else "partial_toolchain"
    ai_status = "offline_first" if not env["OPENAI_API_KEY"] and not env["AZURE_OPENAI_API_KEY"] else "token_present_requires_policy_gate"
    queue_status = "backgroundservice_ok" if cpu_count >= 4 and memory_gb >= 8 else "limit_concurrency"

    return {
        "runtimeProfile": {
            "status": runtime_status,
            "recommended": "windows_service_with_explicit_content_root",
            "fallback": "self_contained_publish_when_target_runtime_missing",
            "checks": ["dotnet", "node", "npm", "pwsh"],
        },
        "databaseProfile": {
            "status": database_status,
            "recommended": "local_postgresql_with_pg_dump_restore",
            "fallback": "install_postgresql_cli_or_configure_path_before_live",
            "checks": ["psql", "pg_dump", "pg_restore"],
        },
        "storageBackupProfile": {
            "status": storage_status,
            "recommended": "local_ntfs_file_store_plus_manifest_backup",
            "fallback": "choose_larger_data_or_backup_drive_before_real_materials",
            "minimumFreeGb": 10,
        },
        "workerOcrProfile": {
            "status": "ready" if worker["recommendedDefaultProfile"] else "needs_profile",
            "recommended": worker["recommendedDefaultProfile"],
            "candidates": worker["availableProfileCandidates"],
            "fallback": "pending_review_takeover_required",
        },
        "exportPrintProfile": {
            "status": export_status,
            "recommended": "docx_pdf_artifact_chain_with_preflight_manifest",
            "fallback": "keep_docx_or_html_export_until_pdf_toolchain_admitted",
            "checks": ["pandoc", "qpdf", "gswin64c", "magick", "soffice"],
        },
        "aiNetworkProfile": {
            "status": ai_status,
            "recommended": "offline_first_no_cloud_token_by_default",
            "fallback": "cloud_provider_only_after_privacy_cost_cache_gate",
            "secretValuesPrinted": False,
        },
        "aiLocalModelProfile": recommend_ai_local_model_profile(facts),
        "searchProfile": {
            "status": "postgresql_first",
            "recommended": "postgresql_fts_pg_trgm_first_pgvector_only_after_eval",
            "fallback": "semantic_search_gate_na_until_extension_and_benchmark",
        },
        "queueProfile": {
            "status": queue_status,
            "recommended": "postgresql_job_store_backgroundservice_first",
            "fallback": "defer_hangfire_rabbitmq_until_throughput_evidence",
            "hostCapacity": {"cpuCount": cpu_count, "memoryGb": memory_gb},
        },
        "securityProfile": {
            "status": "requires_live_gate",
            "recommended": "admin_key_bootstrap_then_rbac_audit_before_live",
            "fallback": "draft_test_only_until_o004b_and_permission_audit",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="configs/installer_init.defaults.yaml")
    parser.add_argument("--output", default="docs/evidence/host-capability-diagnostic-report.json")
    args = parser.parse_args()

    config_path = Path(args.config)
    cfg = load_installer_config(config_path)
    paths = cfg.get("paths", {}) if isinstance(cfg.get("paths"), dict) else {}
    data_root = str(paths.get("data_root") or os.environ.get("KQG_DATA_ROOT") or "D:\\KQG_Data")
    backup_root = str(paths.get("backup_root") or os.environ.get("KQG_BACKUP_ROOT") or "D:\\KQG_Backups")

    facts: dict[str, Any] = {
        "schemaVersion": "host-capability-diagnostic.v1",
        "mode": "read_only",
        "host": {
            "platform": platform.platform(),
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
            "processor": platform.processor(),
            "pythonExecutable": sys.executable,
            "pythonVersion": platform.python_version(),
            "cpuCount": os.cpu_count(),
            "memoryGb": get_windows_memory_gb(),
        },
        "config": {
            "path": str(config_path),
            "version": cfg.get("version"),
            "dataRoot": data_root,
            "backupRoot": backup_root,
        },
        "commands": detect_commands(),
        "envPresence": env_presence(),
        "storage": {
            "dataRoot": disk_for_path(data_root),
            "backupRoot": disk_for_path(backup_root),
        },
        "workerOcrProfile": collect_worker_recommendation(),
    }
    facts["recommendedProfiles"] = recommend_profiles(facts)
    facts["bestConfiguration"] = {
        "profileSet": "local_system_profile.v1",
        "adaptiveOnNewHost": True,
        "allowInstallerToWriteDraftConfig": True,
        "productionChangesRequire": [
            "full gate",
            "roadmap guard",
            "backup/restore evidence",
            "golden OCR/import evidence where document processing changes",
            "local model eval and no-active-write evidence when aiLocalModelProfile changes",
            "human confirmation for admin/system/cloud/real-data changes",
        ],
        "lowRiskAgentActions": [
            "generate draft appsettings/local profile files",
            "create project-owned data/cache directories through installer dry-run",
            "select draft worker profile from diagnostic output",
            "record local model runtime candidates and recommended draft-only model class",
            "record tool versions and missing dependencies in evidence",
        ],
        "humanConfirmationBefore": [
            "installing system services or drivers",
            "changing firewall, antivirus, GPU runtime, Docker Desktop, or WSL installation",
            "configuring cloud tokens or paid providers",
            "downloading local model weights or enabling local model as default route",
            "processing real non-anonymized teacher/student materials",
            "switching production active profile or release readiness status",
        ],
    }
    facts["guardrail"] = {
        "noInstallPerformed": True,
        "noNetworkRequired": True,
        "secretsPrinted": False,
        "productionDefaultChanged": False,
        "modelWeightsDownloaded": False,
        "localAiDefaultChanged": False,
        "failClosedPolicy": "missing runtime, database, worker, export, security, or storage capabilities must block live release or fall back to pending_review/takeoverRequired",
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(facts, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(facts, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
