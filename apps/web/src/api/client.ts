import type {
  AdminAiProviderSettingsContract,
  AdminAiProviderSettingsSaveContract,
  AdminAiProviderSettingsTestContract,
  ApiResult,
  CommentaryReportExportContract,
  CurriculumEvidenceDecisionContract,
  CurriculumEvidenceReplacementOptionsContract,
  CurriculumEvidenceReviewListContract,
  CutCandidateGenerationContract,
  CutCandidateListContract,
  ImportJobContract,
  ItemScoreMappingPreviewContract,
  PaperBlueprintConfirmContract,
  PaperBlueprintReviewContract,
  PaperDraftQuestionContract,
  PaperQuestionReplacementContract,
  QuestionDetailContract,
  QuestionEvidenceSearchContract,
  QuestionEvidenceSearchParams,
  QuestionRevisionContract,
  QuestionSearchContract,
  QuestionSearchParams,
  QuestionSourceReviewContract,
  ReadyHealthContract,
  ReviewQueueItemContract,
  ReviewQueueListContract,
  ReviewWorkbenchActionContract,
  ScoreEvidenceAnalysisContract,
  ScoreImportContract,
  SourceDocumentPreviewContract,
  SourceMaterialListContract,
  SourceRegionRevisionContract,
} from './contracts'
import {
  normalizeAdminAiProviderSettingsResponse,
  normalizeAdminAiProviderSettingsSaveResponse,
  normalizeAdminAiProviderSettingsTestResponse,
  normalizeCommentaryReportExportResponse,
  normalizeCurriculumEvidenceDecisionResponse,
  normalizeCurriculumEvidenceReplacementOptionsResponse,
  normalizeCurriculumEvidenceReviewListResponse,
  normalizeCutCandidateGenerationResponse,
  normalizeCutCandidateListResponse,
  normalizeImportJobResponse,
  normalizeItemScoreMappingPreviewResponse,
  normalizePaperBlueprintConfirmResponse,
  normalizePaperBlueprintReviewResponse,
  normalizePaperQuestionReplacementResponse,
  normalizeQuestionDetailResponse,
  normalizeQuestionEvidenceSearchResponse,
  normalizeQuestionRevisionResponse,
  normalizeQuestionSearchResponse,
  normalizeQuestionSourceReviewResponse,
  normalizeReadyHealthResponse,
  normalizeReviewQueueItemResponse,
  normalizeReviewQueueListResponse,
  normalizeReviewWorkbenchActionResponse,
  normalizeScoreEvidenceAnalysisResponse,
  normalizeScoreImportResponse,
  normalizeSourceDocumentPreviewResponse,
  normalizeSourceMaterialListResponse,
  normalizeSourceRegionRevisionResponse,
} from './contracts'

const configuredApiBaseUrl = import.meta.env.VITE_KQG_API_BASE_URL ?? ''
const apiBaseUrl = import.meta.env.DEV ? '' : configuredApiBaseUrl

type JsonRequestInit = {
  method?: 'GET' | 'POST' | 'PATCH' | 'DELETE'
  headers?: HeadersInit
  body?: BodyInit | null
  includeJsonContentType?: boolean
  timeoutMs?: number
}

const defaultRequestTimeoutMs = 30_000
const longRunningRequestTimeoutMs = 120_000

export type AdminSessionContract = {
  authenticated: boolean
  operatorId: string | null
  role: string | null
  expiresAt: string | null
}

function buildApiUrl(path: string) {
  if (!apiBaseUrl) {
    return path
  }

  return `${apiBaseUrl.replace(/\/$/, '')}${path}`
}

function buildErrorResult(
  code: 'network_error' | 'http_error' | 'invalid_response',
  message: string,
  status?: number,
): ApiResult<never> {
  return {
    ok: false,
    error: {
      code,
      message,
      ...(typeof status === 'number' ? { status } : {}),
    },
  }
}

async function parseJsonResponse<T>(
  response: Response,
  normalize: (value: unknown) => T,
): Promise<ApiResult<T>> {
  try {
    const json: unknown = await response.json()
    return {
      ok: true,
      data: normalize(json),
    }
  } catch (error) {
    return buildErrorResult(
      'invalid_response',
      error instanceof Error ? error.message : 'Invalid JSON response',
      response.status,
    )
  }
}

async function requestResponse(
  path: string,
  init?: JsonRequestInit,
): Promise<ApiResult<Response>> {
  const includeJsonContentType = init?.includeJsonContentType ?? true
  const timeoutMs = Math.max(1, init?.timeoutMs ?? defaultRequestTimeoutMs)
  const abortController = new AbortController()
  const timeoutHandle = globalThis.setTimeout(() => abortController.abort(), timeoutMs)

  try {
    const response = await fetch(buildApiUrl(path), {
      method: init?.method,
      credentials: 'same-origin',
      headers: {
        Accept: 'application/json',
        ...(includeJsonContentType && init?.body ? { 'Content-Type': 'application/json' } : {}),
        ...(init?.headers ?? {}),
      },
      body: init?.body ?? null,
      signal: abortController.signal,
    })

    if (!response.ok) {
      return buildErrorResult('http_error', `HTTP ${response.status}`, response.status)
    }

    return {
      ok: true,
      data: response,
    }
  } catch (error) {
    return buildErrorResult(
      'network_error',
      abortController.signal.aborted
        ? `Request timed out after ${timeoutMs}ms`
        : error instanceof Error ? error.message : 'Unknown network error',
    )
  } finally {
    globalThis.clearTimeout(timeoutHandle)
  }
}

async function requestJson<T>(
  path: string,
  normalize: (value: unknown) => T,
  init?: JsonRequestInit,
): Promise<ApiResult<T>> {
  const response = await requestResponse(path, init)
  if (!response.ok) {
    return response
  }

  return parseJsonResponse(response.data, normalize)
}

async function postJson<T>(
  path: string,
  body: unknown,
  normalize: (value: unknown) => T,
): Promise<ApiResult<T>> {
  return requestJson(path, normalize, {
    method: 'POST',
    body: JSON.stringify(body),
  })
}

async function patchJson<T>(
  path: string,
  body: unknown,
  normalize: (value: unknown) => T,
): Promise<ApiResult<T>> {
  return requestJson(path, normalize, {
    method: 'PATCH',
    body: JSON.stringify(body),
  })
}

async function requestAdminJson<T>(path: string, normalize: (value: unknown) => T): Promise<ApiResult<T>> {
  return requestJson(path, normalize)
}

async function postAdminJson<T>(
  path: string,
  body: unknown,
  normalize: (value: unknown) => T,
  timeoutMs = defaultRequestTimeoutMs,
): Promise<ApiResult<T>> {
  return requestJson(path, normalize, {
    method: 'POST',
    body: JSON.stringify(body),
    timeoutMs,
  })
}

function normalizeAdminSession(value: unknown): AdminSessionContract {
  const record = value && typeof value === 'object' ? value as Record<string, unknown> : {}
  return {
    authenticated: record.authenticated === true,
    operatorId: typeof record.operatorId === 'string' ? record.operatorId : null,
    role: typeof record.role === 'string' ? record.role : null,
    expiresAt: typeof record.expiresAt === 'string' ? record.expiresAt : null,
  }
}

export async function getAdminSession(): Promise<ApiResult<AdminSessionContract>> {
  return requestJson('/auth/session', normalizeAdminSession)
}

export async function createAdminSession(apiKey: string): Promise<ApiResult<AdminSessionContract>> {
  return postJson('/auth/session', { apiKey }, normalizeAdminSession)
}

export async function deleteAdminSession(): Promise<ApiResult<null>> {
  const response = await requestResponse('/auth/session', { method: 'DELETE' })
  return response.ok ? { ok: true, data: null } : response
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
  fallbackBaseUrl?: string
  fallbackApiKey?: string
  fallbackImageBaseUrl?: string
  fallbackImageApiKey?: string
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
  imageBaseUrlOverride?: string
  fallbackBaseUrlOverride?: string
  fallbackImageBaseUrlOverride?: string
}): Promise<ApiResult<AdminAiProviderSettingsTestContract>> {
  return postAdminJson(
    '/api/admin/ai/provider-settings/test',
    request,
    normalizeAdminAiProviderSettingsTestResponse,
    longRunningRequestTimeoutMs,
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

  return requestJson('/imports', normalizeImportJobResponse, {
    method: 'POST',
    body: form,
    includeJsonContentType: false,
    timeoutMs: longRunningRequestTimeoutMs,
  })
}

export async function runDocumentWorkerSmoke(id: string): Promise<ApiResult<ImportJobContract>> {
  return postJson(`/imports/${encodeURIComponent(id)}/worker-smoke`, {}, normalizeImportJobResponse)
}

export async function createScoreImport(file: File): Promise<ApiResult<ScoreImportContract>> {
  const form = new FormData()
  form.append('file', file)
  form.append('containsStudentPii', 'false')
  return requestJson('/score-imports/xlsx', normalizeScoreImportResponse, {
    method: 'POST',
    body: form,
    includeJsonContentType: false,
    timeoutMs: longRunningRequestTimeoutMs,
  })
}

export async function downloadPaperArtifact(
  paperBasketId: string,
  format: 'docx' | 'pdf',
): Promise<ApiResult<{ blob: Blob; fileName: string }>> {
  const response = await requestResponse(
    `/paper-baskets/${encodeURIComponent(paperBasketId)}/export?format=${format}&variant=teacher`,
    { headers: { Accept: format === 'pdf' ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' } },
  )
  if (!response.ok) return response
  const disposition = response.data.headers.get('content-disposition') ?? ''
  const encoded = disposition.match(/filename\*=UTF-8''([^;]+)/i)?.[1]
  const fallback = disposition.match(/filename="?([^";]+)"?/i)?.[1]
  return {
    ok: true,
    data: {
      blob: await response.data.blob(),
      fileName: encoded ? decodeURIComponent(encoded) : fallback ?? `paper.${format}`,
    },
  }
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
  return requestJson(
    `/source-documents/${encodeURIComponent(id)}/cut-candidates/generate`,
    normalizeCutCandidateGenerationResponse,
    {
      method: 'POST',
    },
  )
}

export async function applyReviewWorkbenchAction(request: {
  action: string
  sourceDocumentId: string
  candidateIds: string[]
  assetLabel?: string
  reviewedBy?: string
  reason?: string
}): Promise<ApiResult<ReviewWorkbenchActionContract>> {
  return postJson('/review-workbench/actions', request, normalizeReviewWorkbenchActionResponse)
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

export async function reopenReviewQueueItem(
  id: string,
  request: { reviewedBy: string; reason: string },
): Promise<ApiResult<ReviewQueueItemContract>> {
  return postJson(
    `/review-queue/${encodeURIComponent(id)}/reopen`,
    request,
    normalizeReviewQueueItemResponse,
  )
}

export async function getCurriculumEvidenceReviews(params: {
  groupId?: string
  page?: number
  pageSize?: number
} = {}): Promise<ApiResult<CurriculumEvidenceReviewListContract>> {
  const query = new URLSearchParams()
  query.set('page', String(params.page ?? 1))
  query.set('pageSize', String(params.pageSize ?? 20))
  if (params.groupId) query.set('groupId', params.groupId)
  return requestJson(
    `/knowledge-evidence/reviews?${query.toString()}`,
    normalizeCurriculumEvidenceReviewListResponse,
  )
}

export async function decideCurriculumEvidence(request: {
  candidateType: string
  candidateId: string
  decision: 'approve' | 'return' | 'change_mapping' | 'keep_pending'
  reviewer: string
  reason: string
  actorRole?: 'teacher' | 'administrator'
  replacementAssetVersionId?: string
}): Promise<ApiResult<CurriculumEvidenceDecisionContract>> {
  return postJson(
    '/knowledge-evidence/reviews/decisions',
    request,
    normalizeCurriculumEvidenceDecisionResponse,
  )
}

export async function getCurriculumEvidenceReplacementOptions(
  candidateId: string,
): Promise<ApiResult<CurriculumEvidenceReplacementOptionsContract>> {
  return requestJson(
    `/knowledge-evidence/reviews/${encodeURIComponent(candidateId)}/replacement-options`,
    normalizeCurriculumEvidenceReplacementOptionsResponse,
  )
}

export async function undoCurriculumEvidenceDecision(
  decisionId: string,
  request: { reviewer: string; reason: string; actorRole?: 'teacher' | 'administrator' },
): Promise<ApiResult<CurriculumEvidenceDecisionContract>> {
  return postJson(
    `/knowledge-evidence/reviews/decisions/${encodeURIComponent(decisionId)}/undo`,
    request,
    normalizeCurriculumEvidenceDecisionResponse,
  )
}

export async function getQuestion(questionId: string): Promise<ApiResult<QuestionDetailContract>> {
  return requestJson(`/questions/${encodeURIComponent(questionId)}`, normalizeQuestionDetailResponse)
}

export async function updateQuestion(
  questionId: string,
  request: {
    reviewedBy: string
    reason: string
    difficultyEstimated?: number
    blocks?: Array<{
      id?: string
      blockType?: string
      sortOrder?: number
      content?: Record<string, unknown>
      sourceRegionId?: string | null
      clearSourceRegion?: boolean
    }>
    answer?: Record<string, unknown>
    solution?: Record<string, unknown>
    primaryKnowledgeLabel?: string
    knowledgeTags?: string[]
  },
): Promise<ApiResult<QuestionRevisionContract>> {
  const normalizedRequest = {
    ...request,
    blocks: request.blocks?.map((block) => block.sourceRegionId === null
      ? { ...block, sourceRegionId: undefined, clearSourceRegion: true }
      : block),
  }
  return patchJson(
    `/questions/${encodeURIComponent(questionId)}`,
    normalizedRequest,
    normalizeQuestionRevisionResponse,
  )
}

export async function updateSourceRegion(
  regionId: string,
  request: {
    pageNumber?: number
    x?: number
    y?: number
    width?: number
    height?: number
    coordinateUnit?: string
    screenshotRelativePath?: string | null
    clearScreenshot?: boolean
    regionType?: string
    reviewedBy: string
    reason: string
  },
): Promise<ApiResult<SourceRegionRevisionContract>> {
  const normalizedRequest = request.screenshotRelativePath === null
    ? { ...request, screenshotRelativePath: undefined, clearScreenshot: true }
    : request
  return patchJson(
    `/source-regions/${encodeURIComponent(regionId)}`,
    normalizedRequest,
    normalizeSourceRegionRevisionResponse,
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

export async function searchQuestions(params: QuestionSearchParams = {}): Promise<ApiResult<QuestionSearchContract>> {
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
  if (params.year !== undefined) {
    query.set('year', String(params.year))
  }
  if (params.knowledgeCandidateId) {
    query.set('knowledgeCandidateId', params.knowledgeCandidateId)
  }
  if (params.examPointCandidateId) {
    query.set('examPointCandidateId', params.examPointCandidateId)
  }
  if (params.difficultyMin !== undefined) {
    query.set('difficultyMin', String(params.difficultyMin))
  }
  if (params.difficultyMax !== undefined) {
    query.set('difficultyMax', String(params.difficultyMax))
  }
  if (params.hasImage !== undefined) {
    query.set('hasImage', String(params.hasImage))
  }

  return requestJson(`/questions?${query.toString()}`, normalizeQuestionSearchResponse)
}

export async function searchQuestionEvidence(
  params: QuestionEvidenceSearchParams = {},
): Promise<ApiResult<QuestionEvidenceSearchContract>> {
  const query = new URLSearchParams()
  if (params.evidenceMode !== undefined) query.set('evidenceMode', params.evidenceMode)
  if (params.previewMode !== undefined) query.set('previewMode', String(params.previewMode))

  const stringFilters: Array<[string, string | undefined]> = [
    ['requirementId', params.requirementId],
    ['facetId', params.facetId],
    ['ability', params.ability],
    ['cognitiveDemand', params.cognitiveDemand],
    ['methodOrExperiment', params.methodOrExperiment],
    ['context', params.context],
    ['representation', params.representation],
    ['profileId', params.profileId],
    ['sourceType', params.sourceType],
  ]
  for (const [name, value] of stringFilters) {
    if (value !== undefined && value.trim().length > 0) query.set(name, value.trim())
  }

  const numberFilters: Array<[string, number | undefined]> = [
    ['observedDifficultyMin', params.observedDifficultyMin],
    ['observedDifficultyMax', params.observedDifficultyMax],
    ['estimatedDifficultyMin', params.estimatedDifficultyMin],
    ['estimatedDifficultyMax', params.estimatedDifficultyMax],
    ['page', params.page],
    ['pageSize', params.pageSize],
  ]
  for (const [name, value] of numberFilters) {
    if (value !== undefined) query.set(name, String(value))
  }

  const suffix = query.toString()
  return requestJson(
    `/knowledge-evidence/questions${suffix ? `?${suffix}` : ''}`,
    normalizeQuestionEvidenceSearchResponse,
  )
}

export async function replacePaperQuestion(
  currentQuestion: PaperDraftQuestionContract,
): Promise<ApiResult<PaperQuestionReplacementContract>> {
  return postJson(
    '/paper-requests/replace-question',
    { currentQuestion },
    normalizePaperQuestionReplacementResponse,
  )
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

export async function previewScoreEvidenceAnalysis(request: {
  assessmentId: string
  containsStudentPii?: boolean
  mappings: Array<{ questionNo: string; questionItemId: string | null }>
}): Promise<ApiResult<ScoreEvidenceAnalysisContract>> {
  return postJson(
    `/assessments/${encodeURIComponent(request.assessmentId)}/score-evidence-analysis/preview`,
    {
      containsStudentPii: request.containsStudentPii ?? false,
      mappings: request.mappings,
    },
    normalizeScoreEvidenceAnalysisResponse,
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
