# 50 · C002 Source Material Admission

## 1. 目的

正式 C002 不能由预置知识点清单直接完成。C002 的正式输入必须来自教师录入或导入的真实来源资料，包括各版本教材、学科课程标准、近年当地中考/高考真题、校本试卷或教师原创资料。

当前 `configs/knowledge/junior-physics-l1-l3.json` 只是 draft bootstrap，可用于 API/UI/回归测试，不作为正式校本知识本体。

## 2. 来源资料准入

正式提炼前，每份资料必须记录：

- `sourceType`: `textbook`、`curriculum_standard`、`local_exam_paper`、`school_paper`、`teacher_original` 或 `region_exam_point`。
- `title`、`publisherOrAuthority`、`editionOrVersion`、`year`、`gradeOrScope`。
- `localPath`: 指向 `D:\KQG_Data\source_materials\` 或等价数据目录，不能指向仓库内文件。
- `sha256`: 原文件 hash。
- `licenseOrPermission`: 授权、公开来源、校内许可或未知状态。
- `containsStudentPii` 与 `anonymizationStatus`。
- `mayUseForKnowledgeExtraction`: 是否允许用于知识点提炼。

真实教材、真题、校本试卷原件不得提交到 Git。真实本地 manifest 使用：

```text
configs/knowledge/source-material-manifest.local.json
```

该文件已被 `.gitignore` 排除。

## 3. 最低资料集

正式 C002 至少需要：

- 一个教材版本或教材目录资料。
- 一个学科课程标准资料。
- 一个近年当地中考/高考真题或区域考试资料。

若缺任一类，C002 只能保持 `暂缓`，draft bootstrap 仍只能用于测试。

## 4. 提炼与审核

建议流程：

```text
录入来源资料 manifest
-> 校验授权、PII、hash、路径
-> 从教材/课标/真题提取候选 L1-L3 节点
-> 与 draft bootstrap 对齐、合并、删除或重命名
-> 教师/备课组审核关键节点
-> 生成 source-derived version
-> 将审核通过节点标记为 active
-> 保留草稿与历史映射追溯
```

正式版本不得覆盖草稿历史。用 `version/status/metadata` 表达来源证据和状态迁移。

## 5. 验证

模板/准入 guard：

```powershell
.\tools\run-c002-source-material-guard.ps1
```

Full gate 已包含该 guard。

正式 C002 完成时，还需要新增 source-derived seed validation，验证：

- 所有 active 节点均有来源资料证据。
- L1/L2/L3 结构来自已准入资料。
- 教材/课标/地区考点只作为映射层。
- 草稿映射仍可追溯。
- 未授权或含未脱敏 PII 的资料不会进入提炼流程。
