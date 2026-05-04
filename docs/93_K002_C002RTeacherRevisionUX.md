# 93 · K002 C002R 教师修订 UX

K002 把 C002R 的版本化修订合同放到教师能理解的入口里。教师发现知识点、章节、考点或趋势口径不准确时，不填写技术字段，只提交：

1. 修订原因。
2. 来源证据。
3. 影响范围。
4. 紧急程度。

系统侧继续承接 C002R 合同：基于当前 active C002 v1 生成 `candidate` 版本、映射建议、影响报告和回滚快照。普通教师不能直接切换 active，也不能直接执行 migration、importKey 或 rollback snapshot 相关操作。

## 验证入口

```powershell
.\tools\run-k002-c002r-teacher-revision-ux-contract.ps1
```

该合同会先运行 `tools/run-c002r-versioned-revision-contract.ps1`，再检查 Web UI：

- `data-flow="c002r-teacher-revision-ux"` 存在。
- 教师可见字段只有修订原因、来源证据、影响范围和紧急程度。
- 系统生成项包含 candidate 版本、映射建议、影响报告和回滚快照。
- UI 明确 candidate 保持 `pending_review`，不直接修改当前正式知识体系。
- 教师侧不存在 active 切换、migration 执行或直接编辑 active 的高风险 action。

报告写入 `docs/evidence/k002-c002r-teacher-revision-ux-report.json`，并纳入 `tools/run-gates.ps1`。

## 边界

- 不写数据库。
- 不修改 active C002 v1。
- 不使用真实学生数据。
- 不调用外部 AI。
- 不执行管理员 active switch。

## 回滚

代码回滚优先使用 Git revert。本任务只有 UI、合同脚本、文档和证据报告；无需数据库或文件仓库回滚。
