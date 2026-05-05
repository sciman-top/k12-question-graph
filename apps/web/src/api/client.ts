import type { ApiResult, ReadyHealthContract } from './contracts'
import { normalizeReadyHealthResponse } from './contracts'

const apiBaseUrl = import.meta.env.VITE_KQG_API_BASE_URL ?? ''

function buildApiUrl(path: string) {
  if (!apiBaseUrl) {
    return path
  }

  return `${apiBaseUrl.replace(/\/$/, '')}${path}`
}

async function requestJson<T>(path: string, normalize: (value: unknown) => T): Promise<ApiResult<T>> {
  try {
    const response = await fetch(buildApiUrl(path), {
      headers: {
        Accept: 'application/json',
      },
    })

    if (!response.ok) {
      return {
        ok: false,
        error: {
          code: 'network_error',
          message: `HTTP ${response.status}`,
        },
      }
    }

    const json: unknown = await response.json()
    return {
      ok: true,
      data: normalize(json),
    }
  } catch (error) {
    return {
      ok: false,
      error: {
        code: 'network_error',
        message: error instanceof Error ? error.message : 'Unknown network error',
      },
    }
  }
}

export async function getReadyHealth(): Promise<ApiResult<ReadyHealthContract>> {
  return requestJson('/health/ready', normalizeReadyHealthResponse)
}
