# tests

- `api/`：通过生产模块接口验证 API 与领域行为。
- `workers/test_worker.py`：验证当前 document Worker 主链。
- `workers/test_golden_regression.py`：worker document model 的规范化输出回归;golden 文件与重建入口在 `golden-import/`。
- `workers/test_host_capability_diagnostic.py`：验证 P001 只读机器诊断。
- `verification/`：只验证 changed-path Slice 选择。
- `golden-import/`：备份与隐私扫描消费的最小合成 fixture,以及 golden 输出回归的合成文档与 `golden_runner.py`(显式 `--regenerate` 重建)。

前端(vitest)测试不在本目录,位于 `apps/web/src/**/*.{test,tsx,ts}`;由 Quick/Slice 的 frontend-tests 步骤执行。

历史 task-by-task verifier 与其内部实现测试已退役;完成记录从 Git 历史取证。
