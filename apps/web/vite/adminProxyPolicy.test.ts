import { describe, expect, it } from 'vitest'
import {
  ADMIN_INTERNAL_KEY_HEADER,
  OPERATOR_ID_HEADER,
  OPERATOR_ROLE_HEADER,
} from './adminProxyPolicy.ts'

describe('admin proxy policy', () => {
  it('defines only the headers that the proxy strips from browser requests', () => {
    expect(ADMIN_INTERNAL_KEY_HEADER).toBe('X-KQG-Admin-Key')
    expect(OPERATOR_ROLE_HEADER).toBe('X-KQG-Operator-Role')
    expect(OPERATOR_ID_HEADER).toBe('X-KQG-Operator-Id')
  })
})
