# 06 · 物理知识点本体与知识图谱

## 1. 原则

对物理学科，**学科知识点本体的地位高于课程标准**。课程标准、教材版本、地区考点都作为映射层。

```text
物理学科知识本体
> 教材版本映射
> 地区考试考点画像
> 课程标准映射
> 试题/成绩/学情数据
```

## 2. 为什么这样设计

物理核心知识几十年相对稳定，教材章节和课程标准表述会变。系统应保持知识点稳定，通过映射处理不同教材版本、课标版本、地区考法差异。

正式 `KnowledgeNode` 不由系统预置清单直接定稿。C002 的完成条件是教师先录入或导入各版本教材、学科课程标准、近年当地中考/高考真题、校本试卷等资料，再从这些来源中提炼候选知识点，经人工审核后形成可用版本。开发阶段允许保留 draft bootstrap 作为 schema/gate 样本，但必须标记为非权威草稿，不能作为正式校本知识本体。

## 3. 本体结构

```text
PhysicsKnowledgeOntology
├── CoreConcept              核心概念
├── LawAndFormula            规律与公式
├── Model                    物理模型
├── Experiment               实验与探究
├── Method                   方法与思想
├── Misconception            易错点/错误概念
├── Representation           图像、表格、图示、实验图
├── ProblemType              题型/问题类型
└── AbilityDimension         能力维度
```

## 4. KnowledgeNode 字段

| 字段 | 说明 |
|---|---|
| stable_id | 稳定 ID，例如 PHY-JH-MECH-BUOYANCY |
| canonical_name | 标准名称 |
| aliases | 别名 |
| subject/stage | 学科/学段 |
| level | L1-L5 粒度 |
| parent_id | 上级节点 |
| prerequisite_nodes | 前置知识 |
| related_nodes | 相关知识 |
| formulas | 公式 |
| experiments | 实验 |
| common_problem_types | 常见题型 |
| common_misconceptions | 常见误区 |
| representations | 常见图像/表格/实验图 |
| status | active/deprecated/merged |
| version | 版本 |

## 5. 粒度建议

| 层级 | 示例 |
|---|---|
| L1 模块 | 力学 |
| L2 专题 | 浮力 |
| L3 核心知识 | 阿基米德原理、浮沉条件 |
| L4 方法/题型 | 称重法求浮力、排液法求浮力 |
| L5 易错点 | 误用物体体积代替排开液体体积 |

v0.1 组卷主要使用 L2/L3，错因分析可使用 L4/L5。

## 6. AI 初建 + 人工审核流程

```text
导入教材目录 / 课程标准 / 本地真题 / 校本试卷
→ AI 提取候选知识点、考点、题型、方法、易错点
→ AI 与现有知识本体匹配
→ 生成初版图谱和映射建议
→ 标记低置信度/高影响节点
→ 备课组审核关键节点
→ 形成 v1.0 知识体系
```

## 7. 映射表

```text
KnowledgeMapping
- source_type: textbook_chapter / curriculum_standard / region_exam_point / question / exam_result
- source_id
- knowledge_node_id
- mapping_type: primary / secondary / prerequisite / extension
- weight
- confidence
- ai_generated
- review_status
- version
```

## 8. 教材改版处理

知识点不改，更新映射。

```text
知识点稳定
教材章节可变
考点画像可变
试题保留原始来源
组卷按当前版本映射
旧卷按历史快照复现
```

## 9. 影响分析

教材、课标或知识映射变更时，系统应生成影响报告：

```text
影响试题数量
影响单元卷数量
影响历史报告数量
需要人工审核的高频考点
建议迁移/停用/保留的映射
```
