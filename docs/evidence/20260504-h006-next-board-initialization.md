# 2026-05-04 H006 下一轮任务看板初始化

## 规则 ID

- R1：当前落点为 H0 阶段收口的 `H006`；目标归宿是把 H-R 阶段任务作为新主线，并标记 H/I/J 为近期执行项。
- R2：本轮只更新路线图看板、backlog 状态和证据，不改运行功能。
- R4：低风险规划层变更；不执行数据库、备份、active switch、真实 AI 或远端同步。
- R6：H006 的验证为 `tasks/backlog.csv` parse、`docs/87` 看板检查和 roadmap guard。
- R8：依据、命令、证据和回滚如下。

## 看板结论

- H-R 新主线共 70 项。
- 阶段分布：H0 7、I0 7、J0 6、K0 6、L0 7、M0 6、N0 6、O0 7、P0-live 6、Q0 5、R0 7。
- H001-H005 已完成。
- H006 完成本次看板初始化后，H0 剩余 `H007 external benchmark drift guard`。
- H007 完成后，近期执行进入 I0：先做 `I001 普通教师首页与导航产品化`。
- 近期只执行 H/I/J。K0 以后保留为长期路线，不因任务已写入 backlog 就提前扩大功能面。

## 当前近期队列

| 顺序 | ID | 阶段 | 任务 | 前置 |
|---:|---|---|---|---|
| 1 | H007 | H0 | external benchmark drift guard | H006 |
| 2 | I001 | I0 | 普通教师首页与导航产品化 | H007 |
| 3 | I002 | I0 | 导入试卷向导产品化 | I001 |
| 4 | I003 | I0 | 人工确认队列可用性强化 | I002 |
| 5 | I004 | I0 | 找题组卷工作台整合 | I001 |
| 6 | I005 | I0 | 成绩导入分析工作台整合 | I001 |
| 7 | I006 | I0 | 新手示例与默认值闭环 | I001 |
| 8 | I007 | I0 | server-state 与 typed API boundary | I001 |
| 9 | J001 | J0 | OpenXML docx 真实解析 adapter | I002 |
| 10 | J002 | J0 | PDF 文本版解析 adapter | J001 |
| 11 | J003 | J0 | 扫描版 PDF 图片 OCR adapter | J002 |
| 12 | J004 | J0 | 公式 表格 题图保真回归 | J001 |
| 13 | J005 | J0 | Adapter 版本诊断和工具供应链门禁 | J001 |
| 14 | J006 | J0 | 导入准确率基线与人工工作量报告 | J003 |

## 已执行命令

```powershell
python -c "import csv, collections; rows=list(csv.DictReader(open('tasks/backlog.csv',encoding='utf-8-sig'))); hr=[r for r in rows if r['id'] >= 'H001']; print('hr_total', len(hr)); print('by_phase', dict(collections.Counter(r['phase'] for r in hr))); print('by_status', dict(collections.Counter(r['status'] for r in hr)))"
```

关键输出：

```text
hr_total 70
by_phase {'H0': 7, 'I0': 7, 'J0': 6, 'K0': 6, 'L0': 7, 'M0': 6, 'N0': 6, 'O0': 7, 'P0-live': 6, 'Q0': 5, 'R0': 7}
```

## 回滚

```powershell
git diff -- docs/87_PhaseCloseoutAndFullRoadmap.md tasks/backlog.csv docs/evidence/20260504-h006-next-board-initialization.md
```

如需撤销 H006 收口，只还原 `docs/87_PhaseCloseoutAndFullRoadmap.md` 的当前执行看板段，把 `tasks/backlog.csv` 中 `H006` 状态改回 `待办`，并删除本证据文件。
