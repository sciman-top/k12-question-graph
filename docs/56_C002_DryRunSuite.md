# 56 · C002 Dynamic Assets Dry-Run Suite

## 1. 目的

本文件记录 C002 动态资产 dry-run suite。它用于在没有 PostgreSQL 密码时快速验证 C002B-C002E 的非生产合同，避免每次都只能依赖完整数据库 gate。

## 2. 命令

```powershell
.\tools\run-c002-dry-run-suite.ps1
```

## 3. 覆盖范围

- C002 source material admission guard。
- C002B replacement mapping contract。
- C002C migration impact contract。
- C002D source-derived admission contract。
- C002E activation guard contract。
- C002H mapping review workbench contract。

## 4. 边界

该 suite 不连接数据库、不写生产数据、不替代 `tools/run-gates.ps1` 中的数据库 contract。它只能证明动态资产 dry-run 链路自洽，不能证明 EF migration 已应用到本机 PostgreSQL。

## 5. 回滚

```powershell
git restore --source=HEAD -- tools/README.md docs/20_TaskBreakdown.md tasks/backlog.csv
git clean -f -- tools/run-c002-dry-run-suite.ps1 docs/56_C002_DryRunSuite.md
```
