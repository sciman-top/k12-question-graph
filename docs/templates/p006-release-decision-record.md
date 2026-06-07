# P006 发布裁决记录

用途：用于记录 `P006` 的正式发布裁决。该记录页只负责把发布判断压缩成可签字的单页记录，不替代 `docs/109_ReleaseGoNoGoCard.md`。

## 0. 基本信息
- 日期：
- 裁决：`go / no_go / go_with_named_exceptions`
- 目标里程碑：`P001 readiness -> P003/P005/P006 closeout -> v0.1 live pilot release decision`
- release candidate：
- deployment mode：
- 试点范围：

## 1. 证据锚点
- `P001 readiness pack`：
- `P005 triage`：
- `Go / No-Go card`：
- full gate：
- roadmap guard：
- backup evidence：
- restore evidence：
- privacy evidence：
- role audit evidence：

## 2. 门禁复核
- build / test / contract / hotspot：
- backup / restore：
- teacher efficiency：
- privacy / authorization：
- role audit：
- 剩余现场阻断项：

## 3. 例外项（如有）

### exception-001
- 标题：
- owner：
- expires_at：
- recovery_plan：
- evidence_link：
- accepted_risk：

## 4. Tag 与回退
- 是否创建 tag candidate：
- tag 名称：
- rollback window：
- disable switch plan：

## 5. 最终理由
- 发布理由：

## 6. 签字
- 发布负责人：
- 管理员负责人：
- 数据责任方代表：
- 试点支持负责人：

## 7. 下一步
1. 若为 `No-Go`，保持 `P006` 为 `待办`，不得创建 tag candidate。
2. 若为 `Go with named exceptions`，必须把例外 owner、到期时间和恢复计划填完整。
3. 只有本记录、对应 JSON、以及 `docs/109_ReleaseGoNoGoCard.md` 一致时，才允许继续后续发布动作。
