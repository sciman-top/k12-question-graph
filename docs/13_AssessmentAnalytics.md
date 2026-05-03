# 13 · 成绩导入与学情分析

## 1. 原则

先 CTT，后 IRT。v0.1 使用经典测量理论指标：得分率、区分度、选项分布、空白率、标准分、百分位、知识点掌握率。

## 2. 成绩导入

支持：

- 只录总分。
- 录小题分。
- 录小问分。
- 不固定模板，使用字段映射。
- 映射保存到教师偏好。

流程：

```text
上传 Excel
→ 自动识别字段
→ 匹配试卷题号
→ 预览异常
→ 确认导入
→ 生成分析
```

## 3. 分析维度

### 3.1 题目层面

- 得分率。
- 区分度。
- 空白率。
- 选项分布。
- 错因标签。
- 历史使用统计。

### 3.2 知识点层面

- 知识点得分率。
- 小问分值权重。
- 班级薄弱知识点。
- 学生个人薄弱点。
- 与历史表现对比。

### 3.3 学生层面

- 原始分趋势。
- 标准分趋势。
- 班级百分位变化。
- 知识点掌握度变化。
- 错因变化。
- 所属分层建议。

### 3.4 班级层面

- 均分、中位数、标准差。
- 优秀率、及格率、低分率。
- 分数段。
- 知识点热力图。
- 题型表现。
- A/B/C 分层练习建议。

## 4. 进步/退步判断

不能只比较原始分。应综合：

```text
原始分变化
+ 标准分变化
+ 百分位变化
+ 知识点掌握变化
+ 同类题表现变化
+ 错因减少情况
```

输出：上升、稳定、波动、下降、数据不足。

## 5. 同一道题跨年份统计

QuestionObservedStats 按考试、年份、班级、样本量单独保存，不简单混合。

```text
question_id
exam_id
school_year
grade
class_group
sample_size
score_rate
discrimination
blank_rate
option_distribution
exam_context
```

## 6. 输出格式

| 对象 | 推荐输出 |
|---|---|
| 学生个人 | Word/PDF、图片长图 |
| 班级 | Excel + 图表 + Word/PDF 摘要 |
| 年级/备课组 | Excel 工作簿 + 教研报告 |

## 7. 分层练习

日常打印优先 A/B/C 三套，而不是每人一份。

- A：基础巩固。
- B：标准提升。
- C：拔高拓展。

个人推荐可通过 PDF/图片发给学生或家长，但后置。

## 8. F003 当前合同

F003 已完成 draft/test 最小合同：

- 入口：`tools/run-f003-knowledge-mastery-analysis-contract.ps1`。
- 证据：`docs/evidence/f003-knowledge-mastery-analysis-report.json`。
- 输入：synthetic 小题分和当前 active 知识版本引用。
- 输出：班级总分得分率、知识点得分率、区分度、薄弱知识点和学生掌握摘要。
- 边界：`productionEligible=false`、`realStudentDataUsed=false`、`noProductionHistoryWrite=true`。

该合同不代表真实学生成绩已导入，也不改写正式历史学情。
