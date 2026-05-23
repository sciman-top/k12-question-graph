# R002 queue worker scale evaluation checklist

- [ ] `P006` 已完成并有 release decision record。
- [ ] `P001` 已完成隔离机或现场代理运行证据，且包含队列深度、任务耗时、失败恢复和人工接管影响。
- [ ] 先采集 PostgreSQL job store + BackgroundService 的 throughput、latency p50/p95、queue depth、lease、retry、stuck-job 和 failure baseline。
- [ ] 证明当前 BackgroundService loop 存在真实瓶颈，且该瓶颈会影响教师导入、审核、导出或成绩分析工作流。
- [ ] Hangfire 仅在 operational dashboard、delayed/recurrent jobs、retry policy 或 operator visibility 缺口成立时进入 admission。
- [ ] RabbitMQ 仅在多机 Worker、严格队列隔离、broker ops owner、网络/防火墙和备份恢复证据齐备后进入 admission。
- [ ] 形成 ADR、迁移计划、rollback/disable switch 和 teacher workflow impact 说明。
- [ ] fail-closed：缺 metrics、owner、rollback 或现场证据时，不新增 Hangfire/RabbitMQ package、schema、dashboard、broker service 或默认 worker route。
