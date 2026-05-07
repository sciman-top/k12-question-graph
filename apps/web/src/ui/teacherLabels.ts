const teacherText: Record<string, string> = {
  calculation: '计算题',
  active: '当前版本',
  draft: '草稿',
  draft_dynamic_asset: '示例约束',
  draft_test: '示例流程',
  experiment: '实验题',
  golden: '样本来源',
  grade_8: '八年级',
  medium: '难度中等',
  medium_hard: '难度略高',
  pending_review: '需确认',
  physics: '物理',
  queued: '排队中',
  retry_waiting: '等待重试',
  running: '处理中',
  failed: '失败',
  textbook: '教材',
  curriculum_standard: '课程标准',
  local_exam_paper: '当地真题',
  exam_analysis_report: '考情年报',
  school_paper: '校本资料',
  teacher_original: '教师原创',
  short_answer: '简答题',
  single_choice: '单选题',
  synthetic: '示例来源',
  unit_practice: '单元练习',
  uploaded_metadata: '已记录元数据',
  manual_review: '需人工接管',
  split: '拆分',
  merge: '合并',
  skip: '跳过',
  rerun: '重跑',
  save_question: '保存题目',
}

export const teacherLabelFor = (value: string) => teacherText[value] ?? value

export const teacherDifficultyLabelFor = (value: string | number) => {
  if (typeof value === 'string' && value in teacherText) {
    return teacherText[value]
  }

  const numericValue = Number(value)
  if (Number.isNaN(numericValue)) {
    return teacherLabelFor(String(value))
  }

  if (numericValue < 0.45) {
    return '难度偏基础'
  }
  if (numericValue < 0.65) {
    return '难度中等'
  }
  return '难度略高'
}

export const teacherDifficultyRangeLabelFor = (value: string) => {
  if (value === '0.4-0.7') {
    return '难度中等到略高'
  }
  if (value === '0.55-0.7') {
    return '难度中等到略高'
  }
  return value
}
