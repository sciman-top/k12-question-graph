# 40 · B002 Document Adapter Contract 证据

执行日期：2026-05-03。

## 1. 完成范围

- 扩展 `workers/document/worker.py`，保持 Python placeholder，不接真实 Docling/OpenXML/PaddleOCR。
- Worker 成功输出稳定内部 JSON：
  - `DocumentModel`
  - `PageModel`
  - `LayoutBlock`
  - `AdapterDiagnostic`
- `AdapterDiagnostic` 记录：
  - adapter name/version
  - tool name/version
  - command args
  - durationMs
  - inputSha256
  - outputSha256
  - warnings/errors
- `tools/run-gates.ps1` 新增 `b002 adapter contract smoke`。

## 2. Contract 示例

```json
{
  "status": "ok",
  "documentModel": {
    "schemaVersion": "document-model.v0.1",
    "pages": [
      {
        "pageNumber": 1,
        "layoutBlocks": [
          {
            "id": "block_0001",
            "blockType": "raw_document"
          }
        ]
      }
    ]
  },
  "adapterDiagnostics": [
    {
      "adapterName": "placeholder_document_adapter",
      "adapterVersion": "0.1",
      "toolName": "python",
      "inputSha256": "<sha256>",
      "outputSha256": "<sha256>",
      "warnings": [
        "placeholder adapter: no Docling/OpenXML/PaddleOCR parsing executed"
      ],
      "errors": []
    }
  ]
}
```

## 3. Gate 结果

命令：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-gates.ps1
```

关键输出：

```text
backend build: pass
frontend build: pass
frontend lint: pass
worker smoke: pass
b002 adapter contract smoke: pass
doc schema config csv: pass
database smoke: pass
b001 duplicate upload smoke: pass
backup verify: pass
overall: pass
```

已知非阻断警告：

```text
Vite chunk-size warning due Ant Design bundle.
```

## 4. 回滚

代码/文档回滚：

```powershell
git restore --source=HEAD -- workers/document tools tasks docs/40_B002_DocumentAdapterContract.md
```

B002 不新增数据库 migration；数据库回滚沿 B001 文档执行即可。
