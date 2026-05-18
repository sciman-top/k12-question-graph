# 20260518 P001 live pilot readiness preflight

## 目标
- 在 `REAL012` 已完成后，刷新 `P001` 试点学校部署预演的 preflight 准入口径。
- 只证明隔离机执行前的证据包已经齐备；不伪造隔离机器安装、现场教师试点或正式发布。

## 当前结论
- `P001` 继续保持 `待办`。
- `S012/O004B/O006/O007/O008/REAL012` 均已在 backlog 标记为 `已完成`。
- `REAL001-REAL012` 证据包已纳入 `tools/run-p001-live-pilot-readiness-preflight-contract.ps1` 检查。
- `REAL012` 质量报告仍保持 `not_closed`，说明真实题样题已可用于检索、题篮、导出、学情引用，但整卷/2015-2025 全闭环不能宣称完成。
- `host capability`、`worker profile`、`technology refresh` 均只读检查：不安装、不下载、不切默认、不处理真实未脱敏材料。

## 本轮边界
- 本轮是 preflight，未在隔离机器执行安装向导。
- 本轮不执行真实学校网络、打印机、权限域或现场老师入口 smoke。
- 本轮不导入真实学生成绩，不启用外部 AI 生产写入，不写正式历史学情口径。

## N/A 记录
- `platform_na`:
  - reason: 当前会话主机不是目标隔离机器，不能形成 P001 隔离机部署证据。
  - alternative_verification: 刷新 P001 preflight contract，检查 REAL012 后的真实题证据包、host capability、worker profile 和 technology refresh。
  - evidence_link: `docs/evidence/20260518-p001-live-pilot-readiness-preflight-report.json`
  - expires_at: `2026-05-25`
- `gate_na`:
  - reason: P001 验收必须包含隔离机器安装向导、备份恢复、权限审计和四个教师入口 smoke，本机 dry-run 不能替代。
  - alternative_verification: 保持 `P001` 为 `待办`，只输出可执行 checklist 与 fail-closed blocker。
  - evidence_link: `docs/templates/p001-live-pilot-release-checklist.md`
  - expires_at: `2026-05-25`

## 下一步
1. 在隔离机器执行 `docs/templates/p001-live-pilot-release-checklist.md`。
2. 回填安装向导、备份、恢复、权限审计、四入口 smoke 和 REAL012 quality report 复核证据。
3. 只有隔离机证据完整后，才允许把 `P001` 从 `待办` 切到 `已完成`。
