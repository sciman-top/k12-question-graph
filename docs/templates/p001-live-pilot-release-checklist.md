# P001 live pilot release checklist

用途：用于 `P001` 试点学校部署预演。该清单只定义执行项与证据锚点，不替代现场执行记录。

## 0. 执行边界
- [ ] 目标环境为隔离机器，非开发仓库主机。
- [ ] 本次仅执行安装向导、备份、恢复、权限审计和教师入口 smoke。
- [ ] 执行前确认回滚路径：backup manifest + restore command + operator rollback note。
- [ ] 带上 `REAL001-REAL012` 真卷证据包，尤其是 REAL012 `quality report`；若报告仍为 `not_closed`，不得宣称整卷或 2015-2025 全闭环完成。

## 1. 安装与初始化
- [ ] 执行安装向导，记录安装包版本、安装目录、数据目录和备份目录。
- [ ] 验证 PostgreSQL 连接与 pgpass 非交互可用，不在日志写明文密码。
- [ ] 运行 host capability diagnostic、worker profile diagnostic 和 O008 technology refresh `report_only`，记录新硬件/OCR/模型候选但不安装、不下载、不切默认。
- [ ] 保存初始化日志路径和关键输出摘要。

## 2. 备份与恢复
- [ ] 生成 backup manifest 并校验通过。
- [ ] 运行恢复演练（至少一次 dry-run 或隔离恢复）。
- [ ] 记录恢复后健康检查结果与异常项。

## 3. 权限与审计
- [ ] 验证 teacher/group_lead/admin 角色分离。
- [ ] 验证 `/api/admin/*` 与 `/internal/ai/*` 未授权 fail-closed。
- [ ] 验证高风险后台操作有结构化审计日志。

## 4. 教师入口 smoke
- [ ] 导入入口可完成上传 -> 任务状态 -> 异常处理基本路径。
- [ ] 组卷入口可完成检索 -> 题篮 -> 导出基本路径。
- [ ] 成绩入口可完成模板导入与异常提示基本路径。
- [ ] 分析入口可完成班级讲评摘要查看基本路径。

## 5. 证据归档
- [ ] 在 `docs/evidence/` 写入本轮 evidence（含命令、退出码、关键输出、风险、回滚）。
- [ ] 记录 `platform_na` / `gate_na`（如有）：reason / alternative_verification / evidence_link / expires_at。
- [ ] 更新 `tasks/backlog.csv` 的 P001 状态（仅当现场证据闭环完成时）。
