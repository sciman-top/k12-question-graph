# 47 · B008 P1 Proxy Scenario 证据

执行日期：2026-05-03。

## 1. 完成范围

- 新增 P1 非现场流程脚本：
  - `tools/run-p1-proxy-scenario.ps1`
- 脚本复用 B007 黄金样本导入，验证代理场景可完成：
  - 上传。
  - 页面/来源预览。
  - 修正异常项的操作清单。
  - 保存题目。
  - 回看来源。
  - 失败接管步骤记录。
  - 估算教师处理耗时。
- 不要求真实教师现场验收；当前为代理场景 walkthrough。

## 2. 独立脚本结果

命令：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-p1-proxy-scenario.ps1
```

关键输出：

```json
{
  "status": "pass",
  "uploadedSampleCount": 5,
  "previewVerified": true,
  "questionSaved": true,
  "sourceReviewVerified": true,
  "confirmationItemCount": 6,
  "estimatedTeacherMinutes": 8
}
```

失败接管步骤：

```text
keep original file
keep adapter diagnostics
manual box source region
split or merge affected segments
skip bad page when needed
rerun adapter when source is fixed
```

## 3. Gate 结果

命令：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-gates.ps1
```

关键输出应包含：

```text
b008 p1 proxy scenario: pass
```

## 4. 回滚

代码/文档回滚：

```powershell
git restore --source=HEAD -- tools/run-p1-proxy-scenario.ps1 tools/run-gates.ps1 tools/README.md tasks/backlog.csv docs/47_B008_P1ProxyScenario.md
```

B008 不新增数据库 migration；脚本会在本机数据库追加 synthetic 回归记录。
