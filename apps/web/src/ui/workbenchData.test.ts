import { describe, expect, it } from 'vitest'
import {
  questionSearchFilterChips,
  questionSearchParamsFor,
  realExamDifficultyOptions,
} from './workbenchData'

describe('question search presets', () => {
  it('maps every visible preset to a real API filter dimension', () => {
    expect(questionSearchFilterChips.map((item) => item.filter)).toEqual([
      'all-real',
      'year',
      'question-type',
      'difficulty',
      'image',
      'knowledge',
      'exam-point',
    ])
    expect(questionSearchParamsFor('year')).toMatchObject({ year: 2025, status: 'pending_review' })
    expect(questionSearchParamsFor('knowledge')).toHaveProperty('knowledgeCandidateId')
    expect(questionSearchParamsFor('exam-point')).toHaveProperty('examPointCandidateId')
    expect(questionSearchParamsFor('difficulty')).toMatchObject({ difficultyMin: 0.4, difficultyMax: 0.7 })
    expect(questionSearchParamsFor('image')).toMatchObject({ hasImage: true })
  })

  it('offers teacher-facing difficulty choices while retaining numeric API values', () => {
    expect(realExamDifficultyOptions.map((option) => option.label)).toEqual([
      '难度偏基础',
      '难度中等',
      '难度略高',
    ])
    expect(realExamDifficultyOptions.every((option) => typeof option.value === 'number')).toBe(true)
  })
})
