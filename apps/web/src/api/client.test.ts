import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  applyReviewWorkbenchAction,
  confirmPaperBlueprintReview,
  createPaperBlueprintReview,
  exportCommentaryReport,
  generateCutCandidates,
  getQuestion,
  getReviewQueueItems,
  getReadyHealth,
  reopenReviewQueueItem,
  replacePaperQuestion,
  searchQuestions,
  previewItemScoreMappings,
  updateQuestion,
  updateSourceRegion,
  uploadImportFile,
} from './client'

const originalFetch = globalThis.fetch

afterEach(() => {
  vi.restoreAllMocks()
  globalThis.fetch = originalFetch
})

describe('api client error handling', () => {
  it('returns http_error for non-ok responses', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(
      new Response('{}', {
        status: 503,
        headers: { 'Content-Type': 'application/json' },
      }),
    ) as typeof fetch

    const result = await getReadyHealth()

    expect(result.ok).toBe(false)
    if (result.ok) {
      throw new Error('expected error result')
    }
    expect(result.error.code).toBe('http_error')
    expect(result.error.status).toBe(503)
  })

  it('returns invalid_response for malformed json payloads', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(
      new Response('{', {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    ) as typeof fetch

    const result = await getReadyHealth()

    expect(result.ok).toBe(false)
    if (result.ok) {
      throw new Error('expected error result')
    }
    expect(result.error.code).toBe('invalid_response')
    expect(result.error.status).toBe(200)
  })

  it('returns network_error when fetch rejects', async () => {
    globalThis.fetch = vi.fn().mockRejectedValue(new Error('socket closed')) as typeof fetch

    const result = await getReadyHealth()

    expect(result.ok).toBe(false)
    if (result.ok) {
      throw new Error('expected error result')
    }
    expect(result.error.code).toBe('network_error')
    expect(result.error.message).toContain('socket closed')
  })

  it('maps upload requests through the shared invalid_response guard', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(
      new Response('{', {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    ) as typeof fetch

    const result = await uploadImportFile(new File(['stub'], 'sample.docx'))

    expect(result.ok).toBe(false)
    if (result.ok) {
      throw new Error('expected error result')
    }
    expect(result.error.code).toBe('invalid_response')
  })

  it('maps generated cut candidate failures to http_error', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(
      new Response('{}', {
        status: 503,
        headers: { 'Content-Type': 'application/json' },
      }),
    ) as typeof fetch

    const result = await generateCutCandidates('doc-1')

    expect(result.ok).toBe(false)
    if (result.ok) {
      throw new Error('expected error result')
    }
    expect(result.error.code).toBe('http_error')
    expect(result.error.status).toBe(503)
  })

  it('maps review workbench post failures through shared network_error handling', async () => {
    globalThis.fetch = vi.fn().mockRejectedValue(new Error('connection reset')) as typeof fetch

    const result = await applyReviewWorkbenchAction({
      action: 'create_question',
      sourceDocumentId: 'doc-1',
      candidateIds: ['candidate-1'],
    })

    expect(result.ok).toBe(false)
    if (result.ok) {
      throw new Error('expected error result')
    }
    expect(result.error.code).toBe('network_error')
    expect(result.error.message).toContain('connection reset')
  })

  it('preserves v2 review actions and year when normalizing the real queue', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(
      Response.json({
        items: [{
          id: 'review-1',
          reviewType: 'guangzhou_v2_question_candidate_review',
          status: 'open',
          riskLevel: 'high',
          requiredAction: 'review_question_crop',
          requiredActions: ['review_question_crop', 'review_tags'],
          payload: {
            year: 2020,
            questionNo: 3,
            questionItemId: 'question-1',
            requiredActions: ['review_question_crop', 'review_tags'],
          },
        }],
        totalCount: 1,
      }),
    ) as typeof fetch

    const result = await getReviewQueueItems({ reviewType: 'guangzhou_v2_question_candidate_review' })

    expect(result.ok).toBe(true)
    if (!result.ok) {
      throw new Error('expected queue result')
    }
    expect(result.data.items[0].payload.year).toBe(2020)
    expect(result.data.items[0].requiredActions).toEqual(['review_question_crop', 'review_tags'])
  })

  it('uses the question, patch, recrop, and reopen workflow endpoints', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(Response.json({
        id: 'question-1',
        questionNo: 1,
        status: 'pending_review',
        difficultyEstimated: 0.4,
        blocks: [],
        assets: [],
        customFields: {},
      }))
      .mockResolvedValueOnce(Response.json({ question: { id: 'question-1', blocks: [], assets: [], customFields: {} }, auditId: 'audit-1' }))
      .mockResolvedValueOnce(Response.json({ region: { id: 'region-1' }, auditId: 'audit-2' }))
      .mockResolvedValueOnce(Response.json({ id: 'review-1', status: 'open', payload: {} }))
    globalThis.fetch = fetchMock as typeof fetch

    await getQuestion('question-1')
    await updateQuestion('question-1', { reviewedBy: 'reviewer', reason: 'revision', blocks: [] })
    await updateSourceRegion('region-1', { x: 1, reviewedBy: 'reviewer', reason: 'recrop' })
    await reopenReviewQueueItem('review-1', { reviewedBy: 'reviewer', reason: 'undo' })

    expect(fetchMock.mock.calls.map(([url, init]) => [url, init?.method ?? 'GET'])).toEqual([
      ['/questions/question-1', 'GET'],
      ['/questions/question-1', 'PATCH'],
      ['/source-regions/region-1', 'PATCH'],
      ['/review-queue/review-1/reopen', 'POST'],
    ])
  })

  it('preserves a zero question difficulty instead of treating it as missing', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(
      Response.json({
        id: 'question-zero-difficulty',
        questionNo: 1,
        status: 'pending_review',
        difficultyEstimated: 0,
        blocks: [],
        customFields: {},
      }),
    ) as typeof fetch

    const result = await getQuestion('question-zero-difficulty')

    expect(result.ok).toBe(true)
    if (!result.ok) {
      throw new Error('expected question result')
    }
    expect(result.data.difficultyEstimated).toBe(0)
  })

  it('sends real-question search filters before pagination', async () => {
    const fetchMock = vi.fn().mockResolvedValue(Response.json({
      mode: 'draft_test',
      productionEligible: false,
      total: 1,
      page: 2,
      limit: 10,
      knowledgeStatus: 'candidate_filters',
      knowledgeVersion: null,
      items: [],
    }))
    globalThis.fetch = fetchMock as typeof fetch

    await searchQuestions({
      page: 2,
      year: 2025,
      questionType: 'single_choice',
      status: 'pending_review',
      knowledgeCandidateId: 'KPHY-C003-059',
      examPointCandidateId: 'EPHY-C003-032',
      difficultyMin: 0.2,
      difficultyMax: 0.7,
      hasImage: true,
    })

    const requestUrl = String(fetchMock.mock.calls[0][0])
    expect(requestUrl).toContain('year=2025')
    expect(requestUrl).toContain('knowledgeCandidateId=KPHY-C003-059')
    expect(requestUrl).toContain('examPointCandidateId=EPHY-C003-032')
    expect(requestUrl).toContain('difficultyMin=0.2')
    expect(requestUrl).toContain('difficultyMax=0.7')
    expect(requestUrl).toContain('hasImage=true')
  })

  it('keeps candidate tags visible without treating them as primary knowledge', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(Response.json({
      mode: 'draft_test',
      productionEligible: false,
      total: 1,
      page: 1,
      limit: 10,
      knowledgeStatus: 'candidate_filters',
      knowledgeVersion: null,
      items: [{
        id: 'question-1',
        status: 'pending_review',
        primaryKnowledge: null,
        candidateTags: {
          primaryKnowledge: { id: 'KPHY-C003-025', label: '长度时间测量与估测' },
          primaryExamPoint: { id: 'EPHY-C003-001', label: '生活情境中的长度时间质量等估测' },
          abilityDimensions: ['信息提取', '科学推理'],
          reviewStatus: 'pending_review',
          productionEligible: false,
        },
        sources: {},
      }],
    })) as typeof fetch

    const result = await searchQuestions({ status: 'pending_review' })

    expect(result.ok).toBe(true)
    if (!result.ok) {
      throw new Error('expected question search result')
    }
    expect(result.data.items[0].primaryKnowledge).toBeNull()
    expect(result.data.items[0].candidateTags).toEqual({
      primaryKnowledge: { id: 'KPHY-C003-025', label: '长度时间测量与估测' },
      primaryExamPoint: { id: 'EPHY-C003-001', label: '生活情境中的长度时间质量等估测' },
      abilityDimensions: ['信息提取', '科学推理'],
      reviewStatus: 'pending_review',
      productionEligible: false,
    })
  })

  it('uses the blueprint, replacement, score mapping, and commentary endpoints', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(Response.json({ id: 'blueprint-1', blueprint: [] }))
      .mockResolvedValueOnce(Response.json({ id: 'blueprint-1', paperBasketId: 'basket-1' }))
      .mockResolvedValueOnce(Response.json({
        mode: 'draft_test',
        productionEligible: false,
        replacement: { id: 'replacement-1', difficultyEstimated: 0.55 },
        undo: { undoToken: 'undo-1', beforeQuestion: { id: 'q-1' }, afterQuestion: { id: 'replacement-1' } },
        constraints: {},
        auditTrail: [],
      }))
      .mockResolvedValueOnce(Response.json({ assessmentId: 'assessment-1', rows: [], issues: [] }))
      .mockResolvedValueOnce(Response.json({ assessmentId: 'assessment-1', sections: [], weakKnowledgePoints: [], practiceSuggestions: [], blockingIssues: [] }))
    globalThis.fetch = fetchMock as typeof fetch

    await createPaperBlueprintReview({ teacherRequest: '广州物理复习卷' })
    await confirmPaperBlueprintReview('blueprint-1', 'teacher')
    const replacement = await replacePaperQuestion({
      id: 'q-1',
      stemPreview: '原题',
      questionType: 'single_choice',
      score: 3,
      difficultyEstimated: 0.52,
      primaryKnowledgeId: 'K-1',
      primaryKnowledgeTitle: '惯性',
      sourceType: 'local_exam_paper',
      recentUseStatus: 'not_recently_used',
    })
    await previewItemScoreMappings({ assessmentId: 'assessment-1', mappings: [] })
    await exportCommentaryReport({ assessmentId: 'assessment-1', format: 'md', allowAiDraftText: false, mappings: [] })

    expect(replacement.ok && replacement.data.undo.undoToken).toBe('undo-1')
    expect(fetchMock.mock.calls.map(([url, init]) => [url, init?.method])).toEqual([
      ['/paper-blueprints', 'POST'],
      ['/paper-blueprints/blueprint-1/confirm', 'POST'],
      ['/paper-requests/replace-question', 'POST'],
      ['/assessments/assessment-1/item-score-mappings/preview', 'POST'],
      ['/assessments/assessment-1/commentary-report/export', 'POST'],
    ])
  })
})
