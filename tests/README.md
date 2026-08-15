# tests

- `api/`：通过生产模块接口验证 API 与领域行为。
- `workers/test_worker.py`：验证当前 document Worker 主链。
- `workers/test_curriculum_exam_c002r_drill.py`：验证仍在使用的 C002R 隔离演练工具。
- `workers/test_host_capability_diagnostic.py`：验证 P001 只读机器诊断。
- `verification/`：只验证 changed-path Slice 选择。
- `golden-import/`：备份与隐私扫描仍消费的最小合成 fixture。

历史 task-by-task verifier 与其内部实现测试已退役；完成记录从 Git 历史取证。
