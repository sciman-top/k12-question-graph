import type {
  ApiResult,
  CommentaryReportExportContract,
  CutCandidateGenerationContract,
  CutCandidateListContract,
  ImportJobContract,
  ItemScoreMappingPreviewContract,
  PaperBlueprintConfirmContract,
  PaperBlueprintReviewContract,
  QuestionSearchContract,
  QuestionSourceReviewContract,
  ReadyHealthContract,
  ReviewWorkbenchActionContract,
  SourceDocumentPreviewContract,
  SourceMaterialListContract,
} from './contracts'
import {
  normalizeCommentaryReportExportResponse,
  normalizeCutCandidateGenerationResponse,
  normalizeCutCandidateListResponse,
  normalizeImportJobResponse,
  normalizeItemScoreMappingPreviewResponse,
  normalizePaperBlueprintConfirmResponse,
  normalizePaperBlueprintReviewResponse,
  normalizeQuestionSearchResponse,
  normalizeQuestionSourceReviewResponse,
  normalizeReadyHealthResponse,
  normalizeReviewWorkbenchActionResponse,
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

async function postJson<T>(
  path: string,
  body: unknown,
  normalize: (value: unknown) => T,
): Promise<ApiResult<T>> {
  try {
    const response = await fetch(buildApiUrl(path), {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
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

export async function applyReviewWorkbenchAction(request: {
  action: string
  sourceDocumentId: string
  candidateIds: string[]
  assetLabel?: string
  reviewedBy?: string
  reason?: string
}): Promise<ApiResult<ReviewWorkbenchActionContract>> {
  try {
    const response = await fetch(buildApiUrl('/review-workbench/actions'), {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(request),
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
      data: normalizeReviewWorkbenchActionResponse(json),
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

export async function getQuestionSources(
  questionId: string,
): Promise<ApiResult<QuestionSourceReviewContract>> {
  return requestJson(
    `/questions/${encodeURIComponent(questionId)}/sources`,
    normalizeQuestionSourceReviewResponse,
  )
}

export async function searchQuestions(params: {
  page?: number
  limit?: number
  questionType?: string
  sourceType?: string
} = {}): Promise<ApiResult<QuestionSearchContract>> {
  const query = new URLSearchParams()
  query.set('subject', 'physics')
  query.set('stage', 'junior_middle_school')
  query.set('page', String(params.page ?? 1))
  query.set('limit', String(params.limit ?? 10))
  if (params.questionType) {
    query.set('questionType', params.questionType)
  }
  if (params.sourceType) {
    query.set('sourceType', params.sourceType)
  }

  return requestJson(`/questions?${query.toString()}`, normalizeQuestionSearchResponse)
}

export async function createPaperBlueprintReview(request: {
  teacherRequest: string
  textbookVersion?: string
}): Promise<ApiResult<PaperBlueprintReviewContract>> {
  return postJson('/paper-blueprints', request, normalizePaperBlueprintReviewResponse)
}

export async function confirmPaperBlueprintReview(
  id: string,
  teacherConfirmedBy: string,
): Promise<ApiResult<PaperBlueprintConfirmContract>> {
  return postJson(
    `/paper-blueprints/${encodeURIComponent(id)}/confirm`,
    { teacherConfirmedBy },
    normalizePaperBlueprintConfirmResponse,
  )
}

export async function previewItemScoreMappings(request: {
  assessmentId: string
  mappings: Array<{ questionNo: string; questionItemId: string | null }>
}): Promise<ApiResult<ItemScoreMappingPreviewContract>> {
  return postJson(
    `/assessments/${encodeURIComponent(request.assessmentId)}/item-score-mappings/preview`,
    { mappings: request.mappings },
    normalizeItemScoreMappingPreviewResponse,
  )
}

export async function exportCommentaryReport(request: {
  assessmentId: string
  format: string
  allowAiDraftText: boolean
  mappings: Array<{ questionNo: string; questionItemId: string | null }>
}): Promise<ApiResult<CommentaryReportExportContract>> {
  return postJson(
    `/assessments/${encodeURIComponent(request.assessmentId)}/commentary-report/export`,
    {
      format: request.format,
      allowAiDraftText: request.allowAiDraftText,
      mappings: request.mappings,
    },
    normalizeCommentaryReportExportResponse,
  )
}
