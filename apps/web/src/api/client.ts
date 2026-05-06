import type {
  ApiResult,
  CutCandidateGenerationContract,
  CutCandidateListContract,
  ImportJobContract,
  ReadyHealthContract,
  SourceDocumentPreviewContract,
  SourceMaterialListContract,
} from './contracts'
import {
  normalizeCutCandidateGenerationResponse,
  normalizeCutCandidateListResponse,
  normalizeImportJobResponse,
  normalizeReadyHealthResponse,
  normalizeSourceDocumentPreviewResponse,
  normalizeSourceMaterialListResponse,
} from './contracts'

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

export async function getSourceMaterials(sourceType?: string): Promise<ApiResult<SourceMaterialListContract>> {
  const query = sourceType ? `?sourceType=${encodeURIComponent(sourceType)}` : ''
  return requestJson(`/source-documents${query}`, normalizeSourceMaterialListResponse)
}

export async function getImportJob(id: string): Promise<ApiResult<ImportJobContract>> {
  return requestJson(`/imports/${encodeURIComponent(id)}`, normalizeImportJobResponse)
}

export async function getSourceDocumentPreview(id: string): Promise<ApiResult<SourceDocumentPreviewContract>> {
  return requestJson(
    `/source-documents/${encodeURIComponent(id)}/preview`,
    normalizeSourceDocumentPreviewResponse,
  )
}

export async function getCutCandidates(id: string): Promise<ApiResult<CutCandidateListContract>> {
  return requestJson(
    `/source-documents/${encodeURIComponent(id)}/cut-candidates`,
    normalizeCutCandidateListResponse,
  )
}

export async function generateCutCandidates(
  id: string,
): Promise<ApiResult<CutCandidateGenerationContract>> {
  try {
    const response = await fetch(
      buildApiUrl(`/source-documents/${encodeURIComponent(id)}/cut-candidates/generate`),
      {
        method: 'POST',
        headers: {
          Accept: 'application/json',
        },
      },
    )
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
      data: normalizeCutCandidateGenerationResponse(json),
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
