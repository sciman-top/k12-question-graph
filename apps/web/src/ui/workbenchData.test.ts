import { describe, expect, it } from 'vitest'
import {
  isQuestionAssetRegion,
  questionEvidenceFilterOptions,
  questionEvidenceParamsFor,
  resolveSourcePreviewUrl,
  questionSearchFilterChips,
  questionSearchParamsFor,
  realExamDifficultyOptions,
} from './workbenchData'

import type { QuestionSourceRegionContract } from '../api/contracts'

describe('question search presets', () => {
  it('treats the Guangzhou v2 question crop as the complete teacher-facing question image', () => {
    const region: QuestionSourceRegionContract = {
      id: 'region-1',
      sourceDocumentId: 'paper-1',
      sourceTitle: '2020广州中考',
      pageNumber: 1,
      x: 5,
      y: 10,
      width: 90,
      height: 20,
      coordinateUnit: 'percent',
      regionType: 'guangzhou_v2_question_candidate',
      screenshotRelativePath: 'generated/question-regions/2020/q01.png',
      screenshotUrl: '/source-regions/region-1/screenshot',
      pageScreenshotUrl: '/source-regions/region-1/page-screenshot',
    }

    expect(isQuestionAssetRegion(region)).toBe(true)
  })

  it('resolves source previews against the app origin before navigating a blank tab', () => {
    expect(resolveSourcePreviewUrl('/source-regions/region-1/page-screenshot', 'http://127.0.0.1:5175')).toBe(
      'http://127.0.0.1:5175/source-regions/region-1/page-screenshot',
    )
  })

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

  it('keeps evidence modes isolated and makes previews explicit', () => {
    expect(questionEvidenceParamsFor('all', 'active')).toMatchObject({
      evidenceMode: 'active',
      previewMode: false,
    })
    expect(questionEvidenceParamsFor('ability', 'candidate')).toMatchObject({
      evidenceMode: 'candidate',
      previewMode: true,
      ability: '科学推理',
    })
    expect(questionEvidenceParamsFor('profile', 'reviewed')).toMatchObject({
      evidenceMode: 'reviewed',
      previewMode: true,
      profileId: 'EPHY-GUANGZHOU-074E4C66013F8AE6',
    })
  })

  it('offers every teacher-facing evidence dimension without mixing difficulty sources', () => {
    const filters = questionEvidenceFilterOptions.map((option) => option.value)
    expect(filters).toEqual([
      'all',
      'requirement',
      'ability',
      'cognitive',
      'method',
      'context',
      'representation',
      'profile',
      'observed-difficulty',
    ])
    expect(questionEvidenceParamsFor('observed-difficulty', 'candidate')).toMatchObject({
      observedDifficultyMin: 0.5,
      observedDifficultyMax: 1,
    })
    expect(questionEvidenceParamsFor('observed-difficulty', 'candidate')).not.toHaveProperty(
      'estimatedDifficultyMin',
    )
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
