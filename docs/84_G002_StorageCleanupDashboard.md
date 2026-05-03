# G002 · 缓存清理与存储看板

G002 在 draft/test 模式下建立管理员运维入口：管理员能看到数据目录、文件仓库、备份、日志和缓存占用，并且只能对配置化缓存目录执行预览和清理。

## 合同入口

- API: `GET /api/admin/storage/summary`
- API: `POST /api/admin/cache/cleanup`
- Web: `data-flow="admin-storage-dashboard"`
- Gate: `tools/run-g002-storage-cleanup-contract.ps1`
- Evidence: `docs/evidence/g002-storage-cleanup-report.json`

## 安全边界

- 清理根目录来自 `KqgPaths:CacheRoot`，不接受任意前端路径。
- 默认先 `dryRun=true` 预览候选文件。
- 文件仓库、备份包、学生成绩和正式资产不属于缓存清理范围。
- 证据报告记录 preview、cleanup、候选文件、删除数量和回滚方式。

## 回滚

代码回滚使用 `git revert` 对应 G002 提交。合同脚本生成的 synthetic 数据只位于 `tmp/g002-storage`，可删除该目录；不得把该清理方式泛化到真实数据目录。
