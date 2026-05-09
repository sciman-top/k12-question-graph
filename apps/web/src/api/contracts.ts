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
  pageNumber: number
  textPreview: string
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
  sourceDocumentId: string | null
  status: string
  idempotencyKey: string
  lastErrorCode: string | null
  lastErrorMessage: string | null
  createdAt: string
}

export interface ItemScoreMappingPreviewRowContract {
  questionNo: string
  fieldNames: string[]
  scoreRecordCount: number
  maxScore: number
  averageScoreRate: number
  questionItemId: string | null
  questionPreview: string | null
  primaryKnowledge: {
    knowledgeNodeId: string
    title: string
    status: string
    version: number
  } | null
  status: string
  issueCodes: string[]
}

export interface ItemScoreMappingPreviewContract {
  mode: string
  productionEligible: boolean
  realStudentDataUsed: boolean
  writesProductionHistory: boolean
  assessmentId: string
  assessmentTitle: string
  itemCount: number
  mappedCount: number
  unclearCount: number
  rows: ItemScoreMappingPreviewRowContract[]
  issues: Array<{ questionNo: string; codes: string[] }>
  teacherMessage: string
  auditTrail: string[]
}

export interface CommentaryReportExportContract {
  status: string
  mode: string
  productionEligible: boolean
  realStudentDataUsed: boolean
  writesProductionHistory: boolean
  allowAiDraftText: boolean
  assessmentId: string
  assessmentTitle: string
  format: string
  artifactPath: string | null
  manifestSha256: string | null
  reportMarkdown: string
  sections: Array<{ sectionId: string; title: string; summary: string }>
  weakKnowledgePoints: Array<{ title: string; version: number; scoreRate: number; questionNo: string }>
  practiceSuggestions: Array<{ knowledgeTitle: string; suggestion: string }>
  blockingIssues: Array<{ questionNo: string; codes: string[] }>
  teacherMessage: string
  auditTrail: string[]
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

function readObjectField(value: unknown, field: string): Record<string, unknown> | null {
  if (!value || typeof value !== 'object' || !(field in value)) {
    return null
  }

  const record = value as Record<string, unknown>
  return record[field] && typeof record[field] === 'object'
    ? (record[field] as Record<string, unknown>)
    : null
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
  const file = readObjectField(value, 'file')
  const sourceDocument = file ? readObjectField(file, 'sourceDocument') : null

  return {
    id: readStringField(value, 'id') ?? '',
    inputFileAssetId: readStringField(value, 'inputFileAssetId') ?? '',
    sourceDocumentId: sourceDocument ? readStringField(sourceDocument, 'id') ?? null : null,
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
    items: rows.map((row) => {
      const candidatePayload = readObjectField(row, 'candidatePayload')
      return {
        id: readStringField(row, 'id') ?? '',
        sourceDocumentId: readStringField(row, 'sourceDocumentId') ?? '',
        sourceRegionId: readNullableStringField(row, 'sourceRegionId'),
        status: readStringField(row, 'status') ?? 'pending_review',
        confidence: readNumberField(row, 'confidence'),
        segmentType: readStringField(row, 'segmentType') ?? 'question_stem',
        sequenceNo: readNumberField(row, 'sequenceNo'),
        pageNumber: candidatePayload ? readNumberField(candidatePayload, 'pageNumber') : 0,
        textPreview: candidatePayload ? readStringField(candidatePayload, 'textPreview') ?? '' : '',
        failureReason: readStringField(row, 'failureReason') ?? '',
        takeoverAction: readStringField(row, 'takeoverAction') ?? 'manual_review',
      }
    }),
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

export function normalizeItemScoreMappingPreviewResponse(
  value: unknown,
): ItemScoreMappingPreviewContract {
  const rows = readArrayField(value, 'rows')
  const issues = readArrayField(value, 'issues')
  return {
    mode: readStringField(value, 'mode') ?? 'unknown',
    productionEligible: readBooleanField(value, 'productionEligible'),
    realStudentDataUsed: readBooleanField(value, 'realStudentDataUsed'),
    writesProductionHistory: readBooleanField(value, 'writesProductionHistory'),
    assessmentId: readStringField(value, 'assessmentId') ?? '',
    assessmentTitle: readStringField(value, 'assessmentTitle') ?? '',
    itemCount: readNumberField(value, 'itemCount'),
    mappedCount: readNumberField(value, 'mappedCount'),
    unclearCount: readNumberField(value, 'unclearCount'),
    rows: rows.map((row) => {
      const primaryKnowledge = row && typeof row === 'object'
        ? (row as Record<string, unknown>).primaryKnowledge
        : null
      return {
        questionNo: readStringField(row, 'questionNo') ?? '',
        fieldNames: readArrayField(row, 'fieldNames').map(String),
        scoreRecordCount: readNumberField(row, 'scoreRecordCount'),
        maxScore: readNumberField(row, 'maxScore'),
        averageScoreRate: readNumberField(row, 'averageScoreRate'),
        questionItemId: readNullableStringField(row, 'questionItemId'),
        questionPreview: readNullableStringField(row, 'questionPreview'),
        primaryKnowledge:
          primaryKnowledge && typeof primaryKnowledge === 'object'
            ? {
                knowledgeNodeId: readStringField(primaryKnowledge, 'knowledgeNodeId') ?? '',
                title: readStringField(primaryKnowledge, 'title') ?? '',
                status: readStringField(primaryKnowledge, 'status') ?? 'unknown',
                version: readNumberField(primaryKnowledge, 'version'),
              }
            : null,
        status: readStringField(row, 'status') ?? 'needs_review',
        issueCodes: readArrayField(row, 'issueCodes').map(String),
      }
    }),
    issues: issues.map((issue) => ({
      questionNo: readStringField(issue, 'questionNo') ?? '',
      codes: readArrayField(issue, 'codes').map(String),
    })),
    teacherMessage: readStringField(value, 'teacherMessage') ?? '',
    auditTrail: readArrayField(value, 'auditTrail').map(String),
  }
}

export function normalizeCommentaryReportExportResponse(
  value: unknown,
): CommentaryReportExportContract {
  return {
    status: readStringField(value, 'status') ?? 'unknown',
    mode: readStringField(value, 'mode') ?? 'unknown',
    productionEligible: readBooleanField(value, 'productionEligible'),
    realStudentDataUsed: readBooleanField(value, 'realStudentDataUsed'),
    writesProductionHistory: readBooleanField(value, 'writesProductionHistory'),
    allowAiDraftText: readBooleanField(value, 'allowAiDraftText'),
    assessmentId: readStringField(value, 'assessmentId') ?? '',
    assessmentTitle: readStringField(value, 'assessmentTitle') ?? '',
    format: readStringField(value, 'format') ?? 'md',
    artifactPath: readNullableStringField(value, 'artifactPath'),
    manifestSha256: readNullableStringField(value, 'manifestSha256'),
    reportMarkdown: readStringField(value, 'reportMarkdown') ?? '',
    sections: readArrayField(value, 'sections').map((section) => ({
      sectionId: readStringField(section, 'sectionId') ?? '',
      title: readStringField(section, 'title') ?? '',
      summary: readStringField(section, 'summary') ?? '',
    })),
    weakKnowledgePoints: readArrayField(value, 'weakKnowledgePoints').map((point) => ({
      title: readStringField(point, 'title') ?? '',
      version: readNumberField(point, 'version'),
      scoreRate: readNumberField(point, 'scoreRate'),
      questionNo: readStringField(point, 'questionNo') ?? '',
    })),
    practiceSuggestions: readArrayField(value, 'practiceSuggestions').map((suggestion) => ({
      knowledgeTitle: readStringField(suggestion, 'knowledgeTitle') ?? '',
      suggestion: readStringField(suggestion, 'suggestion') ?? '',
    })),
    blockingIssues: readArrayField(value, 'blockingIssues').map((issue) => ({
      questionNo: readStringField(issue, 'questionNo') ?? '',
      codes: readArrayField(issue, 'codes').map(String),
    })),
    teacherMessage: readStringField(value, 'teacherMessage') ?? '',
    auditTrail: readArrayField(value, 'auditTrail').map(String),
  }
}
