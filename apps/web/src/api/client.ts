import type {
  AdminAiProviderSettingsContract,
  AdminAiProviderSettingsSaveContract,
  AdminAiProviderSettingsTestContract,
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
  ReviewQueueItemContract,
  ReviewQueueListContract,
  ReviewWorkbenchActionContract,
  ScoreImportContract,
  SourceDocumentPreviewContract,
  SourceMaterialListContract,
} from './contracts'
import {
  normalizeAdminAiProviderSettingsResponse,
  normalizeAdminAiProviderSettingsSaveResponse,
  normalizeAdminAiProviderSettingsTestResponse,
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
  normalizeReviewQueueItemResponse,
  normalizeReviewQueueListResponse,
  normalizeReviewWorkbenchActionResponse,
  normalizeScoreImportResponse,
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

function adminHeaders() {
  return {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    'X-KQG-Operator-Role': 'admin',
    'X-KQG-Operator-Id': 'codex-admin',
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

async function requestAdminJson<T>(path: string, normalize: (value: unknown) => T): Promise<ApiResult<T>> {
  try {
    const response = await fetch(buildApiUrl(path), {
      headers: adminHeaders(),
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

async function postAdminJson<T>(
  path: string,
  body: unknown,
  normalize: (value: unknown) => T,
): Promise<ApiResult<T>> {
  try {
    const response = await fetch(buildApiUrl(path), {
      method: 'POST',
      headers: adminHeaders(),
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

export async function getAdminAiProviderSettings(): Promise<ApiResult<AdminAiProviderSettingsContract>> {
  return requestAdminJson('/api/admin/ai/provider-settings', normalizeAdminAiProviderSettingsResponse)
}

export async function saveAdminAiProviderSettings(request: {
  providerProfileId: string
  baseUrl: string
  apiKey: string
  imageBaseUrl?: string
  imageApiKey?: string
  maxConcurrency: number
  monthlyBudgetCny: number
  disabledByDefault: boolean
  allowRealModelCalls: boolean
  defaultSmokeTaskType: string
  defaultSmokeModel: string
  operatorNote?: string
}): Promise<ApiResult<AdminAiProviderSettingsSaveContract>> {
  return postAdminJson(
    '/api/admin/ai/provider-settings',
    request,
    normalizeAdminAiProviderSettingsSaveResponse,
  )
}

export async function testAdminAiProviderSettings(request: {
  taskType: string
  inputJson?: string
  model?: string
  baseUrlOverride?: string
}): Promise<ApiResult<AdminAiProviderSettingsTestContract>> {
  return postAdminJson(
    '/api/admin/ai/provider-settings/test',
    request,
    normalizeAdminAiProviderSettingsTestResponse,
  )
}

export async function getSourceMaterials(sourceType?: string): Promise<ApiResult<SourceMaterialListContract>> {
  const query = sourceType ? `?sourceType=${encodeURIComponent(sourceType)}` : ''
  return requestJson(`/source-documents${query}`, normalizeSourceMaterialListResponse)
}

export async function getImportJob(id: string): Promise<ApiResult<ImportJobContract>> {
  return requestJson(`/imports/${encodeURIComponent(id)}`, normalizeImportJobResponse)
}

export async function uploadImportFile(file: File): Promise<ApiResult<ImportJobContract>> {
  const form = new FormData()
  form.append('file', file)
  form.append('sourceType', 'local_exam_paper')
  form.append('sourceTitle', file.name)
  form.append('ownerScope', 'school')
  form.append('licenseOrPermission', 'pending_source_workbench_review')
  form.append('sharingAllowed', 'false')
  form.append('containsStudentPii', 'false')
  form.append('anonymizationStatus', 'not_applicable')
  form.append('materialBatchKey', 'teacher_upload')

  try {
    const response = await fetch(buildApiUrl('/imports'), {
      method: 'POST',
      headers: {
        Accept: 'application/json',
      },
      body: form,
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
      data: normalizeImportJobResponse(json),
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

export async function runDocumentWorkerSmoke(id: string): Promise<ApiResult<ImportJobContract>> {
  return postJson(`/imports/${encodeURIComponent(id)}/worker-smoke`, {}, normalizeImportJobResponse)
}

export async function createScoreImport(): Promise<ApiResult<ScoreImportContract>> {
  return postJson(
    '/score-imports',
    {
      assessmentKey: `sample-score-${Date.now()}`,
      assessmentTitle: '初二物理样例测验',
      subject: 'physics',
      stage: 'junior_middle_school',
      grade: '八年级',
      templateKey: 'sample-score-template-v1',
      templateDisplayName: '样例成绩模板',
      sourceFileName: 'sample-score.xlsx',
      containsStudentPii: false,
      productionEligible: false,
      maxTotalScore: 100,
      fieldMapping: {
        studentKey: 'student_code',
        totalScore: 'total_score',
        itemScores: {
          Q1: 'q1_score',
          Q2: 'q2_score',
        },
      },
      itemMaxScores: {
        Q1: 5,
        Q2: 5,
      },
      rows: [
        {
          rowNumber: 2,
          values: {
            student_code: 'S001',
            total_score: '8',
            q1_score: '4',
            q2_score: '4',
          },
        },
        {
          rowNumber: 3,
          values: {
            student_code: 'S002',
            total_score: '7',
            q1_score: '3',
            q2_score: '4',
          },
        },
        {
          rowNumber: 4,
          values: {
            student_code: 'S003',
            total_score: '12',
            q1_score: '5',
            q2_score: '7',
          },
        },
      ],
    },
    normalizeScoreImportResponse,
  )
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

export async function getReviewQueueItems(params: {
  status?: string
  reviewType?: string
  sortBy?: string
  order?: 'asc' | 'desc'
  limit?: number
} = {}): Promise<ApiResult<ReviewQueueListContract>> {
  const query = new URLSearchParams()
  query.set('status', params.status ?? 'open')
  query.set('limit', String(params.limit ?? 100))
  if (params.reviewType) {
    query.set('reviewType', params.reviewType)
  }
  if (params.sortBy) {
    query.set('sortBy', params.sortBy)
  }
  if (params.order) {
    query.set('order', params.order)
  }

  return requestJson(`/review-queue?${query.toString()}`, normalizeReviewQueueListResponse)
}

export async function resolveReviewQueueItem(
  id: string,
  request: {
    reviewedBy: string
    decision: 'resolved' | 'dismissed'
    reason: string
    revision?: {
      textPreview: string
      answer: string
      primaryKnowledgeLabel: string
      knowledgeTags: string[]
    }
  },
): Promise<ApiResult<ReviewQueueItemContract>> {
  return postJson(
    `/review-queue/${encodeURIComponent(id)}/resolve`,
    request,
    normalizeReviewQueueItemResponse,
  )
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
  status?: string
  sortBy?: string
  order?: 'asc' | 'desc'
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
  if (params.status) {
    query.set('status', params.status)
  }
  if (params.sortBy) {
    query.set('sortBy', params.sortBy)
  }
  if (params.order) {
    query.set('order', params.order)
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
