const teacherText: Record<string, string> = {
  calculation: '计算题',
  draft_dynamic_asset: '示例约束',
  draft_test: '示例流程',
  experiment: '实验题',
  golden: '样本来源',
  pending_review: '需确认',
  short_answer: '简答题',
  single_choice: '单选题',
  synthetic: '示例来源',
}

export const teacherLabelFor = (value: string) => teacherText[value] ?? value
