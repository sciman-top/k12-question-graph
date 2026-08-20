# P001 live pilot release checklist

用途：用于 `P001` 试点学校部署预演。默认采用“远程自动证据 -> 目标机远程执行 -> 现场异常补证”模式；该清单只定义执行项与证据锚点，不替代目标环境事实和责任人确认。

## 0. 执行边界
- [ ] 目标环境为隔离机器，非开发仓库主机。
- [ ] 本次仅执行安装向导、备份、恢复、权限审计和教师入口 smoke。
- [ ] 执行前确认回滚路径：backup manifest + restore command + operator rollback note。
- [ ] 带上 `REAL001-REAL012` 真卷证据包，尤其是 REAL012 `quality report`；若报告仍为 `not_closed`，不得宣称整卷或 2015-2025 全闭环完成。

## 0.1 到场前必须已闭合的非现场预检
- [ ] 先运行 `tools/run-remote-first-evidence-pack.ps1 -Mode Collect`，使用同一 commit 和证据哈希生成远程执行包；自动证据缺失时 fail-closed。
- [ ] `NS904` readiness pack 已刷新。
- [ ] `NS906` 视觉代理已刷新，覆盖四入口 route smoke、artifact、source screenshot 和异常报告。
- [ ] `NS801-NS806` 安装、备份、恢复、升级、健康面板证据已刷新。
- [ ] 若上述客观项仍未闭合，不允许把它们留到隔离机现场临时手工补做。

## 0.2 证据模式
- [ ] `remote_automated`：Release、roadmap、closeout、route smoke、artifact、截图和视觉代理由脚本汇总，操作者不重复核对。
- [ ] `remote_target_host`：安装、health/readiness、备份恢复、网络探针、域权限和文件目录访问优先通过目标机远程会话执行并留结构化 receipt。
- [ ] `onsite_exception_only`：仅当目标机不可远程访问，或打印机、学校网络、权限域/文件共享异常无法远程复现时到场。
- [ ] 所有模式都只减少执行地点和重复检查，不自动关闭 `P001`，不替代操作者和责任人确认。
- [ ] 目标机和后续阶段证据使用 `accountable-acceptance-bundle-template.json` 绑定当前 commit、文件 SHA-256、最低责任角色和身份系统审计引用；先运行 `tools/run-accountable-acceptance-bundle.ps1 -Mode DryRun`，结构未通过时不得进入正式接受。

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
- [ ] 本节只验证隔离机特有事实；路线、工件和版面客观检查应以前置 automation/visual surrogate 结果为主。

## 4.1 学校环境事实
- [ ] 学校网络与异常网络路径可由目标机远程探针证明；仅异常未解释时转现场。
- [ ] 域权限、本机账号和文件目录/共享访问可由专用测试账号远程验证；不得使用生产管理员常驻凭据。
- [ ] 若发布承诺包含真实纸张交付，必须完成真实打印；否则可接受驱动、队列、页面尺寸、分页和 spool/PDF 的等价打印预检，并明确记录未出纸边界。

## 5. 证据归档
- [ ] 在 `docs/evidence/` 写入本轮 evidence（含命令、退出码、关键输出、风险、回滚）。
- [ ] 使用 `docs/templates/p001-isolated-machine-evidence-template.md` 回填目标环境事实、四入口耗时/卡点、打印/网络/权限域结果、证据模式和操作者电子签收。
- [ ] 记录 `platform_na` / `gate_na`（如有）：reason / alternative_verification / evidence_link / expires_at。
- [ ] 更新 `tasks/backlog.csv` 的 P001 状态（仅当现场证据闭环完成时）。
