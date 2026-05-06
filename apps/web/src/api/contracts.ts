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
