import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  applyReviewWorkbenchAction,
  generateCutCandidates,
  getReadyHealth,
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
})
