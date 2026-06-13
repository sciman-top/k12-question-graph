# 110 · 工程终态对照清单

日期：2026-06-09。

用途：给后续评审、扩范围、换栈、引新工具时快速对照，避免每次重读长评审。

长期判断以 `docs/decisions/ADR-014-recommended-engineering-endstate-and-stack-boundary.md` 为准；本清单只是短入口。

## 1. 推荐保留

- `Windows/LAN-first`
- `ASP.NET Core modular monolith`
- `Windows Service` 主运行形态
- `PostgreSQL + local file store`
- `React + TypeScript + Vite SPA + Ant Design`
- `TanStack Query only for server state`
- `Python document/OCR/AI adapters with explicit profiles`
- `versioned domain assets + review / rollback`
- `AI as candidate/draft pipeline only`
- `profile-map-first interoperability`
- `backup / restore / upgrade / release evidence before live`
- `automation-first + reference-basis + live-closeout guards`

## 2. 默认先问自己

1. 这项变更是否真的减少教师步骤、选择或培训成本？
2. 它是否破坏离线优先、校内部署或低运维目标？
3. 它是否削弱了备份、恢复、回滚或审计能力？
4. 它是否把外部标准、第三方工具或 AI 输出直接污染内部主模型？
5. 它是否有真实 benchmark、真实现场约束变化或真实对接需求支撑？
6. 若它属于高风险任务，`tasks/reference-basis-requirements.csv` 是否已经绑定了官方与本地参考锚点？

只要有一项回答不清，就不应默认进入主线。

## 3. 默认后置

- 微服务 / RabbitMQ / Kafka / Kubernetes
- Elasticsearch / Meilisearch / Neo4j
- Next.js / SSR 默认化
- 完整 QTI / CASE / OneRoster import/export
- 本地小模型默认生产路由
- 外部 AI 直接写 `active`
- 多校 SaaS / 公网多租户 / 学生端 / 家长端

## 4. 何时允许偏离

只有在以下至少一项成立时，才允许偏离默认终态：

- 真实学校环境或部署约束已变化
- 真实 benchmark 证明现有路线明显不足
- 真实对接需求和授权样本已经出现
- 真实维护成本已高于替代方案

偏离后必须补新 ADR 或 superseding ADR。
