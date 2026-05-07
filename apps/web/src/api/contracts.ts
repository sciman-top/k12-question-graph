export const apiContractSnapshot = {
  version: 'i007.frontend-api-boundary.v1',
  openApiPath: '/openapi/v1.json',
  generatedClientCommand: 'dotnet run --project apps/api/K12QuestionGraph.Api.csproj then fetch /openapi/v1.json',
  boundary: 'UI consumes normalized typed contracts instead of raw JSON response shapes',
} as const

export type ApiResult<T> =
  | {
      ok: true
      data: T
    }
  | {
      ok: false
      error: {
        code: 'network_error' | 'invalid_response'
        message: string
      }
    }

export type ReadyHealthStatus = 'ok' | 'unknown'

export interface ReadyHealthContract {
  status: ReadyHealthStatus
  database: 'ok' | 'unknown'
  checkedAtIso: string
}

export interface SourceMaterialContract {
  sourceDocumentId: string
  fileAssetId: string
  sourceType: string
  sourceTitle: string
  region: string
  materialBatchKey: string
  createdAt: string
}

export interface SourceMaterialListContract {
  mode: string
  sourceType: string | null
  sourceDocuments: SourceMaterialContract[]
}

export interface SourcePreviewRegionContract {
  id: string
  sourceDocumentId: string
  pageNumber: number
  regionType: string
  screenshotRelativePath: string | null
}

export interface SourcePreviewPageContract {
  pageNumber: number
  regions: SourcePreviewRegionContract[]
}

export interface SourceDocumentPreviewContract {
  sourceDocumentId: string
  pages: SourcePreviewPageContract[]
}

export interface CutCandidateContract {
  id: string
  sourceDocumentId: string
  sourceRegionId: string | null
  status: string
  confidence: number
  segmentType: string
  sequenceNo: number
  failureReason: string
  takeoverAction: string
}

export interface CutCandidateListContract {
  sourceDocumentId: string
  items: CutCandidateContract[]
}

export interface CutCandidateGenerationContract {
  sourceDocumentId: string
  generatedCount: number
  lowConfidenceReviewQueueCount: number
  lowConfidenceThreshold: number
}

export interface ReviewWorkbenchActionContract {
  action: string
  sourceDocumentId: string
  touchedIds: string[]
  createdCandidateIds: string[]
  skippedIds: string[]
  createdQuestionId: string | null
}

export interface QuestionSourceRegionContract {
  id: string
  sourceDocumentId: string
  pageNumber: number
  regionType: string
  screenshotRelativePath: string | null
}

export interface QuestionSourceReviewContract {
  questionId: string
  sourceRegions: QuestionSourceRegionContract[]
}

export interface QuestionCardContract {
  id: string
  questionType: string
  difficultyEstimated: number | null
  status: string
  primaryKnowledge: {
    id: string
    title: string
    status: string
    version: number
  } | null
  preview: string
  blockCount: number
  assetCount: number
  sources: {
    titles: string[]
    types: string[]
  }
  hasFormula: boolean
  hasTable: boolean
  hasImage: boolean
}

export interface QuestionSearchContract {
  mode: string
  productionEligible: boolean
  total: number
  page: number
  limit: number
  knowledgeStatus: string
  knowledgeVersion: number | null
  items: QuestionCardContract[]
}

export interface PaperBlueprintRowContract {
  questionType: string
  count: number
  score: number
  scope: string[]
  assetStatus: string
  reviewStatus: string
}

export interface PaperBlueprintReviewContract {
  id: string
  status: string
  mode: string
  productionEligible: boolean
  allowRealModelCalls: boolean
  requestText: string
  subject: string
  grade: string
  textbookVersion: string | null
  scope: string[]
  totalScore: number
  difficultyTarget: string
  blueprint: PaperBlueprintRowContract[]
  reviewQuestions: string[]
  mustConfirmBeforeTakingQuestions: boolean
  opaqueGenerationAllowed: boolean
  confirmedPaperBasketId: string | null
}

export interface PaperBlueprintConfirmContract {
  id: string
  status: string
  confirmed: boolean
  paperBasketId: string | null
  selectedQuestionCount: number
  teacherMessage: string
  auditTrail: string[]
}

export interface ImportJobContract {
  id: string
  inputFileAssetId: string
  status: string
  idempotencyKey: string
  lastErrorCode: string | null
  lastErrorMessage: string | null
  createdAt: string
}

function readStringField(value: unknown, field: string): string | undefined {
  if (!value || typeof value !== 'object' || !(field in value)) {
    return undefined
  }

  const record = value as Record<string, unknown>
  return typeof record[field] === 'string' ? record[field] : undefined
}

export function normalizeReadyHealthResponse(value: unknown): ReadyHealthContract {
  const status = readStringField(value, 'status') === 'ok' ? 'ok' : 'unknown'
  const database = readStringField(value, 'database') === 'ok' ? 'ok' : 'unknown'

  return {
    status,
    database,
    checkedAtIso: new Date().toISOString(),
  }
}

function readArrayField(value: unknown, field: string): unknown[] {
  if (!value || typeof value !== 'object' || !(field in value)) {
    return []
  }

  const record = value as Record<string, unknown>
  return Array.isArray(record[field]) ? record[field] : []
}

function readNullableStringField(value: unknown, field: string): string | null {
  if (!value || typeof value !== 'object' || !(field in value)) {
    return null
  }

  const record = value as Record<string, unknown>
  return typeof record[field] === 'string' ? record[field] : null
}

function readNumberField(value: unknown, field: string): number {
  if (!value || typeof value !== 'object' || !(field in value)) {
    return 0
  }

  const record = value as Record<string, unknown>
  return typeof record[field] === 'number' ? record[field] : 0
}

function readBooleanField(value: unknown, field: string): boolean {
  if (!value || typeof value !== 'object' || !(field in value)) {
    return false
  }

  const record = value as Record<string, unknown>
  return record[field] === true
}

function normalizeBlueprintRows(value: unknown): PaperBlueprintRowContract[] {
  return readArrayField(value, 'blueprint').map((row) => ({
    questionType: readStringField(row, 'questionType') ?? 'unknown',
    count: readNumberField(row, 'count'),
    score: readNumberField(row, 'score'),
    scope: readArrayField(row, 'scope').map(String),
    assetStatus: readStringField(row, 'assetStatus') ?? 'unknown',
    reviewStatus: readStringField(row, 'reviewStatus') ?? 'unknown',
  }))
}

export function normalizeSourceMaterialListResponse(value: unknown): SourceMaterialListContract {
  const rows = readArrayField(value, 'sourceDocuments')
  return {
    mode: readStringField(value, 'mode') ?? 'unknown',
    sourceType: readNullableStringField(value, 'sourceType'),
    sourceDocuments: rows.map((row) => ({
      sourceDocumentId: readStringField(row, 'sourceDocumentId') ?? '',
      fileAssetId: readStringField(row, 'fileAssetId') ?? '',
      sourceType: readStringField(row, 'sourceType') ?? 'unknown',
      sourceTitle: readStringField(row, 'sourceTitle') ?? '',
      region: readStringField(row, 'region') ?? '',
      materialBatchKey: readStringField(row, 'materialBatchKey') ?? '',
      createdAt: readStringField(row, 'createdAt') ?? '',
    })),
  }
}

export function normalizeImportJobResponse(value: unknown): ImportJobContract {
  return {
    id: readStringField(value, 'id') ?? '',
    inputFileAssetId: readStringField(value, 'inputFileAssetId') ?? '',
    status: readStringField(value, 'status') ?? 'unknown',
    idempotencyKey: readStringField(value, 'idempotencyKey') ?? '',
    lastErrorCode: readNullableStringField(value, 'lastErrorCode'),
    lastErrorMessage: readNullableStringField(value, 'lastErrorMessage'),
    createdAt: readStringField(value, 'createdAt') ?? '',
  }
}

export function normalizeSourceDocumentPreviewResponse(value: unknown): SourceDocumentPreviewContract {
  const pages = readArrayField(value, 'pages')
  return {
    sourceDocumentId: readStringField(value, 'sourceDocumentId') ?? '',
    pages: pages.map((page) => ({
      pageNumber: readNumberField(page, 'pageNumber'),
      regions: readArrayField(page, 'regions').map((region) => ({
        id: readStringField(region, 'id') ?? '',
        sourceDocumentId: readStringField(region, 'sourceDocumentId') ?? '',
        pageNumber: readNumberField(region, 'pageNumber'),
        regionType: readStringField(region, 'regionType') ?? 'preview',
        screenshotRelativePath: readNullableStringField(region, 'screenshotRelativePath'),
      })),
    })),
  }
}

export function normalizeCutCandidateListResponse(value: unknown): CutCandidateListContract {
  const rows = readArrayField(value, 'items')
  return {
    sourceDocumentId: readStringField(value, 'sourceDocumentId') ?? '',
    items: rows.map((row) => ({
      id: readStringField(row, 'id') ?? '',
      sourceDocumentId: readStringField(row, 'sourceDocumentId') ?? '',
      sourceRegionId: readNullableStringField(row, 'sourceRegionId'),
      status: readStringField(row, 'status') ?? 'pending_review',
      confidence: readNumberField(row, 'confidence'),
      segmentType: readStringField(row, 'segmentType') ?? 'question_stem',
      sequenceNo: readNumberField(row, 'sequenceNo'),
      failureReason: readStringField(row, 'failureReason') ?? '',
      takeoverAction: readStringField(row, 'takeoverAction') ?? 'manual_review',
    })),
  }
}

export function normalizeCutCandidateGenerationResponse(
  value: unknown,
): CutCandidateGenerationContract {
  return {
    sourceDocumentId: readStringField(value, 'sourceDocumentId') ?? '',
    generatedCount: readNumberField(value, 'generatedCount'),
    lowConfidenceReviewQueueCount: readNumberField(value, 'lowConfidenceReviewQueueCount'),
    lowConfidenceThreshold: readNumberField(value, 'lowConfidenceThreshold'),
  }
}

export function normalizeReviewWorkbenchActionResponse(
  value: unknown,
): ReviewWorkbenchActionContract {
  return {
    action: readStringField(value, 'action') ?? '',
    sourceDocumentId: readStringField(value, 'sourceDocumentId') ?? '',
    touchedIds: readArrayField(value, 'touchedIds').map((x) => String(x)),
    createdCandidateIds: readArrayField(value, 'createdCandidateIds').map((x) => String(x)),
    skippedIds: readArrayField(value, 'skippedIds').map((x) => String(x)),
    createdQuestionId: readNullableStringField(value, 'createdQuestionId'),
  }
}

export function normalizeQuestionSourceReviewResponse(
  value: unknown,
): QuestionSourceReviewContract {
  const rows = readArrayField(value, 'sourceRegions')
  return {
    questionId: readStringField(value, 'questionId') ?? '',
    sourceRegions: rows.map((row) => ({
      id: readStringField(row, 'id') ?? '',
      sourceDocumentId: readStringField(row, 'sourceDocumentId') ?? '',
      pageNumber: readNumberField(row, 'pageNumber'),
      regionType: readStringField(row, 'regionType') ?? 'question',
      screenshotRelativePath: readNullableStringField(row, 'screenshotRelativePath'),
    })),
  }
}

export function normalizeQuestionSearchResponse(value: unknown): QuestionSearchContract {
  const rows = readArrayField(value, 'items')
  return {
    mode: readStringField(value, 'mode') ?? 'unknown',
    productionEligible: readBooleanField(value, 'productionEligible'),
    total: readNumberField(value, 'total'),
    page: readNumberField(value, 'page'),
    limit: readNumberField(value, 'limit'),
    knowledgeStatus: readStringField(value, 'knowledgeStatus') ?? 'unknown',
    knowledgeVersion:
      readNumberField(value, 'knowledgeVersion') === 0 ? null : readNumberField(value, 'knowledgeVersion'),
    items: rows.map((row) => {
      const primaryKnowledge = row && typeof row === 'object'
        ? (row as Record<string, unknown>).primaryKnowledge
        : null
      const sources = row && typeof row === 'object'
        ? (row as Record<string, unknown>).sources
        : null
      return {
        id: readStringField(row, 'id') ?? '',
        questionType: readStringField(row, 'questionType') ?? 'unknown',
        difficultyEstimated:
          readNumberField(row, 'difficultyEstimated') === 0
            ? null
            : readNumberField(row, 'difficultyEstimated'),
        status: readStringField(row, 'status') ?? 'unknown',
        primaryKnowledge:
          primaryKnowledge && typeof primaryKnowledge === 'object'
            ? {
                id: readStringField(primaryKnowledge, 'id') ?? '',
                title: readStringField(primaryKnowledge, 'title') ?? '',
                status: readStringField(primaryKnowledge, 'status') ?? '',
                version: readNumberField(primaryKnowledge, 'version'),
              }
            : null,
        preview: readStringField(row, 'preview') ?? '',
        blockCount: readNumberField(row, 'blockCount'),
        assetCount: readNumberField(row, 'assetCount'),
        sources: {
          titles: readArrayField(sources, 'titles').map((x) => String(x)),
          types: readArrayField(sources, 'types').map((x) => String(x)),
        },
        hasFormula: readBooleanField(row, 'hasFormula'),
        hasTable: readBooleanField(row, 'hasTable'),
        hasImage: readBooleanField(row, 'hasImage'),
      }
    }),
  }
}

export function normalizePaperBlueprintReviewResponse(value: unknown): PaperBlueprintReviewContract {
  return {
    id: readStringField(value, 'id') ?? '',
    status: readStringField(value, 'status') ?? 'unknown',
    mode: readStringField(value, 'mode') ?? 'unknown',
    productionEligible: readBooleanField(value, 'productionEligible'),
    allowRealModelCalls: readBooleanField(value, 'allowRealModelCalls'),
    requestText: readStringField(value, 'requestText') ?? '',
    subject: readStringField(value, 'subject') ?? 'physics',
    grade: readStringField(value, 'grade') ?? '',
    textbookVersion: readNullableStringField(value, 'textbookVersion'),
    scope: readArrayField(value, 'scope').map(String),
    totalScore: readNumberField(value, 'totalScore'),
    difficultyTarget: readStringField(value, 'difficultyTarget') ?? 'medium',
    blueprint: normalizeBlueprintRows(value),
    reviewQuestions: readArrayField(value, 'reviewQuestions').map(String),
    mustConfirmBeforeTakingQuestions: readBooleanField(value, 'mustConfirmBeforeTakingQuestions'),
    opaqueGenerationAllowed: readBooleanField(value, 'opaqueGenerationAllowed'),
    confirmedPaperBasketId: readNullableStringField(value, 'confirmedPaperBasketId'),
  }
}

export function normalizePaperBlueprintConfirmResponse(value: unknown): PaperBlueprintConfirmContract {
  return {
    id: readStringField(value, 'id') ?? '',
    status: readStringField(value, 'status') ?? 'unknown',
    confirmed: readBooleanField(value, 'confirmed'),
    paperBasketId: readNullableStringField(value, 'paperBasketId'),
    selectedQuestionCount: readNumberField(value, 'selectedQuestionCount'),
    teacherMessage: readStringField(value, 'teacherMessage') ?? '',
    auditTrail: readArrayField(value, 'auditTrail').map(String),
  }
}
