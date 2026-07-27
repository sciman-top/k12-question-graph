import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  applyReviewWorkbenchAction,
  generateCutCandidates,
  getQuestion,
  getReviewQueueItems,
  getReadyHealth,
  reopenReviewQueueItem,
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
})
