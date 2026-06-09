# 2026-06-09 教师可见 walkthrough 证据

日期：2026-06-09

## 1. 目的

这份证据只回答一个问题：

> 当本地 API 与 Web 都处于 ready 状态时，普通教师入口是不是已经能真实落到主要工作区，而不是只停留在按钮或静态壳？

本次验证只覆盖本机联调可见层，不把结果夸大为现场发布闭环。

## 2. 运行前提

- Web 状态：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/start-local-web.ps1 -Status`
  - 结果：`status=running`，`ready=true`，`url=http://127.0.0.1:5173/`
- API 状态：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/start-local-api.ps1 -Status`
  - 结果：`status=running`，`ready=true`，`url=http://127.0.0.1:5275`
- 健康检查：`http://127.0.0.1:5275/health/ready`
  - 结果：`200`

## 3. 页面级结论

浏览器打开 `http://127.0.0.1:5173/` 后，页面顶部直接显示：

- `本机可用`
- `初中物理`
- `服务状态 正常`

普通教师入口四个主按钮均可见并可切到对应工作区：

1. `导入试卷`
   - 成功落到导入向导和异常确认区。
   - 页面正文包含 `2015 广州中考物理`、`真卷复核`、`数据库队列`、`24 题待复核`。
   - 说明当前页面不是离线占位，而是已经落到数据库队列视图。
2. `找题组卷`
   - 成功落到 `找题组卷工作台`。
   - 同屏可见 `题库检索`、`自然语言组卷`、`一键换题与撤销`、`试卷导出`。
   - 说明检索、题篮、细目表、换题、导出不是分散在未接通页面里。
3. `导入成绩`
   - 成功落到 `成绩导入分析工作台`。
   - 同屏可见 `字段映射预览`、`异常行`、`小题映射预览`、`知识点分析`、`报告导出路径`。
   - 说明成绩导入、异常处理和分析导出工作区已经可见。
4. `查看分析`
   - 成功落到 `讲评分析`。
   - 点击 `查看摘要` 后，可见 `班级得分率 87.5%`、`优先讲评 运动快慢与速度`、`下一步 加入巩固题`。
   - 说明讲评摘要区不是空白占位，教师能看到下一步建议。

## 4. 控制台结果

- 浏览器控制台累计消息：`3`
- `Errors: 0`
- `Warnings: 0`

本次 walkthrough 过程中没有新增前端错误或警告。

## 5. 截图

- 首页壳：[20260609-home.png](./20260609-teacher-visible-walkthrough/20260609-home.png)
- 导入试卷：[20260609-import.png](./20260609-teacher-visible-walkthrough/20260609-import.png)
- 找题组卷：[20260609-compose.png](./20260609-teacher-visible-walkthrough/20260609-compose.png)
- 导入成绩：[20260609-score-import.png](./20260609-teacher-visible-walkthrough/20260609-score-import.png)
- 查看分析：[20260609-analysis.png](./20260609-teacher-visible-walkthrough/20260609-analysis.png)
- 讲评摘要展开后：[20260609-analysis-summary.png](./20260609-teacher-visible-walkthrough/20260609-analysis-summary.png)

## 6. 真实边界

这份证据可以支持如下说法：

- 教师四入口在本机联调状态下可见、可切换、可落到主要工作区。
- API 打开后，页面会进入真实服务联调状态，而不是仅依赖本地静态占位。
- `试题录入 / 组卷 / 成绩导入 / 分析` 这些教师主链路，至少在页面级已经不是“未落盘、不可见”状态。

这份证据仍然不能支持如下说法：

- 不能据此宣称 `REAL005` 已关闭。
- 不能据此宣称 `P001` 现场链路已闭环。
- 不能据此宣称隔离机、打印机、域权限、真实网络和现场签收问题已经被本机验证替代。
