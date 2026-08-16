import { describe, expect, it } from 'vitest'
import { ADMIN_INTERNAL_KEY_HEADER, requiresAdminProxyKey } from './adminProxyPolicy.ts'

describe('admin proxy policy', () => {
  it.each([
    ['/api/admin/ai/provider-settings', true],
    ['/internal/ai/model-route?mode=test', true],
    ['/source-documents/27f5ad82-0ee9-4920-b4b8-b844551f35c6/authorization', true],
    ['/source-documents/27f5ad82-0ee9-4920-b4b8-b844551f35c6/preview', false],
    ['/api/administrator', false],
    ['/questions', false],
  ])('classifies %s', (path, expected) => {
    expect(requiresAdminProxyKey(path)).toBe(expected)
  })

  it('uses the server guard header without exposing a value', () => {
    expect(ADMIN_INTERNAL_KEY_HEADER).toBe('X-KQG-Admin-Key')
  })
})
