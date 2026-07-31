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
        code: 'network_error' | 'http_error' | 'invalid_response'
        message: string
        status?: number
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
  screenshotUrl: string | null
  pageScreenshotUrl: string | null
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

export interface ReviewQueuePayloadContract {
  sourceWorkflowKey: string
  materialBatchKey: string
  year: number
  questionNo: number
  sourceDocumentId: string
  sourceTitle: string
  answerSourceDocumentId: string
  sourceRegionId: string
  answerRegionId: string
  candidateId: string
  questionItemId: string
  confidence: number
  requiredAction: string
  requiredActions: string[]
  reason: string
  riskLevel: string
  textPreview: string
  answer: string
  primaryKnowledgeLabel: string
  knowledgeTags: string[]
  reviewAudit: {
    reviewedBy: string
    decision: string
    reason: string
    reviewedAt: string
    revision: {
      textPreview: string
      answer: string
      primaryKnowledgeLabel: string
      knowledgeTags: string[]
    } | null
  } | null
}

export interface ReviewQueueItemContract {
  id: string
  reviewType: string
  status: string
  riskLevel: string
  requiredAction: string
  requiredActions: string[]
  confidence: number | null
  reason: string | null
  payload: ReviewQueuePayloadContract
  createdAt: string
  resolvedAt: string | null
}

export interface ReviewQueueListContract {
  items: ReviewQueueItemContract[]
  totalCount: number
}

export interface CurriculumEvidenceReviewItemContract {
  candidateType: 'requirement' | 'target' | 'alignment' | 'error_pattern' | 'profile' | 'unknown'
  candidateId: string
  stableKey: string
  groupId: string
  reviewStatus: string
  confidence: number
  impactLevel: 'high' | 'medium' | 'low' | 'unknown'
  mappingType: string | null
  alignmentType: string | null
  originalBasis: boolean
  productionEligible: boolean
  reversible: boolean
  batchApprovalEligible: boolean
  summary: Record<string, unknown>
  evidence: Record<string, unknown>
}

export interface CurriculumEvidenceReviewListContract {
  items: CurriculumEvidenceReviewItemContract[]
  page: number
  pageSize: number
  totalCount: number
  totalPages: number
  sort: string
  productionEligible: boolean
  completionBoundary: string
}

export interface CurriculumEvidenceReplacementOptionContract {
  assetVersionId: string
  stableKey: string
  displayName: string
}

export interface CurriculumEvidenceReplacementOptionsContract {
  items: CurriculumEvidenceReplacementOptionContract[]
  productionEligible: boolean
  completionBoundary: string
}

export interface CurriculumEvidenceDecisionContract {
  decisionId: string
  candidateType: string
  candidateId: string
  decision: string
  reviewStatus: string
  productionEligible: boolean
  activeApply: boolean
  audit: Record<string, unknown>
}

export interface QuestionSourceRegionContract {
  id: string
  sourceDocumentId: string
  sourceTitle: string | null
  pageNumber: number
  x: number
  y: number
  width: number
  height: number
  coordinateUnit: string
  regionType: string
  screenshotRelativePath: string | null
  screenshotUrl: string | null
  pageScreenshotUrl: string | null
}

export interface QuestionBlockContract {
  id: string
  blockType: string
  sortOrder: number
  content: Record<string, unknown>
  sourceRegionId: string | null
}

export interface QuestionDetailContract {
  id: string
  questionType: string | null
  questionNo: number
  status: string
  difficultyEstimated: number | null
  blocks: QuestionBlockContract[]
  customFields: Record<string, unknown>
}

export interface QuestionRevisionContract {
  question: QuestionDetailContract
  auditId: string
}

export interface SourceRegionRevisionContract {
  region: QuestionSourceRegionContract
  auditId: string
}

export interface QuestionSourceReviewContract {
  questionId: string
  sourceRegions: QuestionSourceRegionContract[]
}

export interface QuestionCardContract {
  id: string
  questionType: string
  defaultScore: number | null
  difficultyEstimated: number | null
  status: string
  questionNo: number | null
  primaryKnowledge: {
    id: string
    title: string
    status: string
    version: number
  } | null
  candidateTags: {
    primaryKnowledge: { id: string; label: string } | null
    primaryExamPoint: { id: string; label: string } | null
    abilityDimensions: string[]
    reviewStatus: string
    productionEligible: boolean
  } | null
  preview: string
  blockCount: number
  assetCount: number
  sources: {
    titles: string[]
    types: string[]
    permissions: string[]
    sharingAllowed: boolean
    containsStudentPii: boolean
    anonymizationStatuses: string[]
    regionCount: number
    screenshotCount: number
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

export interface QuestionSearchParams {
  page?: number
  limit?: number
  questionType?: string
  sourceType?: string
  status?: string
  sortBy?: string
  order?: 'asc' | 'desc'
  year?: number
  knowledgeCandidateId?: string
  examPointCandidateId?: string
  difficultyMin?: number
  difficultyMax?: number
  hasImage?: boolean
}

export type QuestionEvidenceMode = 'active' | 'reviewed' | 'candidate'

export interface QuestionEvidenceSearchParams {
  evidenceMode?: QuestionEvidenceMode
  previewMode?: boolean
  requirementId?: string
  facetId?: string
  ability?: string
  cognitiveDemand?: string
  methodOrExperiment?: string
  context?: string
  representation?: string
  profileId?: string
  observedDifficultyMin?: number
  observedDifficultyMax?: number
  estimatedDifficultyMin?: number
  estimatedDifficultyMax?: number
  sourceType?: string
  page?: number
  pageSize?: number
}

export interface QuestionEvidenceKnowledgeContract {
  stableId: string
  displayName: string
  role: string
  confidence: number
  status: string
  reviewStatus: string
}

export interface QuestionEvidenceRequirementContract {
  stableId: string
  displayName: string
  alignmentType: string
  originalBasis: boolean
  provenance: string
  sourceDocumentId: string
  sourceRegionId: string | null
  confidence: number
  curriculumSourceDocumentId: string | null
  curriculumSourceRegionId: string | null
  curriculumSourcePageNumber: number | null
}

export interface QuestionObservedDifficultyContract {
  value: number
  direction: string
  sampleScope: string
  sourceRegionId: string
  status: string
  reviewStatus: string
}

export interface QuestionEvidenceProfileContract {
  stableId: string
  displayName: string
  status: string
  trendStatus: string | null
}

export interface QuestionAssessmentTargetEvidenceContract {
  id: string
  stableKey: string
  scopeType: string
  targetStatement: string
  isPrimaryTarget: boolean
  confidence: number
  status: string
  reviewStatus: string
  productionEligible: boolean
  abilityDimensions: string[]
  cognitiveDemands: string[]
  methodOrExperimentIds: string[]
  contextType: string | null
  representationTypes: string[]
  knowledge: QuestionEvidenceKnowledgeContract[]
  requirements: QuestionEvidenceRequirementContract[]
  observedDifficulty: QuestionObservedDifficultyContract[]
  profiles: QuestionEvidenceProfileContract[]
}

export interface QuestionEvidenceCardContract {
  questionId: string
  questionNo: number | null
  subject: string
  stage: string
  grade: string | null
  questionType: string | null
  status: string
  estimatedDifficulty: number | null
  estimatedDifficultySource: string
  assessmentTargets: QuestionAssessmentTargetEvidenceContract[]
  productionEligible: boolean
}

export interface QuestionEvidenceSearchContract {
  evidenceMode: QuestionEvidenceMode | 'unknown'
  previewMode: boolean
  productionEligible: boolean
  total: number
  page: number
  pageSize: number
  items: QuestionEvidenceCardContract[]
  sort: string
  completionBoundary: string
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

export interface PaperDraftQuestionContract {
  id: string
  stemPreview: string
  questionType: string
  score: number
  difficultyEstimated: number | null
  primaryKnowledgeId: string
  primaryKnowledgeTitle: string
  sourceType: string
  recentUseStatus: string
}

export interface PaperQuestionReplacementContract {
  mode: string
  productionEligible: boolean
  allowRealModelCalls: boolean
  action: string
  reason: string
  constraints: {
    sameKnowledge: boolean
    sameQuestionType: boolean
    similarDifficulty: boolean
    sameScore: boolean
    excludeCurrentPaperDuplicates: boolean
    excludeRecentlyUsed: boolean
    knowledgeStatus: string
    blocksProductionPaper: boolean
  }
  replacement: PaperDraftQuestionContract
  undo: {
    undoToken: string
    beforeQuestion: PaperDraftQuestionContract
    afterQuestion: PaperDraftQuestionContract
    revertAction: string
  }
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

export interface ScoreImportContract {
  status: string
  mode: string
  productionEligible: boolean
  realStudentDataUsed: boolean
  containsStudentPii: boolean
  assessmentId: string | null
  templateId: string | null
  batchId: string | null
  rowCount: number
  importedCount: number
  errorCount: number
  errors: Array<{
    rowNumber: number
    code: string
    message: string
    fields: string[]
  }>
  teacherMessage: string
  auditTrail: string[]
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

export interface ScoreEvidenceAnalysisContract {
  status: string
  mode: string
  productionEligible: boolean
  realStudentDataUsed: boolean
  writesProductionHistory: boolean
  assessmentId: string
  assessmentTitle: string
  scoreDerivedPerformance: Array<{
    questionNo: string
    assessmentTargetStableKey: string
    targetStatement: string
    scoreRecordCount: number
    averageScoreRate: number
    abilityDimensions: string[]
    cognitiveDemands: string[]
    evidenceRole: string
  }>
  knowledgeMastery: ScoreEvidenceDimensionContract[]
  abilityPerformance: ScoreEvidenceDimensionContract[]
  cognitivePerformance: ScoreEvidenceDimensionContract[]
  observedContexts: Array<{
    evidenceId: string
    difficultyObserved: number | null
    scoreRate: number | null
    sampleScope: string
    sourceRegionId: string
    contextRole: string
  }>
  errorPatternAssociations: Array<{
    evidenceId: string
    kind: string
    content: string
    sourceRegionId: string | null
    relation: string
    diagnosisStatus: string
  }>
  teachingRecommendations: Array<{
    recommendationId: string
    content: string
    authorKind: string
    generationMethod: string
    sourceRegionId: string
    factRole: string
  }>
  teacherConfirmedDiagnoses: Array<{
    assessmentTargetId: string
    diagnosis: string
    confirmedBy: string
    confirmedAt: string
  }>
  diagnosisStatus: string
  blockingIssues: Array<{ scope: string; codes: string[] }>
  teacherMessage: string
  auditTrail: string[]
}

export interface ScoreEvidenceDimensionContract {
  stableId: string
  displayName: string
  scoreRate: number
  scoreRecordCount: number
  questionNos: string[]
  version: number | null
  evidenceRole: string
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

export interface AdminAiProviderSettingsContract {
  status: string
  mode: string
  productionEligible: boolean
  providerProfileId: string
  providerType: string
  baseUrl: string
  imageBaseUrl: string
  credentialMode: string
  maskedSecret: string
  secretConfigured: boolean
  maskedImageSecret: string
  imageSecretConfigured: boolean
  imageUsesPrimarySecret: boolean
  maxConcurrency: number
  monthlyBudgetCny: number
  disabledByDefault: boolean
  allowRealModelCalls: boolean
  defaultSmokeTaskType: string
  defaultSmokeModel: string
  fallbackBaseUrl: string
  fallbackImageBaseUrl: string
  maskedFallbackSecret: string
  fallbackSecretConfigured: boolean
  maskedFallbackImageSecret: string
  fallbackImageSecretConfigured: boolean
  fallbackImageUsesPrimarySecret: boolean
  endpoints: AdminAiProviderEndpointContract[]
  lastUpdatedAt: string
  teacherMessage: string
  auditTrail: string[]
}

export interface AdminAiProviderEndpointContract {
  endpointId: string
  label: string
  isFallback: boolean
  baseUrl: string
  imageBaseUrl: string
  maskedSecret: string
  secretConfigured: boolean
  maskedImageSecret: string
  imageSecretConfigured: boolean
  imageUsesTextSecret: boolean
}

export interface AdminAiProviderSettingsSaveContract {
  status: string
  mode: string
  productionEligible: boolean
  providerProfileId: string
  secretConfigured: boolean
  maskedSecret: string
  imageSecretConfigured: boolean
  maskedImageSecret: string
  imageUsesPrimarySecret: boolean
  fallbackSecretConfigured: boolean
  maskedFallbackSecret: string
  fallbackImageSecretConfigured: boolean
  maskedFallbackImageSecret: string
  fallbackImageUsesPrimarySecret: boolean
  lastUpdatedAt: string
  teacherMessage: string
  auditTrail: string[]
}

export interface AdminAiProviderProbeAttemptContract {
  providerEndpointId: string
  baseUrl: string
  routeKind: string
  endpointPath: string
  model: string
  passed: boolean
  httpStatusCode: number
  latencyMs: number
  message: string
}

export interface AdminAiProviderImageProbeAttemptContract {
  providerEndpointId: string
  baseUrl: string
  routeKind: string
  endpointPath: string
  model: string
  passed: boolean
  httpStatusCode: number
  latencyMs: number
  message: string
}

export interface AdminAiProviderImageProbeResultContract {
  attempted: boolean
  passed: boolean
  effectiveProviderEndpointId: string
  effectiveBaseUrl: string
  effectiveRouteKind: string
  effectiveModel: string
  httpStatusCode: number
  latencyMs: number
  message: string
  blockers: string[]
  attempts: AdminAiProviderImageProbeAttemptContract[]
  auditTrail: string[]
}

export interface AdminAiProviderSettingsTestContract {
  status: string
  mode: string
  productionEligible: boolean
  providerProfileId: string
  providerType: string
  model: string
  taskType: string
  reviewStatus: string
  passed: boolean
  combinedPassed: boolean
  effectiveProviderEndpointId: string
  effectiveBaseUrl: string
  httpStatusCode: number
  message: string
  outputJson: string
  inputTokens: number
  outputTokens: number
  cachedTokens: number
  cost: number
  latencyMs: number
  blockers: string[]
  attempts: AdminAiProviderProbeAttemptContract[]
  imageProbe: AdminAiProviderImageProbeResultContract
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

function readNullableNumberField(value: unknown, field: string): number | null {
  if (!value || typeof value !== 'object' || !(field in value)) {
    return null
  }

  const record = value as Record<string, unknown>
  return typeof record[field] === 'number' ? record[field] : null
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

export function normalizeScoreImportResponse(value: unknown): ScoreImportContract {
  return {
    status: readStringField(value, 'status') ?? 'unknown',
    mode: readStringField(value, 'mode') ?? 'unknown',
    productionEligible: readBooleanField(value, 'productionEligible'),
    realStudentDataUsed: readBooleanField(value, 'realStudentDataUsed'),
    containsStudentPii: readBooleanField(value, 'containsStudentPii'),
    assessmentId: readNullableStringField(value, 'assessmentId'),
    templateId: readNullableStringField(value, 'templateId'),
    batchId: readNullableStringField(value, 'batchId'),
    rowCount: readNumberField(value, 'rowCount'),
    importedCount: readNumberField(value, 'importedCount'),
    errorCount: readNumberField(value, 'errorCount'),
    errors: readArrayField(value, 'errors').map((error) => ({
      rowNumber: readNumberField(error, 'rowNumber'),
      code: readStringField(error, 'code') ?? '',
      message: readStringField(error, 'message') ?? '',
      fields: readArrayField(error, 'fields').map(String),
    })),
    teacherMessage: readStringField(value, 'teacherMessage') ?? '',
    auditTrail: readArrayField(value, 'auditTrail').map(String),
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
        screenshotUrl: readNullableStringField(region, 'screenshotUrl'),
        pageScreenshotUrl: readNullableStringField(region, 'pageScreenshotUrl'),
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

function normalizeReviewQueuePayload(value: unknown): ReviewQueuePayloadContract {
  return {
    sourceWorkflowKey: readStringField(value, 'sourceWorkflowKey') ?? '',
    materialBatchKey: readStringField(value, 'materialBatchKey') ?? '',
    year: readNumberField(value, 'year'),
    questionNo: readNumberField(value, 'questionNo'),
    sourceDocumentId: readStringField(value, 'sourceDocumentId') ?? '',
    sourceTitle: readStringField(value, 'sourceTitle') ?? '',
    answerSourceDocumentId: readStringField(value, 'answerSourceDocumentId') ?? '',
    sourceRegionId: readStringField(value, 'sourceRegionId') ?? '',
    answerRegionId: readStringField(value, 'answerRegionId') ?? '',
    candidateId: readStringField(value, 'candidateId') ?? '',
    questionItemId: readStringField(value, 'questionItemId') ?? '',
    confidence: readNumberField(value, 'confidence'),
    requiredAction: readStringField(value, 'requiredAction') ?? 'manual_review',
    requiredActions: readArrayField(value, 'requiredActions').map((action) => String(action)),
    reason: readStringField(value, 'reason') ?? '',
    riskLevel: readStringField(value, 'riskLevel') ?? 'medium',
    textPreview: readStringField(value, 'textPreview') ?? '',
    answer: readStringField(value, 'answer') ?? '',
    primaryKnowledgeLabel: readStringField(value, 'primaryKnowledgeLabel') ?? '',
    knowledgeTags: readArrayField(value, 'knowledgeTags').map((tag) => String(tag)),
    reviewAudit: normalizeReviewAudit(readObjectField(value, 'reviewAudit')),
  }
}

function normalizeReviewAudit(value: Record<string, unknown> | null): ReviewQueuePayloadContract['reviewAudit'] {
  if (!value) {
    return null
  }

  const revision = readObjectField(value, 'revision')
  return {
    reviewedBy: readStringField(value, 'reviewedBy') ?? '',
    decision: readStringField(value, 'decision') ?? '',
    reason: readStringField(value, 'reason') ?? '',
    reviewedAt: readStringField(value, 'reviewedAt') ?? '',
    revision: revision
      ? {
          textPreview: readStringField(revision, 'textPreview') ?? '',
          answer: readStringField(revision, 'answer') ?? '',
          primaryKnowledgeLabel: readStringField(revision, 'primaryKnowledgeLabel') ?? '',
          knowledgeTags: readArrayField(revision, 'knowledgeTags').map((tag) => String(tag)),
        }
      : null,
  }
}

export function normalizeReviewQueueItemResponse(value: unknown): ReviewQueueItemContract {
  const payload = readObjectField(value, 'payload') ?? {}
  const confidence = readNumberField(value, 'confidence')
  return {
    id: readStringField(value, 'id') ?? '',
    reviewType: readStringField(value, 'reviewType') ?? '',
    status: readStringField(value, 'status') ?? 'open',
    riskLevel: readStringField(value, 'riskLevel') ?? 'medium',
    requiredAction: readStringField(value, 'requiredAction') ?? 'manual_review',
    requiredActions: readArrayField(value, 'requiredActions').map((action) => String(action)),
    confidence: confidence === 0 ? null : confidence,
    reason: readNullableStringField(value, 'reason'),
    payload: normalizeReviewQueuePayload(payload),
    createdAt: readStringField(value, 'createdAt') ?? '',
    resolvedAt: readNullableStringField(value, 'resolvedAt'),
  }
}

export function normalizeReviewQueueListResponse(value: unknown): ReviewQueueListContract {
  return {
    items: readArrayField(value, 'items').map(normalizeReviewQueueItemResponse),
    totalCount: readNumberField(value, 'totalCount'),
  }
}

export function normalizeCurriculumEvidenceReviewListResponse(
  value: unknown,
): CurriculumEvidenceReviewListContract {
  return {
    items: readArrayField(value, 'items').map((item) => ({
      candidateType: (readStringField(item, 'candidateType') ?? 'unknown') as CurriculumEvidenceReviewItemContract['candidateType'],
      candidateId: readStringField(item, 'candidateId') ?? '',
      stableKey: readStringField(item, 'stableKey') ?? '',
      groupId: readStringField(item, 'groupId') ?? '',
      reviewStatus: readStringField(item, 'reviewStatus') ?? 'pending_review',
      confidence: readNumberField(item, 'confidence'),
      impactLevel: (readStringField(item, 'impactLevel') ?? 'unknown') as CurriculumEvidenceReviewItemContract['impactLevel'],
      mappingType: readNullableStringField(item, 'mappingType'),
      alignmentType: readNullableStringField(item, 'alignmentType'),
      originalBasis: readBooleanField(item, 'originalBasis'),
      productionEligible: readBooleanField(item, 'productionEligible'),
      reversible: readBooleanField(item, 'reversible'),
      batchApprovalEligible: readBooleanField(item, 'batchApprovalEligible'),
      summary: readObjectField(item, 'summary') ?? {},
      evidence: readObjectField(item, 'evidence') ?? {},
    })),
    page: readNumberField(value, 'page'),
    pageSize: readNumberField(value, 'pageSize'),
    totalCount: readNumberField(value, 'totalCount'),
    totalPages: readNumberField(value, 'totalPages'),
    sort: readStringField(value, 'sort') ?? '',
    productionEligible: readBooleanField(value, 'productionEligible'),
    completionBoundary: readStringField(value, 'completionBoundary') ?? '',
  }
}

export function normalizeCurriculumEvidenceDecisionResponse(
  value: unknown,
): CurriculumEvidenceDecisionContract {
  return {
    decisionId: readStringField(value, 'decisionId') ?? '',
    candidateType: readStringField(value, 'candidateType') ?? 'unknown',
    candidateId: readStringField(value, 'candidateId') ?? '',
    decision: readStringField(value, 'decision') ?? '',
    reviewStatus: readStringField(value, 'reviewStatus') ?? 'pending_review',
    productionEligible: readBooleanField(value, 'productionEligible'),
    activeApply: readBooleanField(value, 'activeApply'),
    audit: readObjectField(value, 'audit') ?? {},
  }
}

export function normalizeCurriculumEvidenceReplacementOptionsResponse(
  value: unknown,
): CurriculumEvidenceReplacementOptionsContract {
  return {
    items: readArrayField(value, 'items').map((item) => ({
      assetVersionId: readStringField(item, 'assetVersionId') ?? '',
      stableKey: readStringField(item, 'stableKey') ?? '',
      displayName: readStringField(item, 'displayName') ?? '',
    })).filter((item) => item.assetVersionId && item.stableKey),
    productionEligible: readBooleanField(value, 'productionEligible'),
    completionBoundary: readStringField(value, 'completionBoundary') ?? '',
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
      sourceTitle: readNullableStringField(row, 'sourceTitle'),
      pageNumber: readNumberField(row, 'pageNumber'),
      x: readNumberField(row, 'x'),
      y: readNumberField(row, 'y'),
      width: readNumberField(row, 'width'),
      height: readNumberField(row, 'height'),
      coordinateUnit: readStringField(row, 'coordinateUnit') ?? 'percent',
      regionType: readStringField(row, 'regionType') ?? 'question',
      screenshotRelativePath: readNullableStringField(row, 'screenshotRelativePath'),
      screenshotUrl: readNullableStringField(row, 'screenshotUrl'),
      pageScreenshotUrl: readNullableStringField(row, 'pageScreenshotUrl'),
    })),
  }
}

export function normalizeQuestionDetailResponse(value: unknown): QuestionDetailContract {
  return {
    id: readStringField(value, 'id') ?? '',
    questionType: readNullableStringField(value, 'questionType'),
    questionNo: readNumberField(value, 'questionNo'),
    status: readStringField(value, 'status') ?? 'pending_review',
    difficultyEstimated: readNullableNumberField(value, 'difficultyEstimated'),
    blocks: readArrayField(value, 'blocks').map((block) => ({
      id: readStringField(block, 'id') ?? '',
      blockType: readStringField(block, 'blockType') ?? 'text',
      sortOrder: readNumberField(block, 'sortOrder'),
      content: readObjectField(block, 'content') ?? {},
      sourceRegionId: readNullableStringField(block, 'sourceRegionId'),
    })),
    customFields: readObjectField(value, 'customFields') ?? {},
  }
}

export function normalizeQuestionRevisionResponse(value: unknown): QuestionRevisionContract {
  return {
    question: normalizeQuestionDetailResponse(readObjectField(value, 'question') ?? {}),
    auditId: readStringField(value, 'auditId') ?? '',
  }
}

export function normalizeSourceRegionRevisionResponse(value: unknown): SourceRegionRevisionContract {
  const region = readObjectField(value, 'region') ?? {}
  return {
    region: {
      id: readStringField(region, 'id') ?? '',
      sourceDocumentId: readStringField(region, 'sourceDocumentId') ?? '',
      sourceTitle: readNullableStringField(region, 'sourceTitle'),
      pageNumber: readNumberField(region, 'pageNumber'),
      x: readNumberField(region, 'x'),
      y: readNumberField(region, 'y'),
      width: readNumberField(region, 'width'),
      height: readNumberField(region, 'height'),
      coordinateUnit: readStringField(region, 'coordinateUnit') ?? 'percent',
      regionType: readStringField(region, 'regionType') ?? 'question',
      screenshotRelativePath: readNullableStringField(region, 'screenshotRelativePath'),
      screenshotUrl: readNullableStringField(region, 'screenshotUrl'),
      pageScreenshotUrl: readNullableStringField(region, 'pageScreenshotUrl'),
    },
    auditId: readStringField(value, 'auditId') ?? '',
  }
}

function normalizeQuestionEvidenceMode(value: unknown): QuestionEvidenceSearchContract['evidenceMode'] {
  const mode = readStringField(value, 'evidenceMode')
  return mode === 'active' || mode === 'reviewed' || mode === 'candidate' ? mode : 'unknown'
}

function normalizeQuestionEvidenceTarget(value: unknown): QuestionAssessmentTargetEvidenceContract {
  return {
    id: readStringField(value, 'id') ?? '',
    stableKey: readStringField(value, 'stableKey') ?? '',
    scopeType: readStringField(value, 'scopeType') ?? 'unknown',
    targetStatement: readStringField(value, 'targetStatement') ?? '',
    isPrimaryTarget: readBooleanField(value, 'isPrimaryTarget'),
    confidence: readNumberField(value, 'confidence'),
    status: readStringField(value, 'status') ?? 'unknown',
    reviewStatus: readStringField(value, 'reviewStatus') ?? 'pending_review',
    productionEligible: readBooleanField(value, 'productionEligible'),
    abilityDimensions: readArrayField(value, 'abilityDimensions').map(String),
    cognitiveDemands: readArrayField(value, 'cognitiveDemands').map(String),
    methodOrExperimentIds: readArrayField(value, 'methodOrExperimentIds').map(String),
    contextType: readNullableStringField(value, 'contextType'),
    representationTypes: readArrayField(value, 'representationTypes').map(String),
    knowledge: readArrayField(value, 'knowledge').map((item) => ({
      stableId: readStringField(item, 'stableId') ?? '',
      displayName: readStringField(item, 'displayName') ?? '',
      role: readStringField(item, 'role') ?? 'unknown',
      confidence: readNumberField(item, 'confidence'),
      status: readStringField(item, 'status') ?? 'unknown',
      reviewStatus: readStringField(item, 'reviewStatus') ?? 'pending_review',
    })),
    requirements: readArrayField(value, 'requirements').map((item) => ({
      stableId: readStringField(item, 'stableId') ?? '',
      displayName: readStringField(item, 'displayName') ?? '',
      alignmentType: readStringField(item, 'alignmentType') ?? 'unknown',
      originalBasis: readBooleanField(item, 'originalBasis'),
      provenance: readStringField(item, 'provenance') ?? 'unknown',
      sourceDocumentId: readStringField(item, 'sourceDocumentId') ?? '',
      sourceRegionId: readNullableStringField(item, 'sourceRegionId'),
      confidence: readNumberField(item, 'confidence'),
      curriculumSourceDocumentId: readNullableStringField(item, 'curriculumSourceDocumentId'),
      curriculumSourceRegionId: readNullableStringField(item, 'curriculumSourceRegionId'),
      curriculumSourcePageNumber: readNullableNumberField(item, 'curriculumSourcePageNumber'),
    })),
    observedDifficulty: readArrayField(value, 'observedDifficulty').map((item) => ({
      value: readNumberField(item, 'value'),
      direction: readStringField(item, 'direction') ?? 'unknown',
      sampleScope: readStringField(item, 'sampleScope') ?? 'unknown',
      sourceRegionId: readStringField(item, 'sourceRegionId') ?? '',
      status: readStringField(item, 'status') ?? 'unknown',
      reviewStatus: readStringField(item, 'reviewStatus') ?? 'pending_review',
    })),
    profiles: readArrayField(value, 'profiles').map((item) => ({
      stableId: readStringField(item, 'stableId') ?? '',
      displayName: readStringField(item, 'displayName') ?? '',
      status: readStringField(item, 'status') ?? 'unknown',
      trendStatus: readNullableStringField(item, 'trendStatus'),
    })),
  }
}

export function normalizeQuestionEvidenceSearchResponse(value: unknown): QuestionEvidenceSearchContract {
  return {
    evidenceMode: normalizeQuestionEvidenceMode(value),
    previewMode: readBooleanField(value, 'previewMode'),
    productionEligible: readBooleanField(value, 'productionEligible'),
    total: readNumberField(value, 'total'),
    page: readNumberField(value, 'page'),
    pageSize: readNumberField(value, 'pageSize'),
    items: readArrayField(value, 'items').map((item) => ({
      questionId: readStringField(item, 'questionId') ?? '',
      questionNo: readNullableNumberField(item, 'questionNo'),
      subject: readStringField(item, 'subject') ?? 'unknown',
      stage: readStringField(item, 'stage') ?? 'unknown',
      grade: readNullableStringField(item, 'grade'),
      questionType: readNullableStringField(item, 'questionType'),
      status: readStringField(item, 'status') ?? 'unknown',
      estimatedDifficulty: readNullableNumberField(item, 'estimatedDifficulty'),
      estimatedDifficultySource: readStringField(item, 'estimatedDifficultySource') ?? 'unknown',
      assessmentTargets: readArrayField(item, 'assessmentTargets').map(normalizeQuestionEvidenceTarget),
      productionEligible: readBooleanField(item, 'productionEligible'),
    })),
    sort: readStringField(value, 'sort') ?? 'unknown',
    completionBoundary: readStringField(value, 'completionBoundary') ?? '',
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
      const candidateTags = row && typeof row === 'object'
        ? (row as Record<string, unknown>).candidateTags
        : null
      const candidatePrimaryKnowledge = candidateTags && typeof candidateTags === 'object'
        ? (candidateTags as Record<string, unknown>).primaryKnowledge
        : null
      const candidatePrimaryExamPoint = candidateTags && typeof candidateTags === 'object'
        ? (candidateTags as Record<string, unknown>).primaryExamPoint
        : null
      const sources = row && typeof row === 'object'
        ? (row as Record<string, unknown>).sources
        : null
      return {
        id: readStringField(row, 'id') ?? '',
        questionType: readStringField(row, 'questionType') ?? 'unknown',
        defaultScore: readNullableNumberField(row, 'defaultScore'),
        difficultyEstimated:
          readNumberField(row, 'difficultyEstimated') === 0
            ? null
            : readNumberField(row, 'difficultyEstimated'),
        status: readStringField(row, 'status') ?? 'unknown',
        questionNo: readNumberField(row, 'questionNo') === 0 ? null : readNumberField(row, 'questionNo'),
        primaryKnowledge:
          primaryKnowledge && typeof primaryKnowledge === 'object'
            ? {
                id: readStringField(primaryKnowledge, 'id') ?? '',
                title: readStringField(primaryKnowledge, 'title') ?? '',
                status: readStringField(primaryKnowledge, 'status') ?? '',
                version: readNumberField(primaryKnowledge, 'version'),
              }
            : null,
        candidateTags:
          candidateTags && typeof candidateTags === 'object'
            ? {
                primaryKnowledge:
                  candidatePrimaryKnowledge && typeof candidatePrimaryKnowledge === 'object'
                    ? {
                        id: readStringField(candidatePrimaryKnowledge, 'id') ?? '',
                        label: readStringField(candidatePrimaryKnowledge, 'label') ?? '',
                      }
                    : null,
                primaryExamPoint:
                  candidatePrimaryExamPoint && typeof candidatePrimaryExamPoint === 'object'
                    ? {
                        id: readStringField(candidatePrimaryExamPoint, 'id') ?? '',
                        label: readStringField(candidatePrimaryExamPoint, 'label') ?? '',
                      }
                    : null,
                abilityDimensions: readArrayField(candidateTags, 'abilityDimensions').map(String),
                reviewStatus: readStringField(candidateTags, 'reviewStatus') ?? 'pending_review',
                productionEligible: readBooleanField(candidateTags, 'productionEligible'),
              }
            : null,
        preview: readStringField(row, 'preview') ?? '',
        blockCount: readNumberField(row, 'blockCount'),
        assetCount: readNumberField(row, 'assetCount'),
        sources: {
          titles: readArrayField(sources, 'titles').map((x) => String(x)),
          types: readArrayField(sources, 'types').map((x) => String(x)),
          permissions: readArrayField(sources, 'permissions').map((x) => String(x)),
          sharingAllowed: readBooleanField(sources, 'sharingAllowed'),
          containsStudentPii: readBooleanField(sources, 'containsStudentPii'),
          anonymizationStatuses: readArrayField(sources, 'anonymizationStatuses').map((x) => String(x)),
          regionCount: readNumberField(sources, 'regionCount'),
          screenshotCount: readNumberField(sources, 'screenshotCount'),
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

function normalizePaperDraftQuestion(value: unknown): PaperDraftQuestionContract {
  return {
    id: readStringField(value, 'id') ?? '',
    stemPreview: readStringField(value, 'stemPreview') ?? '',
    questionType: readStringField(value, 'questionType') ?? 'unknown',
    score: readNumberField(value, 'score'),
    difficultyEstimated: readNullableNumberField(value, 'difficultyEstimated'),
    primaryKnowledgeId: readStringField(value, 'primaryKnowledgeId') ?? '',
    primaryKnowledgeTitle: readStringField(value, 'primaryKnowledgeTitle') ?? '',
    sourceType: readStringField(value, 'sourceType') ?? 'unknown',
    recentUseStatus: readStringField(value, 'recentUseStatus') ?? 'unknown',
  }
}

export function normalizePaperQuestionReplacementResponse(value: unknown): PaperQuestionReplacementContract {
  const constraints = value && typeof value === 'object'
    ? (value as Record<string, unknown>).constraints
    : null
  const undo = value && typeof value === 'object'
    ? (value as Record<string, unknown>).undo
    : null
  return {
    mode: readStringField(value, 'mode') ?? 'unknown',
    productionEligible: readBooleanField(value, 'productionEligible'),
    allowRealModelCalls: readBooleanField(value, 'allowRealModelCalls'),
    action: readStringField(value, 'action') ?? '',
    reason: readStringField(value, 'reason') ?? '',
    constraints: {
      sameKnowledge: readBooleanField(constraints, 'sameKnowledge'),
      sameQuestionType: readBooleanField(constraints, 'sameQuestionType'),
      similarDifficulty: readBooleanField(constraints, 'similarDifficulty'),
      sameScore: readBooleanField(constraints, 'sameScore'),
      excludeCurrentPaperDuplicates: readBooleanField(constraints, 'excludeCurrentPaperDuplicates'),
      excludeRecentlyUsed: readBooleanField(constraints, 'excludeRecentlyUsed'),
      knowledgeStatus: readStringField(constraints, 'knowledgeStatus') ?? 'unknown',
      blocksProductionPaper: readBooleanField(constraints, 'blocksProductionPaper'),
    },
    replacement: normalizePaperDraftQuestion(
      value && typeof value === 'object' ? (value as Record<string, unknown>).replacement : null,
    ),
    undo: {
      undoToken: readStringField(undo, 'undoToken') ?? '',
      beforeQuestion: normalizePaperDraftQuestion(
        undo && typeof undo === 'object' ? (undo as Record<string, unknown>).beforeQuestion : null,
      ),
      afterQuestion: normalizePaperDraftQuestion(
        undo && typeof undo === 'object' ? (undo as Record<string, unknown>).afterQuestion : null,
      ),
      revertAction: readStringField(undo, 'revertAction') ?? '',
    },
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

export function normalizeScoreEvidenceAnalysisResponse(value: unknown): ScoreEvidenceAnalysisContract {
  const normalizeDimension = (dimension: unknown): ScoreEvidenceDimensionContract => ({
    stableId: readStringField(dimension, 'stableId') ?? '',
    displayName: readStringField(dimension, 'displayName') ?? '',
    scoreRate: readNumberField(dimension, 'scoreRate'),
    scoreRecordCount: readNumberField(dimension, 'scoreRecordCount'),
    questionNos: readArrayField(dimension, 'questionNos').map(String),
    version: readNullableNumberField(dimension, 'version'),
    evidenceRole: readStringField(dimension, 'evidenceRole') ?? 'unknown',
  })
  return {
    status: readStringField(value, 'status') ?? 'blocked',
    mode: readStringField(value, 'mode') ?? 'unknown',
    productionEligible: readBooleanField(value, 'productionEligible'),
    realStudentDataUsed: readBooleanField(value, 'realStudentDataUsed'),
    writesProductionHistory: readBooleanField(value, 'writesProductionHistory'),
    assessmentId: readStringField(value, 'assessmentId') ?? '',
    assessmentTitle: readStringField(value, 'assessmentTitle') ?? '',
    scoreDerivedPerformance: readArrayField(value, 'scoreDerivedPerformance').map((item) => ({
      questionNo: readStringField(item, 'questionNo') ?? '',
      assessmentTargetStableKey: readStringField(item, 'assessmentTargetStableKey') ?? '',
      targetStatement: readStringField(item, 'targetStatement') ?? '',
      scoreRecordCount: readNumberField(item, 'scoreRecordCount'),
      averageScoreRate: readNumberField(item, 'averageScoreRate'),
      abilityDimensions: readArrayField(item, 'abilityDimensions').map(String),
      cognitiveDemands: readArrayField(item, 'cognitiveDemands').map(String),
      evidenceRole: readStringField(item, 'evidenceRole') ?? 'unknown',
    })),
    knowledgeMastery: readArrayField(value, 'knowledgeMastery').map(normalizeDimension),
    abilityPerformance: readArrayField(value, 'abilityPerformance').map(normalizeDimension),
    cognitivePerformance: readArrayField(value, 'cognitivePerformance').map(normalizeDimension),
    observedContexts: readArrayField(value, 'observedContexts').map((context) => ({
      evidenceId: readStringField(context, 'evidenceId') ?? '',
      difficultyObserved: readNullableNumberField(context, 'difficultyObserved'),
      scoreRate: readNullableNumberField(context, 'scoreRate'),
      sampleScope: readStringField(context, 'sampleScope') ?? '',
      sourceRegionId: readStringField(context, 'sourceRegionId') ?? '',
      contextRole: readStringField(context, 'contextRole') ?? 'unknown',
    })),
    errorPatternAssociations: readArrayField(value, 'errorPatternAssociations').map((error) => ({
      evidenceId: readStringField(error, 'evidenceId') ?? '',
      kind: readStringField(error, 'kind') ?? 'unknown',
      content: readStringField(error, 'content') ?? '',
      sourceRegionId: readNullableStringField(error, 'sourceRegionId'),
      relation: readStringField(error, 'relation') ?? 'association_not_cause',
      diagnosisStatus: readStringField(error, 'diagnosisStatus') ?? 'pending_teacher_confirmation',
    })),
    teachingRecommendations: readArrayField(value, 'teachingRecommendations').map((recommendation) => ({
      recommendationId: readStringField(recommendation, 'recommendationId') ?? '',
      content: readStringField(recommendation, 'content') ?? '',
      authorKind: readStringField(recommendation, 'authorKind') ?? 'unknown',
      generationMethod: readStringField(recommendation, 'generationMethod') ?? 'unknown',
      sourceRegionId: readStringField(recommendation, 'sourceRegionId') ?? '',
      factRole: readStringField(recommendation, 'factRole') ?? 'not_curriculum_fact',
    })),
    teacherConfirmedDiagnoses: readArrayField(value, 'teacherConfirmedDiagnoses').map((diagnosis) => ({
      assessmentTargetId: readStringField(diagnosis, 'assessmentTargetId') ?? '',
      diagnosis: readStringField(diagnosis, 'diagnosis') ?? '',
      confirmedBy: readStringField(diagnosis, 'confirmedBy') ?? '',
      confirmedAt: readStringField(diagnosis, 'confirmedAt') ?? '',
    })),
    diagnosisStatus: readStringField(value, 'diagnosisStatus') ?? 'pending_teacher_confirmation',
    blockingIssues: readArrayField(value, 'blockingIssues').map((issue) => ({
      scope: readStringField(issue, 'scope') ?? 'assessment',
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

export function normalizeAdminAiProviderSettingsResponse(
  value: unknown,
): AdminAiProviderSettingsContract {
  return {
    status: readStringField(value, 'status') ?? 'unknown',
    mode: readStringField(value, 'mode') ?? 'unknown',
    productionEligible: readBooleanField(value, 'productionEligible'),
    providerProfileId: readStringField(value, 'providerProfileId') ?? '',
    providerType: readStringField(value, 'providerType') ?? '',
    baseUrl: readStringField(value, 'baseUrl') ?? '',
    imageBaseUrl: readStringField(value, 'imageBaseUrl') ?? '',
    credentialMode: readStringField(value, 'credentialMode') ?? '',
    maskedSecret: readStringField(value, 'maskedSecret') ?? '',
    secretConfigured: readBooleanField(value, 'secretConfigured'),
    maskedImageSecret: readStringField(value, 'maskedImageSecret') ?? '',
    imageSecretConfigured: readBooleanField(value, 'imageSecretConfigured'),
    imageUsesPrimarySecret: readBooleanField(value, 'imageUsesPrimarySecret'),
    maxConcurrency: readNumberField(value, 'maxConcurrency'),
    monthlyBudgetCny: readNumberField(value, 'monthlyBudgetCny'),
    disabledByDefault: readBooleanField(value, 'disabledByDefault'),
    allowRealModelCalls: readBooleanField(value, 'allowRealModelCalls'),
    defaultSmokeTaskType: readStringField(value, 'defaultSmokeTaskType') ?? '',
    defaultSmokeModel: readStringField(value, 'defaultSmokeModel') ?? '',
    fallbackBaseUrl: readStringField(value, 'fallbackBaseUrl') ?? '',
    fallbackImageBaseUrl: readStringField(value, 'fallbackImageBaseUrl') ?? '',
    maskedFallbackSecret: readStringField(value, 'maskedFallbackSecret') ?? '',
    fallbackSecretConfigured: readBooleanField(value, 'fallbackSecretConfigured'),
    maskedFallbackImageSecret: readStringField(value, 'maskedFallbackImageSecret') ?? '',
    fallbackImageSecretConfigured: readBooleanField(value, 'fallbackImageSecretConfigured'),
    fallbackImageUsesPrimarySecret: readBooleanField(value, 'fallbackImageUsesPrimarySecret'),
    endpoints: readArrayField(value, 'endpoints').map(normalizeAdminAiProviderEndpointResponse),
    lastUpdatedAt: readStringField(value, 'lastUpdatedAt') ?? '',
    teacherMessage: readStringField(value, 'teacherMessage') ?? '',
    auditTrail: readArrayField(value, 'auditTrail').map(String),
  }
}

function normalizeAdminAiProviderEndpointResponse(value: unknown): AdminAiProviderEndpointContract {
  return {
    endpointId: readStringField(value, 'endpointId') ?? '',
    label: readStringField(value, 'label') ?? '',
    isFallback: readBooleanField(value, 'isFallback'),
    baseUrl: readStringField(value, 'baseUrl') ?? '',
    imageBaseUrl: readStringField(value, 'imageBaseUrl') ?? '',
    maskedSecret: readStringField(value, 'maskedSecret') ?? '',
    secretConfigured: readBooleanField(value, 'secretConfigured'),
    maskedImageSecret: readStringField(value, 'maskedImageSecret') ?? '',
    imageSecretConfigured: readBooleanField(value, 'imageSecretConfigured'),
    imageUsesTextSecret: readBooleanField(value, 'imageUsesTextSecret'),
  }
}

export function normalizeAdminAiProviderSettingsSaveResponse(
  value: unknown,
): AdminAiProviderSettingsSaveContract {
  return {
    status: readStringField(value, 'status') ?? 'unknown',
    mode: readStringField(value, 'mode') ?? 'unknown',
    productionEligible: readBooleanField(value, 'productionEligible'),
    providerProfileId: readStringField(value, 'providerProfileId') ?? '',
    secretConfigured: readBooleanField(value, 'secretConfigured'),
    maskedSecret: readStringField(value, 'maskedSecret') ?? '',
    imageSecretConfigured: readBooleanField(value, 'imageSecretConfigured'),
    maskedImageSecret: readStringField(value, 'maskedImageSecret') ?? '',
    imageUsesPrimarySecret: readBooleanField(value, 'imageUsesPrimarySecret'),
    fallbackSecretConfigured: readBooleanField(value, 'fallbackSecretConfigured'),
    maskedFallbackSecret: readStringField(value, 'maskedFallbackSecret') ?? '',
    fallbackImageSecretConfigured: readBooleanField(value, 'fallbackImageSecretConfigured'),
    maskedFallbackImageSecret: readStringField(value, 'maskedFallbackImageSecret') ?? '',
    fallbackImageUsesPrimarySecret: readBooleanField(value, 'fallbackImageUsesPrimarySecret'),
    lastUpdatedAt: readStringField(value, 'lastUpdatedAt') ?? '',
    teacherMessage: readStringField(value, 'teacherMessage') ?? '',
    auditTrail: readArrayField(value, 'auditTrail').map(String),
  }
}

function normalizeAdminAiProviderProbeAttemptResponse(
  value: unknown,
): AdminAiProviderProbeAttemptContract {
  return {
    providerEndpointId: readStringField(value, 'providerEndpointId') ?? '',
    baseUrl: readStringField(value, 'baseUrl') ?? '',
    routeKind: readStringField(value, 'routeKind') ?? 'unknown',
    endpointPath: readStringField(value, 'endpointPath') ?? '',
    model: readStringField(value, 'model') ?? '',
    passed: readBooleanField(value, 'passed'),
    httpStatusCode: readNumberField(value, 'httpStatusCode'),
    latencyMs: readNumberField(value, 'latencyMs'),
    message: readStringField(value, 'message') ?? '',
  }
}

function normalizeAdminAiProviderImageProbeAttemptResponse(
  value: unknown,
): AdminAiProviderImageProbeAttemptContract {
  return {
    providerEndpointId: readStringField(value, 'providerEndpointId') ?? '',
    baseUrl: readStringField(value, 'baseUrl') ?? '',
    routeKind: readStringField(value, 'routeKind') ?? 'unknown',
    endpointPath: readStringField(value, 'endpointPath') ?? '',
    model: readStringField(value, 'model') ?? '',
    passed: readBooleanField(value, 'passed'),
    httpStatusCode: readNumberField(value, 'httpStatusCode'),
    latencyMs: readNumberField(value, 'latencyMs'),
    message: readStringField(value, 'message') ?? '',
  }
}

function normalizeAdminAiProviderImageProbeResponse(
  value: unknown,
): AdminAiProviderImageProbeResultContract {
  return {
    attempted: readBooleanField(value, 'attempted'),
    passed: readBooleanField(value, 'passed'),
    effectiveProviderEndpointId: readStringField(value, 'effectiveProviderEndpointId') ?? '',
    effectiveBaseUrl: readStringField(value, 'effectiveBaseUrl') ?? '',
    effectiveRouteKind: readStringField(value, 'effectiveRouteKind') ?? '',
    effectiveModel: readStringField(value, 'effectiveModel') ?? '',
    httpStatusCode: readNumberField(value, 'httpStatusCode'),
    latencyMs: readNumberField(value, 'latencyMs'),
    message: readStringField(value, 'message') ?? '',
    blockers: readArrayField(value, 'blockers').map(String),
    attempts: readArrayField(value, 'attempts').map(normalizeAdminAiProviderImageProbeAttemptResponse),
    auditTrail: readArrayField(value, 'auditTrail').map(String),
  }
}

export function normalizeAdminAiProviderSettingsTestResponse(
  value: unknown,
): AdminAiProviderSettingsTestContract {
  const imageProbe = readObjectField(value, 'imageProbe')
  return {
    status: readStringField(value, 'status') ?? 'unknown',
    mode: readStringField(value, 'mode') ?? 'unknown',
    productionEligible: readBooleanField(value, 'productionEligible'),
    providerProfileId: readStringField(value, 'providerProfileId') ?? '',
    providerType: readStringField(value, 'providerType') ?? '',
    model: readStringField(value, 'model') ?? '',
    taskType: readStringField(value, 'taskType') ?? '',
    reviewStatus: readStringField(value, 'reviewStatus') ?? '',
    passed: readBooleanField(value, 'passed'),
    combinedPassed: readBooleanField(value, 'combinedPassed'),
    effectiveProviderEndpointId: readStringField(value, 'effectiveProviderEndpointId') ?? '',
    effectiveBaseUrl: readStringField(value, 'effectiveBaseUrl') ?? '',
    httpStatusCode: readNumberField(value, 'httpStatusCode'),
    message: readStringField(value, 'message') ?? '',
    outputJson: readStringField(value, 'outputJson') ?? '',
    inputTokens: readNumberField(value, 'inputTokens'),
    outputTokens: readNumberField(value, 'outputTokens'),
    cachedTokens: readNumberField(value, 'cachedTokens'),
    cost: readNumberField(value, 'cost'),
    latencyMs: readNumberField(value, 'latencyMs'),
    blockers: readArrayField(value, 'blockers').map(String),
    attempts: readArrayField(value, 'attempts').map(normalizeAdminAiProviderProbeAttemptResponse),
    imageProbe: imageProbe
      ? normalizeAdminAiProviderImageProbeResponse(imageProbe)
      : {
          attempted: false,
          passed: false,
          effectiveProviderEndpointId: '',
          effectiveBaseUrl: '',
          effectiveRouteKind: '',
          effectiveModel: '',
          httpStatusCode: 0,
          latencyMs: 0,
          message: '',
          blockers: [],
          attempts: [],
          auditTrail: [],
        },
    auditTrail: readArrayField(value, 'auditTrail').map(String),
  }
}
