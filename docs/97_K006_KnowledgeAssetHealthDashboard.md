# 97 · K006 知识资产健康面板

## 目标

K006 为管理员提供一个只读知识资产健康面板，集中查看当前 active 知识版本、candidate 数量、待审映射、迁移、阻断项和关键证据摘要。

普通教师不需要处理 active switch、migration、rollback snapshot 或证据文件路径；这些仍留在管理员和脚本层。

## 验证入口

```powershell
.\tools\run-k006-knowledge-asset-health-dashboard-contract.ps1
```

证据报告：

```text
docs/evidence/k006-knowledge-asset-health-dashboard-report.json
```

## 覆盖范围

- `active`: 当前生产默认知识版本和 active asset 数。
- `candidate`: 待激活候选资产数量。
- `pending mappings`: 待审映射数量。
- `migrations`: 待执行迁移数量。
- `blockers`: 激活或修订阻断项。
- `evidence summary`: active switch、K001 生产查询和 K005 第二批修订 dry-run 证据摘要。

## 边界

K006 是 UI contract，不执行数据库写入、不修改 active 知识资产、不执行 migration apply、不改写生产历史。面板只提供证据、待审映射、迁移历史和阻断项的只读入口。

## 回滚

回滚优先使用 Git revert K006 变更。K006 没有数据库、active pointer 或 migration side effect。
