"""golden 输出回归 runner:规范化 worker document model 并与 golden 文件比对。

原则(对应 2026-08-25 独立评审意见):
- 只对"稳定语义"做回归:adapter 选择、页/块结构、块类型、公式/表格/图片保留标志、
  人工接管状态、规范化输出的稳定 hash;
- 不 hash 运行时噪声:耗时、toolVersion、inputSha256/sizeBytes、adapterDiagnostics、
  临时路径或 OCR 浮动文字;
- 外部二进制(pdftotext/pdftoppm)与 OCR 引擎在运行时强制 mock 为不可用,
  保证同一 golden 在任何环境可比;真实 OCR 链路的验收属于 P001 目标机实测。

用法:
    python tests/golden-import/golden_runner.py            # 校验模式,漂移退出码 1
    python tests/golden-import/golden_runner.py --regenerate  # 显式重建 golden
"""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKER_ROOT = REPO_ROOT / "workers" / "document"
GOLDEN_ROOT = pathlib.Path(__file__).resolve().parent / "golden"
if str(WORKER_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKER_ROOT))

import synthetic_documents  # noqa: E402
import worker  # noqa: E402

FORCED_OCR_UNAVAILABLE = "rapidocr_onnxruntime unavailable: golden-test-forced"


def normalize_document_output(document_model: dict) -> dict:
    model = copy.deepcopy(document_model)
    adapter = model.pop("_adapter", {})
    source = model.get("source") or {}
    normalized_source = {"relativePath": source.get("relativePath")}
    return {
        "adapterName": adapter.get("name"),
        "adapterVersion": adapter.get("version"),
        "warnings": adapter.get("warnings", []),
        "documentModel": {
            "schemaVersion": model.get("schemaVersion"),
            "source": normalized_source,
            "pages": model.get("pages", []),
        },
    }


def run_case(case_name: str) -> dict:
    builder, relative_path = synthetic_documents.CASE_BUILDERS[case_name]
    with tempfile.TemporaryDirectory(prefix="kqg-golden-") as directory:
        target = pathlib.Path(directory) / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        builder(target)
        with mock.patch.object(worker.shutil, "which", return_value=None), \
                mock.patch.object(
                    worker,
                    "load_rapidocr_engine",
                    return_value=(None, FORCED_OCR_UNAVAILABLE)):
            document_model = worker.build_document_model(case_name, relative_path, target)
    return normalize_document_output(document_model)


def _canonical_json(value: dict) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2)


def normalized_sha256(normalized: dict) -> str:
    return hashlib.sha256(_canonical_json(normalized).encode("utf-8")).hexdigest()


def golden_path(case_name: str) -> pathlib.Path:
    return GOLDEN_ROOT / f"{case_name}.json"


def save_golden(case_name: str) -> None:
    normalized = run_case(case_name)
    GOLDEN_ROOT.mkdir(parents=True, exist_ok=True)
    payload = {
        "case": case_name,
        "normalizedSha256": normalized_sha256(normalized),
        "normalized": normalized,
    }
    golden_path(case_name).write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def assert_matches_golden(test_case: unittest.TestCase, case_name: str) -> dict:
    golden_file = golden_path(case_name)
    test_case.assertTrue(golden_file.is_file(), f"golden file missing: {golden_file}")
    golden = json.loads(golden_file.read_text(encoding="utf-8"))
    normalized = run_case(case_name)
    test_case.assertEqual(
        golden["normalized"],
        normalized,
        f"golden drift for {case_name};有意变更时用 `python tests/golden-import/golden_runner.py --regenerate` 重建并复核 diff",
    )
    test_case.assertEqual(golden["normalizedSha256"], normalized_sha256(normalized))
    return normalized


def main() -> int:
    if "--regenerate" in sys.argv:
        for case_name in synthetic_documents.ALL_CASES:
            save_golden(case_name)
            print(f"regenerated {golden_path(case_name).name}")
        return 0

    drift = []
    for case_name in synthetic_documents.ALL_CASES:
        golden_file = golden_path(case_name)
        if not golden_file.is_file():
            drift.append(f"{case_name}: golden file missing")
            continue
        golden = json.loads(golden_file.read_text(encoding="utf-8"))
        if golden["normalized"] != run_case(case_name):
            drift.append(case_name)
    if drift:
        print("golden drift: " + ", ".join(drift))
        return 1
    print(f"golden ok: {len(synthetic_documents.ALL_CASES)} cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
