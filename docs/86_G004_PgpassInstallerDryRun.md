# G004 · pgpass 安装器凭据 dry-run

G004 建立 PostgreSQL 非交互凭据初始化的安装器合同。目标是证明新电脑安装或初始化时不依赖 Codex、桌面进程或用户级 `PGPASSWORD` 自然继承，而是可写入受限的 `pgpass.conf` 并用 `psql -w` 验证。

## 合同入口

- Config: `configs/installer_credentials.defaults.yaml`
- Gate: `tools/run-g004-pgpass-installer-dry-run.ps1`
- Evidence: `docs/evidence/g004-pgpass-installer-dry-run-report.json`
- Unified gate: `tools/run-gates.ps1`

## 验证内容

合同脚本会：

1. 读取安装器凭据配置。
2. 使用临时 `APPDATA`，不修改真实 `%APPDATA%\postgresql\pgpass.conf`。
3. 写入临时 `postgresql\pgpass.conf`。
4. 收紧 ACL，并检查没有 `Everyone`、`BUILTIN\Users`、`Authenticated Users` 这类 broad principals。
5. 清空当前进程级 `PGPASSWORD`。
6. 执行 `psql -w` 连接当前数据库。
7. 删除临时凭据目录。
8. 写入不含密码的 evidence report。

## 安全边界

- 不修改真实用户 pgpass。
- 不把密码写入报告。
- 不把凭据机制暴露给普通教师。
- dry-run 只证明安装器凭据初始化链路可行；真实安装器仍必须在交互确认、ACL、回滚和用户 profile 路径确认后执行。

## 回滚

代码回滚使用 `git revert` 对应 G004 提交。合同脚本生成的临时 `%TEMP%\kqg-g004-pgpass-dry-run` 会在验证后删除；若异常中断，只删除该临时目录，不要删除真实 `%APPDATA%\postgresql`。
