# 46 · B007 Golden Import Regression 证据

执行日期：2026-05-03。

## 1. 完成范围

- 新增合成黄金样本配置：
  - `tests/golden-import/samples.json`
  - `tests/golden-import/privacy_and_license.md`
- 新增一键回归脚本：
  - `tools/run-import-golden.ps1`
- 黄金样本覆盖：
  - 共用题图。
  - 跨页题。
  - 公式密集。
  - 扫描版。
  - 答案解析分离。
- 每个样本执行：
  - 上传文件。
  - 创建 SourceDocument。
  - 创建 SourceRegion。
  - 保存 QuestionItem / QuestionBlock / QuestionAsset。
  - 回看题目来源。
- 样本均为 synthetic，不包含真实学生数据或真实试卷原件。

## 2. 独立脚本结果

命令：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-import-golden.ps1
```

关键输出：

```json
{
  "status": "pass",
  "sampleCount": 5
}
```

## 3. Gate 结果

命令：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-gates.ps1
```

关键输出应包含：

```text
b007 golden import regression: pass
```

已知非阻断警告：

```text
Vite chunk-size warning due Ant Design bundle.
```

## 4. 回滚

代码/文档回滚：

```powershell
git restore --source=HEAD -- tools/run-import-golden.ps1 tools/run-gates.ps1 tools/README.md tests/golden-import tasks/backlog.csv docs/46_B007_GoldenImportRegression.md
```

B007 不新增数据库 migration；脚本会在本机数据库追加 synthetic 回归记录。
