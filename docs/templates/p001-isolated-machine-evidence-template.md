# P001 isolated-machine execution evidence template

用途：用于 `P001 / NS1001` 隔离机器部署预演的现场证据记录。该模板只负责回填现场事实、命令、风险和签收，不替代 `docs/templates/p001-live-pilot-release-checklist.md` 的执行清单，也不替代 `docs/109_ReleaseGoNoGoCard.md` 的最终发布裁决。

建议落点：`docs/evidence/<date>-p001-isolated-machine.md`

## 0. 基本信息
- 日期：
- 机器标识：
- 环境位置：
- 执行人：
- 陪同人 / 支持负责人：
- 当前版本 / 安装包：
- 回滚负责人：

## 1. 前置证据锚点
- `P001` preflight report：
- `NS904` readiness pack：
- `NS906` visual surrogate：
- `NS1308` release evidence pack：
- `REAL012` quality report：
- `docs/templates/p001-live-pilot-release-checklist.md` 已核对：`是 / 否`

## 2. 安装与初始化
- 安装目录：
- 数据目录：
- 备份目录：
- PostgreSQL / pgpass 非交互结果：
- host capability diagnostic 结果摘要：
- worker profile diagnostic 结果摘要：
- technology refresh `report_only` 结果摘要：
- 初始化日志路径：

命令与关键输出：
```text
<command>
<exit_code>
<key_output>
```

## 3. 备份与恢复
- backup manifest 路径：
- verify 结果：
- restore drill 结果：
- 恢复后 health/readiness 结果：
- 现场回滚命令：

命令与关键输出：
```text
<command>
<exit_code>
<key_output>
```

## 4. 权限与审计
- teacher / group_lead / admin 分离结果：
- `/api/admin/*` fail-closed 结果：
- `/internal/ai/*` fail-closed 结果：
- 高风险操作 audit 记录路径：
- 权限域 / 本机账号 / 文件目录访问结果：

命令与关键输出：
```text
<command>
<exit_code>
<key_output>
```

## 5. 四入口 Smoke
### 5.1 导入入口
- 是否通过：
- 耗时：
- 卡点：
- 接管点：
- 回退动作：

### 5.2 组卷入口
- 是否通过：
- 耗时：
- 卡点：
- 接管点：
- 回退动作：

### 5.3 成绩入口
- 是否通过：
- 耗时：
- 卡点：
- 接管点：
- 回退动作：

### 5.4 分析入口
- 是否通过：
- 耗时：
- 卡点：
- 接管点：
- 回退动作：

## 6. 打印 / 网络 / 权限域
- 学校打印机 / 等价打印预检：
- 学校网络访问与断网降级：
- 域权限 / 本机权限结果：
- 仍未通过的现场阻断项：

## 7. 风险与 N/A
- `platform_na`：
  - reason：
  - alternative_verification：
  - evidence_link：
  - expires_at：
- `gate_na`：
  - reason：
  - alternative_verification：
  - evidence_link：
  - expires_at：

## 8. 操作者签收
- 最终结论：`可继续 P002 / 继续阻断`
- 剩余风险：
- 回滚确认：
- 执行人签收：
- 支持负责人签收：
- 发布负责人复核：

## 9. 下一步
1. 若仍有现场阻断，保持 `P001` 为 `待办`，只补事实不改状态。
2. 只有安装、备份恢复、权限审计、四入口 smoke、打印、网络、权限域和操作者签收都闭环后，才允许更新 `tasks/backlog.csv` 中的 `P001`。
3. `P001` 关闭后再进入 `P002` 教师代理试点，不得跳序。
