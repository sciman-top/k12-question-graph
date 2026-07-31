import { describe, expect, it } from 'vitest'
import { deriveTeacherQuestionExtraction } from './questionExtraction'

describe('deriveTeacherQuestionExtraction', () => {
  it('shows an incomplete choice extraction instead of pretending the cropped original is structured data', () => {
    const extraction = deriveTeacherQuestionExtraction({
      id: 'q-1', questionType: 'single_choice', questionNo: 1, status: 'pending_review',
      difficultyEstimated: null, customFields: {},
      blocks: [{ id: 'stem-1', blockType: 'stem', sortOrder: 0, sourceRegionId: 'source-1', content: { text: '1. 这表明 A. 分子间存在引力 B. 分子不停地运动' } }],
    }, [{
      id: 'source-1', sourceDocumentId: 'doc-1', sourceTitle: '2015广州中考', pageNumber: 1,
      x: 0, y: 0, width: 100, height: 20, coordinateUnit: 'percent',
      screenshotRelativePath: 'q1.png', screenshotUrl: '/q1.png', pageScreenshotUrl: '/page1.png', regionType: 'guangzhou_v2_question_candidate',
    }])

    expect(extraction.stem).toBe('1. 这表明')
    expect(extraction.options).toEqual([
      { label: 'A', text: '分子间存在引力' },
      { label: 'B', text: '分子不停地运动' },
    ])
    expect(extraction.textStatus).toBe('选择题文本不完整：目前只识别到 2/4 个选项。')
    expect(extraction.visualStatus).toContain('未单独提取')
  })

  it('reports multi-strip figures honestly instead of treating them as separately extracted images', () => {
    const extraction = deriveTeacherQuestionExtraction({
      id: 'q-18', questionType: 'fill_blank_or_drawing', questionNo: 18, status: 'pending_review',
      difficultyEstimated: null, customFields: {},
      blocks: [{ id: 'stem', blockType: 'stem', sortOrder: 0, sourceRegionId: 'source-1', content: { text: '18. 如图所示。' } }],
    }, [
      { id: 'source-1', sourceDocumentId: 'doc-1', sourceTitle: '2015广州中考', pageNumber: 5, x: 0, y: 0, width: 100, height: 20, coordinateUnit: 'percent', screenshotRelativePath: 'q18-a.png', screenshotUrl: '/q18-a.png', pageScreenshotUrl: '/page5.png', regionType: 'guangzhou_v2_question_candidate' },
      { id: 'source-2', sourceDocumentId: 'doc-1', sourceTitle: '2015广州中考', pageNumber: 5, x: 0, y: 20, width: 100, height: 20, coordinateUnit: 'percent', screenshotRelativePath: 'q18-b.png', screenshotUrl: '/q18-b.png', pageScreenshotUrl: '/page5.png', regionType: 'guangzhou_v2_question_candidate' },
    ])

    expect(extraction.stem).toBe('18. 如图所示。')
    expect(extraction.visualStatus).toBe('题图或表格：已随完整原题保留（2 段），尚未单独拆分。')
  })

  it('does not present four options inferred from legacy stem text as structured extraction', () => {
    const extraction = deriveTeacherQuestionExtraction({
      id: 'q-legacy', questionType: 'choice', questionNo: 1, status: 'pending_review',
      difficultyEstimated: null, customFields: {},
      blocks: [{
        id: 'stem-legacy', blockType: 'stem', sortOrder: 0, sourceRegionId: 'source-1',
        content: { text: '下列说法正确的是 A. 甲 B. 乙 C. 丙 D. 丁' },
      }],
    }, [])

    expect(extraction.options).toHaveLength(4)
    expect(extraction.textStatus).toBe('辅助文本中识别到 4 个选项，可能混有页眉或题图文字，需对照原题校对。')
    expect(extraction.requiresReview).toBe(true)
  })
})
