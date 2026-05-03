from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


EXTRACTOR_VERSION = "c002n-source-chunk-cache.v1"
DEFAULT_SOURCE_REPORT = Path("docs/evidence/c002-source-material-import-report.json")
DEFAULT_CACHE_ROOT = Path("tmp/c002n-source-chunk-cache")
DEFAULT_OUTPUT = Path("docs/evidence/c002n-source-chunk-cache-report.json")
SOURCE_HASH_CHUNK_SIZE = 1024 * 1024


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(SOURCE_HASH_CHUNK_SIZE), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def require_tool(name: str) -> str:
    resolved = shutil.which(name)
    if not resolved:
        raise RuntimeError(f"missing required PDF tool: {name}")
    return resolved


def run_text_command(args: list[str]) -> str:
    completed = subprocess.run(args, check=True, capture_output=True)
    return completed.stdout.decode("utf-8", errors="replace")


def parse_page_count(pdfinfo_output: str) -> int:
    match = re.search(r"^Pages:\s+(\d+)\s*$", pdfinfo_output, flags=re.MULTILINE)
    if not match:
        raise RuntimeError("pdfinfo output does not include Pages")
    return int(match.group(1))


def normalize_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = [re.sub(r"[ \t]+", " ", line).strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)


def split_pages(raw_text: str, page_count: int) -> list[str]:
    pages = raw_text.replace("\r\n", "\n").replace("\r", "\n").split("\f")
    if pages and pages[-1].strip() == "":
        pages = pages[:-1]
    if len(pages) < page_count:
        pages.extend([""] * (page_count - len(pages)))
    return pages[:page_count]


def block_type_for(text: str) -> str:
    if not text.strip():
        return "empty_page"
    if re.search(r"(第\s*\d+\s*题|^\d+[\.、]|选择题|填空题|实验题|计算题|问答题)", text, flags=re.MULTILINE):
        return "question_or_exam_block"
    if re.search(r"(课程标准|学业要求|内容要求|核心素养|教学提示|教材|章节)", text):
        return "curriculum_or_textbook_block"
    if re.search(r"(得分率|区分度|难度|考点|年报|质量分析|命题)", text):
        return "exam_analysis_block"
    return "text_block"


def chunks_for_page(source_hash: str, relative_path: str, page_number: int, page_text: str) -> list[dict[str, Any]]:
    normalized = normalize_text(page_text)
    if not normalized:
        chunk_id = f"{source_hash[:12]}-p{page_number:04d}-c000"
        return [
            {
                "chunkId": chunk_id,
                "pageNumber": page_number,
                "chunkIndex": 0,
                "chunkHash": sha256_text(f"{source_hash}:{relative_path}:{page_number}:empty"),
                "blockType": "empty_page",
                "charCount": 0,
                "estimatedTokens": 0,
            }
        ]

    paragraphs = re.split(r"\n{2,}", normalized)
    merged: list[str] = []
    current = ""
    for paragraph in paragraphs:
        if not paragraph:
            continue
        if len(current) + len(paragraph) + 1 <= 1800:
            current = f"{current}\n{paragraph}".strip()
        else:
            if current:
                merged.append(current)
            current = paragraph
    if current:
        merged.append(current)

    chunks: list[dict[str, Any]] = []
    for index, chunk_text in enumerate(merged):
        chunk_hash = sha256_text(f"{source_hash}:{relative_path}:{page_number}:{index}:{chunk_text}")
        chunks.append(
            {
                "chunkId": f"{source_hash[:12]}-p{page_number:04d}-c{index:03d}",
                "pageNumber": page_number,
                "chunkIndex": index,
                "chunkHash": chunk_hash,
                "blockType": block_type_for(chunk_text),
                "charCount": len(chunk_text),
                "estimatedTokens": max(1, len(chunk_text) // 2),
            }
        )
    return chunks


def cache_path_for(cache_root: Path, source_hash: str) -> Path:
    return cache_root / source_hash[:2] / source_hash / "chunk-index.json"


def extract_source(material: dict[str, Any], cache_root: Path, pdftotext: str, pdfinfo: str, source_root: Path | None) -> dict[str, Any]:
    source_path = source_root / material["relativePath"] if source_root else Path(material["path"])
    if not source_path.is_file():
        raise RuntimeError(f"missing source PDF: {source_path}")

    source_hash = sha256_file(source_path)
    cache_path = cache_path_for(cache_root, source_hash)
    if cache_path.is_file():
        cached = read_json(cache_path)
        if cached.get("extractorVersion") == EXTRACTOR_VERSION and cached.get("sourceHash") == source_hash:
            cached["cacheHit"] = True
            return cached

    pdfinfo_output = run_text_command([pdfinfo, str(source_path)])
    page_count = parse_page_count(pdfinfo_output)
    raw_text_path = cache_path.with_suffix(".txt")
    raw_text_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([pdftotext, "-layout", "-enc", "UTF-8", str(source_path), str(raw_text_path)], check=True)
    raw_text = raw_text_path.read_text(encoding="utf-8", errors="replace")
    pages = split_pages(raw_text, page_count)

    page_summaries: list[dict[str, Any]] = []
    total_chunks = 0
    total_chars = 0
    total_estimated_tokens = 0
    block_types: dict[str, int] = {}
    for page_number, page_text in enumerate(pages, start=1):
        chunks = chunks_for_page(source_hash, material["relativePath"], page_number, page_text)
        for chunk in chunks:
            total_chunks += 1
            total_chars += int(chunk["charCount"])
            total_estimated_tokens += int(chunk["estimatedTokens"])
            block_types[chunk["blockType"]] = block_types.get(chunk["blockType"], 0) + 1
        page_summaries.append(
            {
                "pageNumber": page_number,
                "pageHash": sha256_text(normalize_text(page_text)),
                "chunkCount": len(chunks),
                "nonEmpty": any(chunk["charCount"] > 0 for chunk in chunks),
                "chunks": chunks,
            }
        )

    payload = {
        "extractorVersion": EXTRACTOR_VERSION,
        "sourceHash": source_hash,
        "sourceType": material["sourceType"],
        "sourceTitle": material["sourceTitle"],
        "relativePath": material["relativePath"],
        "materialBatchKey": material["materialBatchKey"],
        "pageCount": page_count,
        "chunkCount": total_chunks,
        "nonEmptyPageCount": sum(1 for page in page_summaries if page["nonEmpty"]),
        "estimatedTokens": total_estimated_tokens,
        "charCount": total_chars,
        "blockTypes": dict(sorted(block_types.items())),
        "cacheHit": False,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "pages": page_summaries,
    }
    write_json(cache_path, payload)
    return payload


def summarize_source(source: dict[str, Any]) -> dict[str, Any]:
    sample_chunks: list[dict[str, Any]] = []
    for page in source["pages"]:
        for chunk in page["chunks"]:
            if chunk["charCount"] > 0:
                sample_chunks.append(
                    {
                        "pageNumber": chunk["pageNumber"],
                        "chunkHash": chunk["chunkHash"],
                        "blockType": chunk["blockType"],
                        "charCount": chunk["charCount"],
                        "estimatedTokens": chunk["estimatedTokens"],
                    }
                )
                if len(sample_chunks) >= 3:
                    break
        if len(sample_chunks) >= 3:
            break

    return {
        "relativePath": source["relativePath"],
        "sourceType": source["sourceType"],
        "sourceTitle": source["sourceTitle"],
        "sourceHash": source["sourceHash"],
        "pageCount": source["pageCount"],
        "nonEmptyPageCount": source["nonEmptyPageCount"],
        "chunkCount": source["chunkCount"],
        "estimatedTokens": source["estimatedTokens"],
        "blockTypes": source["blockTypes"],
        "cacheHit": source["cacheHit"],
        "sampleChunks": sample_chunks,
    }


def build_report(source_report: Path, cache_root: Path, output: Path, require_count: int, source_root: Path | None) -> dict[str, Any]:
    source_payload = read_json(source_report)
    materials = source_payload.get("plan", [])
    if len(materials) < require_count:
        raise RuntimeError(f"expected at least {require_count} source materials, found {len(materials)}")

    pdftotext = require_tool("pdftotext")
    pdfinfo = require_tool("pdfinfo")
    sources: list[dict[str, Any]] = []
    for material in materials:
        sources.append(extract_source(material, cache_root, pdftotext, pdfinfo, source_root))

    source_hashes = {source["sourceHash"] for source in sources}
    chunk_hashes = {
        chunk["chunkHash"]
        for source in sources
        for page in source["pages"]
        for chunk in page["chunks"]
    }
    cache_hits = sum(1 for source in sources if source.get("cacheHit"))
    failed_sources = [
        {
            "relativePath": source["relativePath"],
            "reason": "未抽取到任何非空页面",
        }
        for source in sources
        if source["nonEmptyPageCount"] == 0
    ]
    source_types: dict[str, int] = {}
    for source in sources:
        source_types[source["sourceType"]] = source_types.get(source["sourceType"], 0) + 1

    report = {
        "status": "pass" if not failed_sources else "fail",
        "task": "C002N",
        "extractorVersion": EXTRACTOR_VERSION,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "sourceReport": str(source_report),
        "sourceRootOverride": str(source_root) if source_root else "",
        "cacheRoot": str(cache_root),
        "externalAiCalls": 0,
        "sourceCount": len(sources),
        "sourceHashCoverage": {
            "expectedSourceCount": require_count,
            "coveredSourceCount": len(source_hashes),
            "coveragePass": len(source_hashes) >= require_count,
        },
        "cacheIdempotency": {
            "cacheHitSourceCount": cache_hits,
            "cacheMissSourceCount": len(sources) - cache_hits,
            "cacheHitRatio": round(cache_hits / len(sources), 4) if sources else 0,
        },
        "totals": {
            "pageCount": sum(source["pageCount"] for source in sources),
            "nonEmptyPageCount": sum(source["nonEmptyPageCount"] for source in sources),
            "chunkCount": sum(source["chunkCount"] for source in sources),
            "uniqueChunkHashCount": len(chunk_hashes),
            "estimatedInputTokens": sum(source["estimatedTokens"] for source in sources),
        },
        "bySourceType": dict(sorted(source_types.items())),
        "failedSources": failed_sources,
        "summaryChinese": {
            "title": "C002N 来源 chunk 缓存报告",
            "result": "通过" if not failed_sources else "失败",
            "scope": f"已覆盖 {len(sources)} 份来源 PDF，全部仅本地抽取，不调用外部 AI。",
            "cache": f"本轮缓存命中 {cache_hits} 份，未命中 {len(sources) - cache_hits} 份。",
            "next": "正式 C002 v1 已由 C002T 受控激活；后续修订继续走 candidate/review/rollback/active guard。",
        },
        "sources": [summarize_source(source) for source in sources],
    }
    if report["status"] != "pass":
        write_json(output, report)
        raise RuntimeError("C002N source chunk extraction produced failed sources")
    write_json(output, report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Build C002N local source chunk cache.")
    parser.add_argument("--source-report", type=Path, default=DEFAULT_SOURCE_REPORT)
    parser.add_argument("--cache-root", type=Path, default=DEFAULT_CACHE_ROOT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--require-count", type=int, default=33)
    parser.add_argument("--source-root", type=Path, default=None)
    args = parser.parse_args()

    report = build_report(args.source_report, args.cache_root, args.output, args.require_count, args.source_root)
    print(json.dumps({
        "status": report["status"],
        "task": report["task"],
        "sourceCount": report["sourceCount"],
        "cacheHitSourceCount": report["cacheIdempotency"]["cacheHitSourceCount"],
        "chunkCount": report["totals"]["chunkCount"],
        "estimatedInputTokens": report["totals"]["estimatedInputTokens"],
        "output": str(args.output),
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"C002N source chunk cache failed: {exc}", file=sys.stderr)
        raise
