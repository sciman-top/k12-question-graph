import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  applyReviewWorkbenchAction,
  confirmPaperBlueprintReview,
  createPaperBlueprintReview,
  decideCurriculumEvidence,
  exportCommentaryReport,
  generateCutCandidates,
  getCurriculumEvidenceReviews,
  getCurriculumEvidenceReplacementOptions,
  getQuestion,
  getReviewQueueItems,
  getReadyHealth,
  reopenReviewQueueItem,
  replacePaperQuestion,
  searchQuestionEvidence,
  searchQuestions,
  previewItemScoreMappings,
  previewScoreEvidenceAnalysis,
  updateQuestion,
  updateSourceRegion,
  undoCurriculumEvidenceDecision,
  uploadImportFile,
} from './client'
import {
  normalizeCurriculumEvidenceReviewListResponse,
  normalizeQuestionEvidenceSearchResponse,
} from './contracts'

const originalFetch = globalThis.fetch

afterEach(() => {
  vi.useRealTimers()
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

  it('aborts a request that exceeds the shared timeout', async () => {
    vi.useFakeTimers()
    globalThis.fetch = vi.fn((_input, init) => new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')))
    })) as typeof fetch

    const resultPromise = getReadyHealth()
    await vi.advanceTimersByTimeAsync(30_000)
    const result = await resultPromise

    expect(result.ok).toBe(false)
    if (result.ok) {
      throw new Error('expected error result')
    }
    expect(result.error.code).toBe('network_error')
    expect(result.error.message).toBe('Request timed out after 30000ms')
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
      .mockResolvedValueOnce(Response.json({
        status: 'blocked',
        assessmentId: 'assessment-1',
        scoreDerivedPerformance: [],
        knowledgeMastery: [],
        abilityPerformance: [],
        cognitivePerformance: [],
        observedContexts: [],
        errorPatternAssociations: [],
        teachingRecommendations: [],
        teacherConfirmedDiagnoses: [],
        blockingIssues: [{ scope: 'Q1', codes: ['assessment_target_not_reviewed'] }],
      }))
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
    const analysis = await previewScoreEvidenceAnalysis({ assessmentId: 'assessment-1', mappings: [] })
    await exportCommentaryReport({ assessmentId: 'assessment-1', format: 'md', allowAiDraftText: false, mappings: [] })

    expect(replacement.ok && replacement.data.undo.undoToken).toBe('undo-1')
    expect(analysis.ok && analysis.data.productionEligible).toBe(false)
    expect(analysis.ok && analysis.data.blockingIssues[0]?.codes).toContain('assessment_target_not_reviewed')
    expect(fetchMock.mock.calls.map(([url, init]) => [url, init?.method])).toEqual([
      ['/paper-blueprints', 'POST'],
      ['/paper-blueprints/blueprint-1/confirm', 'POST'],
      ['/paper-requests/replace-question', 'POST'],
      ['/assessments/assessment-1/item-score-mappings/preview', 'POST'],
      ['/assessments/assessment-1/score-evidence-analysis/preview', 'POST'],
      ['/assessments/assessment-1/commentary-report/export', 'POST'],
    ])
  })
})

describe('question evidence search client', () => {
  it('serializes every typed filter, preserves zero values, and omits blank strings', async () => {
    const fetchMock = vi.fn().mockResolvedValue(Response.json({ items: [] }))
    globalThis.fetch = fetchMock as typeof fetch

    await searchQuestionEvidence({
      evidenceMode: 'candidate',
      previewMode: true,
      requirementId: 'CR-1',
      facetId: 'FACET-1',
      ability: '科学推理',
      cognitiveDemand: 'analyze',
      methodOrExperiment: 'EXP-1',
      context: 'experimental',
      representation: 'diagram',
      profileId: 'PROFILE-1',
      observedDifficultyMin: 0,
      observedDifficultyMax: 1,
      estimatedDifficultyMin: 0,
      estimatedDifficultyMax: 0.8,
      sourceType: 'local_exam_paper',
      page: 2,
      pageSize: 25,
    })

    const url = new URL(String(fetchMock.mock.calls[0][0]), 'http://localhost')
    expect(url.pathname).toBe('/knowledge-evidence/questions')
    expect(Object.fromEntries(url.searchParams)).toEqual({
      evidenceMode: 'candidate',
      previewMode: 'true',
      requirementId: 'CR-1',
      facetId: 'FACET-1',
      ability: '科学推理',
      cognitiveDemand: 'analyze',
      methodOrExperiment: 'EXP-1',
      context: 'experimental',
      representation: 'diagram',
      profileId: 'PROFILE-1',
      sourceType: 'local_exam_paper',
      observedDifficultyMin: '0',
      observedDifficultyMax: '1',
      estimatedDifficultyMin: '0',
      estimatedDifficultyMax: '0.8',
      page: '2',
      pageSize: '25',
    })

    await searchQuestionEvidence({ requirementId: ' ', facetId: '', previewMode: false })
    const blankUrl = new URL(String(fetchMock.mock.calls[1][0]), 'http://localhost')
    expect(blankUrl.searchParams.has('requirementId')).toBe(false)
    expect(blankUrl.searchParams.has('facetId')).toBe(false)
    expect(blankUrl.searchParams.get('previewMode')).toBe('false')
  })

  it('normalizes evidence cards without merging curriculum, profile, or difficulty semantics', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue(Response.json({
      evidenceMode: 'candidate',
      previewMode: true,
      productionEligible: false,
      total: 1,
      page: 1,
      pageSize: 20,
      sort: 'question_no_asc',
      completionBoundary: 'preview only',
      items: [{
        questionId: 'question-1',
        questionNo: 3,
        subject: 'physics',
        stage: 'junior_middle_school',
        grade: '9',
        questionType: 'experiment',
        status: 'pending_review',
        estimatedDifficulty: 0,
        estimatedDifficultySource: 'question_estimated',
        productionEligible: false,
        assessmentTargets: [{
          id: 'target-1',
          stableKey: 'AT-1',
          scopeType: 'question',
          targetStatement: '分析实验数据',
          isPrimaryTarget: true,
          confidence: 0.91,
          status: 'candidate',
          reviewStatus: 'pending_review',
          productionEligible: false,
          abilityDimensions: ['科学推理'],
          cognitiveDemands: ['analyze'],
          methodOrExperimentIds: ['EXP-1'],
          contextType: 'experimental',
          representationTypes: ['diagram'],
          knowledge: [{
            stableId: 'K-1', displayName: '密度测量', role: 'primary', confidence: 0.9,
            status: 'candidate', reviewStatus: 'pending_review',
          }],
          requirements: [{
            stableId: 'CR-1', displayName: '会测量密度', alignmentType: 'retrospective_crosswalk',
            originalBasis: false, provenance: 'retrospective_crosswalk', sourceDocumentId: 'doc-1',
            sourceRegionId: 'region-1', confidence: 0.88,
            curriculumSourceDocumentId: 'curriculum-doc-1', curriculumSourceRegionId: null,
            curriculumSourcePageNumber: 31,
          }],
          observedDifficulty: [{
            value: 0.64, direction: 'higher_is_easier', sampleScope: 'guangzhou_2024',
            sourceRegionId: 'report-region-1', status: 'candidate', reviewStatus: 'pending_review',
          }],
          profiles: [{
            stableId: 'PROFILE-1', displayName: '广州密度考查画像', status: 'candidate',
            trendStatus: 'insufficient_evidence',
          }],
        }],
      }],
    })) as typeof fetch

    const result = await searchQuestionEvidence({ evidenceMode: 'candidate', previewMode: true })

    expect(result.ok).toBe(true)
    if (!result.ok) throw new Error('expected evidence search result')
    expect(result.data).toMatchObject({
      evidenceMode: 'candidate',
      previewMode: true,
      productionEligible: false,
      total: 1,
    })
    expect(result.data.items[0].estimatedDifficulty).toBe(0)
    expect(result.data.items[0].estimatedDifficultySource).toBe('question_estimated')
    expect(result.data.items[0].assessmentTargets[0]).toMatchObject({
      reviewStatus: 'pending_review',
      knowledge: [{ role: 'primary', displayName: '密度测量' }],
      requirements: [{
        provenance: 'retrospective_crosswalk',
        originalBasis: false,
        curriculumSourceDocumentId: 'curriculum-doc-1',
        curriculumSourcePageNumber: 31,
      }],
      observedDifficulty: [{ value: 0.64, direction: 'higher_is_easier' }],
      profiles: [{ stableId: 'PROFILE-1', trendStatus: 'insufficient_evidence' }],
    })
  })

  it('normalizes legacy or partial payloads to safe non-production defaults', () => {
    const normalized = normalizeQuestionEvidenceSearchResponse({
      productionEligible: 'true',
      items: [{ questionId: 'legacy-1', estimatedDifficulty: 0, assessmentTargets: [{}] }],
    })

    expect(normalized).toMatchObject({
      evidenceMode: 'unknown',
      previewMode: false,
      productionEligible: false,
      total: 0,
      page: 0,
      pageSize: 0,
      sort: 'unknown',
      completionBoundary: '',
    })
    expect(normalized.items[0]).toMatchObject({
      questionId: 'legacy-1',
      estimatedDifficulty: 0,
      estimatedDifficultySource: 'unknown',
      productionEligible: false,
    })
    expect(normalized.items[0].assessmentTargets[0]).toMatchObject({
      reviewStatus: 'pending_review',
      productionEligible: false,
      knowledge: [],
      requirements: [],
      observedDifficulty: [],
      profiles: [],
    })
  })
})

describe('curriculum evidence review client', () => {
  it('serializes the review group and pagination query', async () => {
    const fetchMock = vi.fn().mockResolvedValue(Response.json({ items: [], totalCount: 0 }))
    globalThis.fetch = fetchMock as typeof fetch

    await getCurriculumEvidenceReviews({ groupId: 'complex_mappings', page: 3, pageSize: 12 })

    expect(fetchMock).toHaveBeenCalledWith(
      '/knowledge-evidence/reviews?page=3&pageSize=12&groupId=complex_mappings',
      expect.objectContaining({ body: null }),
    )
  })

  it('posts the complete teacher decision audit payload', async () => {
    const fetchMock = vi.fn().mockResolvedValue(Response.json({ decisionId: 'decision-1' }))
    globalThis.fetch = fetchMock as typeof fetch

    await decideCurriculumEvidence({
      candidateType: 'alignment',
      candidateId: 'alignment-1',
      decision: 'return',
      reviewer: 'teacher-ui-local',
      reason: '来源不足，退回补证。',
      actorRole: 'teacher',
    })

    expect(fetchMock).toHaveBeenCalledWith(
      '/knowledge-evidence/reviews/decisions',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({
          candidateType: 'alignment',
          candidateId: 'alignment-1',
          decision: 'return',
          reviewer: 'teacher-ui-local',
          reason: '来源不足，退回补证。',
          actorRole: 'teacher',
        }),
      }),
    )
  })

  it('encodes the undo decision id and posts its reason', async () => {
    const fetchMock = vi.fn().mockResolvedValue(Response.json({ decisionId: 'decision-1' }))
    globalThis.fetch = fetchMock as typeof fetch

    await undoCurriculumEvidenceDecision('decision/with space', {
      reviewer: 'teacher-ui-local',
      reason: '撤销上一条决定。',
      actorRole: 'teacher',
    })

    expect(fetchMock).toHaveBeenCalledWith(
      '/knowledge-evidence/reviews/decisions/decision%2Fwith%20space/undo',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({
          reviewer: 'teacher-ui-local',
          reason: '撤销上一条决定。',
          actorRole: 'teacher',
        }),
      }),
    )
  })

  it('loads fail-closed replacement choices without exposing an active apply route', async () => {
    const fetchMock = vi.fn().mockResolvedValue(Response.json({
      items: [{ assetVersionId: 'asset-2', stableKey: 'KPHY-002', displayName: '惯性与牛顿第一定律' }],
      productionEligible: false,
    }))
    globalThis.fetch = fetchMock as typeof fetch

    const result = await getCurriculumEvidenceReplacementOptions('alignment/with space')

    expect(fetchMock).toHaveBeenCalledWith(
      '/knowledge-evidence/reviews/alignment%2Fwith%20space/replacement-options',
      expect.objectContaining({ body: null }),
    )
    expect(result.ok && result.data).toMatchObject({
      items: [{ assetVersionId: 'asset-2', stableKey: 'KPHY-002', displayName: '惯性与牛顿第一定律' }],
      productionEligible: false,
    })
  })

  it('normalizes missing and legacy review fields to fail-closed defaults', () => {
    const normalized = normalizeCurriculumEvidenceReviewListResponse({
      items: [{ candidateId: 'legacy-1', confidence: '0.8', productionEligible: 'true' }],
    })

    expect(normalized.items[0]).toMatchObject({
      candidateType: 'unknown',
      candidateId: 'legacy-1',
      reviewStatus: 'pending_review',
      confidence: 0,
      impactLevel: 'unknown',
      originalBasis: false,
      productionEligible: false,
      reversible: false,
      batchApprovalEligible: false,
      summary: {},
      evidence: {},
    })
    expect(normalized).toMatchObject({
      page: 0,
      totalCount: 0,
      productionEligible: false,
      completionBoundary: '',
    })
  })
})
