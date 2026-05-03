# 学科知识体系激活前确认表

## 1. 批次信息

| 项目 | 填写 |
| --- | --- |
| 学科 |  |
| 年级/学段 |  |
| 来源批次 `MaterialBatchKey` |  |
| 候选导入批次 `ImportKey` |  |
| 激活证据前缀 `EvidencePrefix` |  |
| 确认人 |  |
| 确认日期 |  |

## 2. 机器摘要确认

把 `run-domain-asset-activation.ps1` 的 dry-run 摘要填入：

| 检查项 | 必须满足 | 实际 | 是否通过 |
| --- | --- | --- | --- |
| `sourceDocuments` | 大于 0 |  |  |
| `sourceDocumentsWithSha256` | 等于 `sourceDocuments` |  |  |
| `candidateAssets` | 0 |  |  |
| `reviewedAssets` | 大于 0，或已 active |  |  |
| `pendingMappings` | 0 |  |  |
| `pendingMigrations` | 0 |  |  |
| `openReviewItems` | 0 |  |  |
| `rollbackSnapshots` | 大于等于 1 |  |  |
| active dry-run blockers | 空 |  |  |

任一项不满足，不允许激活。

## 3. 人工复核确认

| 检查项 | 是否完成 |
| --- | --- |
| 已按复核清单完成抽样复核 |  |
| 低置信度项已处理 |  |
| 高影响项已处理 |  |
| 一对多、多对一、多对多映射已逐项确认 |  |
| 影响历史学情或正式组卷的项已由管理员确认 |  |
| 仍保留的风险已写入备注 |  |

## 4. 备份确认

| 项目 | 填写 |
| --- | --- |
| backup manifest 路径 |  |
| `verify-backup.ps1` 结果 |  |
| 回滚负责人 |  |
| 回滚窗口 |  |

未生成并校验 backup manifest，不允许执行 `-ApplyActivation`。

## 5. 激活决定

选择一个：

| 决定 | 勾选 |
| --- | --- |
| 同意激活为当前生产默认版本 |  |
| 暂缓激活，要求补充资料 |  |
| 暂缓激活，要求修改候选资产 |  |
| 暂缓激活，要求修改映射/影响报告 |  |

备注：

```text

```

确认签名：

```text
确认人：
日期：
```
