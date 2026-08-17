export const ADMIN_INTERNAL_KEY_HEADER = 'X-KQG-Admin-Key'
export const OPERATOR_ROLE_HEADER = 'X-KQG-Operator-Role'
export const OPERATOR_ID_HEADER = 'X-KQG-Operator-Id'

export function requiresAdminProxyKey(requestUrl: string) {
  const path = requestUrl.split(/[?#]/, 1)[0].toLowerCase()
  return path !== '/health' && path.startsWith('/')
}
