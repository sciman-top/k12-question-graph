# R002 queue worker scale evaluation checklist
- [ ] `P006` 已完成并有 release decision record。
- [ ] 先采集 BackgroundService 吞吐/可靠性 operational metrics。
- [ ] 仅在瓶颈成立时评估 Hangfire / RabbitMQ。
- [ ] 形成 ADR 与回退策略。
