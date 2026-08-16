export const ADMIN_INTERNAL_KEY_HEADER = 'X-KQG-Admin-Key'

function startsWithSegment(path: string, segment: string) {
  return path === segment || path.startsWith(`${segment}/`)
}

export function requiresAdminProxyKey(requestUrl: string) {
  const path = requestUrl.split(/[?#]/, 1)[0].toLowerCase()
  return startsWithSegment(path, '/api/admin')
    || startsWithSegment(path, '/internal/ai')
    || (startsWithSegment(path, '/source-documents') && path.endsWith('/authorization'))
}
