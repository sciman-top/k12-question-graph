import { describe, expect, it } from 'vitest'
import { readyHealthQueryPolicy, serverStateQueryKeys } from './queries'

describe('ready health query policy', () => {
  it('polls the local API so a service started after page load becomes reachable', () => {
    expect(serverStateQueryKeys.readyHealth).toEqual(['server-state', 'ready-health'])
    expect(readyHealthQueryPolicy).toMatchObject({
      retry: false,
      refetchInterval: 5_000,
      refetchIntervalInBackground: false,
    })
  })

  it('keeps evidence search state separate from the legacy question query', () => {
    const params = { evidenceMode: 'candidate' as const, previewMode: true, page: 1, pageSize: 20 }
    expect(serverStateQueryKeys.questionEvidenceSearch(params)).toEqual([
      'server-state',
      'question-evidence-search',
      params,
    ])
    expect(serverStateQueryKeys.questionEvidenceSearch(params)).not.toEqual(
      serverStateQueryKeys.questionSearch({ page: 1, limit: 20 }),
    )
  })
})
