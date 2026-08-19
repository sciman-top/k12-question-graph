import { Suspense, lazy, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  Alert,
  Badge,
  Button,
  ConfigProvider,
  Divider,
  Input,
  Layout,
  Progress,
  Select,
  Space,
  Tag,
  Typography,
} from 'antd'
import {
  CheckCircleOutlined,
  CloudUploadOutlined,
  EditOutlined,
  FileSearchOutlined,
  LinkOutlined,
  MergeCellsOutlined,
  SearchOutlined,
  SplitCellsOutlined,
  UndoOutlined,
} from '@ant-design/icons'
import './App.css'
import {
  applyReviewWorkbenchAction,
  confirmPaperBlueprintReview,
  createPaperBlueprintReview,
  createScoreImport,
  downloadPaperArtifact,
  exportCommentaryReport,
  generateCutCandidates,
  getCutCandidates,
  getQuestion,
  getQuestionSources,
  getReviewQueueItems,
  previewItemScoreMappings,
  previewScoreEvidenceAnalysis,
  reopenReviewQueueItem,
  replacePaperQuestion,
  resolveReviewQueueItem,
  runDocumentWorkerSmoke,
  searchQuestions,
  updateQuestion,
  updateSourceRegion,
  uploadImportFile,
} from './api/client'
import type {
  QuestionDetailContract,
  QuestionEvidenceCardContract,
  QuestionSourceRegionContract,
  ReviewQueueItemContract,
  ScoreImportContract,
} from './api/contracts'
import {
  useCutCandidatesQuery,
  useImportJobQuery,
  useReadyHealthQuery,
  useSourceMaterialsQuery,
  useSourcePreviewQuery,
} from './api/queries'
import { AnalysisPanelContent } from './ui/AnalysisPanelContent'
import { PaperWorkbenchPanels } from './ui/PaperWorkbenchPanels'
import { RealExamReviewWorkbench } from './ui/RealExamReviewWorkbench'
import { ScoreWorkbenchPanelContent } from './ui/ScoreWorkbenchPanelContent'
import { TeacherQuestionExtractionPanel, type TeacherQuestionExtractionDraft } from './ui/TeacherQuestionExtractionPanel'
import { TeacherHomePanelContent } from './ui/TeacherHomePanelContent'
import { teacherDifficultyLabelFor, teacherLabelFor } from './ui/teacherLabels'
import { useActionLog } from './ui/useActionLog'
import { useQuestionEvidenceWorkbench } from './ui/useQuestionEvidenceWorkbench'
import {
  formatRegionKind,
  guangzhou2015EvidencePreview,
  hasRenderableImage,
  initialCommentaryReportPreview,
  initialItemScoreMappingPreview,
  initialPaperDraft,
  initialPaperRequest,
  initialPaperUnderstanding,
  initialScoreEvidenceAnalysis,
  initialSegments,
  importWizardSteps,
  isQuestionAssetRegion,
  jobStates,
  paperDraftQuestionFor,
  realExamPaperKey,
  realExamPaperTitle,
  renderMathAwareText,
  sharedAssets,
  sourceRegionRank,
  splitQuestionText,
  type RealExamPreviewRow,
  type RealExamRevisionState,
  type StarterDemoStep,
  type TeacherView,
} from './ui/workbenchData'

const AdminGovernancePanels = lazy(async () => {
  const module = await import('./ui/AdminGovernancePanels')
  return { default: module.AdminGovernancePanels }
})


function App() {
  const readyHealthQuery = useReadyHealthQuery()
  const [adminWorkspaceVisible, setAdminWorkspaceVisible] = useState<boolean>(() => {
    if (typeof window === 'undefined') {
      return false
    }

    return new URLSearchParams(window.location.search).get('admin') === '1'
  })
  const [sourceTypeFilter, setSourceTypeFilter] = useState('all')
  const [importJobLookupId, setImportJobLookupId] = useState('')
  const [selectedSourceDocumentId, setSelectedSourceDocumentId] = useState('')
  const [realExamQueue, setRealExamQueue] = useState<ReviewQueueItemContract[]>([])
  const [realExamQueueTotal, setRealExamQueueTotal] = useState(0)
  const [realExamQueueBusy, setRealExamQueueBusy] = useState(false)
  const [realExamExtractionSaving, setRealExamExtractionSaving] = useState(false)
  const [realExamQueueMessage, setRealExamQueueMessage] = useState('尚未查询 2015-2025 真卷复核队列')
  const [realExamReviewYear, setRealExamReviewYear] = useState(2015)
  const [selectedRealExamPaperId, setSelectedRealExamPaperId] = useState('')
  const [selectedRealExamReviewId, setSelectedRealExamReviewId] = useState('')
  const [loadedRealExamQuestion, setLoadedRealExamQuestion] = useState<QuestionDetailContract | null>(null)
  const [lastReviewedRealExamItem, setLastReviewedRealExamItem] = useState<ReviewQueueItemContract | null>(null)
  const [cropDraft, setCropDraft] = useState<QuestionSourceRegionContract | null>(null)
  const [cropUndoSnapshot, setCropUndoSnapshot] = useState<QuestionSourceRegionContract | null>(null)
  const [selectedEvidenceQuestionNo, setSelectedEvidenceQuestionNo] = useState(
    guangzhou2015EvidencePreview[0].questionNo,
  )
  const [realExamReviewNote, setRealExamReviewNote] = useState('已核对题干、答案、标签和来源')
  const [realExamRevision, setRealExamRevision] = useState<RealExamRevisionState>({
    textPreview: guangzhou2015EvidencePreview[0].textPreview,
    answer: guangzhou2015EvidencePreview[0].answer,
    primaryKnowledgeLabel: guangzhou2015EvidencePreview[0].primaryKnowledgeLabel,
    knowledgeTagsText: guangzhou2015EvidencePreview[0].knowledgeTags.join(' / '),
    difficultyEstimated: null,
  })
  const [activeTeacherView, setActiveTeacherView] = useState<TeacherView>('import')
  const [segments, setSegments] = useState(initialSegments)
  const [selectedIds, setSelectedIds] = useState<string[]>(['q-02', 'q-03'])
  const [selectedAsset, setSelectedAsset] = useState(sharedAssets[0])
  const { actionLog, appendLog, replaceLatestWithUndoLog } = useActionLog()
  const [savedQuestionSourceSummary, setSavedQuestionSourceSummary] = useState('尚未保存题目')
  const [savedQuestionSourceRegions, setSavedQuestionSourceRegions] = useState<QuestionSourceRegionContract[]>([])
  const [paperRequest, setPaperRequest] = useState(initialPaperRequest)
  const [paperUnderstanding, setPaperUnderstanding] = useState(initialPaperUnderstanding)
  const [paperBlueprintReviewId, setPaperBlueprintReviewId] = useState('')
  const [paperBasketId, setPaperBasketId] = useState('')
  const [paperWorkflowMessage, setPaperWorkflowMessage] = useState('生成细目表后，确认按钮才会取题并保存题篮。')
  const [paperConstraintMessage, setPaperConstraintMessage] = useState('需要先确认细目表，不会直接生成不可解释试卷。')
  const [paperWorkflowBusy, setPaperWorkflowBusy] = useState(false)
  const [paperDraft, setPaperDraft] = useState(initialPaperDraft)
  const [scoreMappingAssessmentId, setScoreMappingAssessmentId] = useState('')
  const [scoreMappingMessage, setScoreMappingMessage] = useState(initialItemScoreMappingPreview.teacherMessage)
  const [itemScoreMappingPreview, setItemScoreMappingPreview] = useState(initialItemScoreMappingPreview)
  const [commentaryReportPreview, setCommentaryReportPreview] = useState(initialCommentaryReportPreview)
  const [scoreEvidenceAnalysis, setScoreEvidenceAnalysis] = useState(initialScoreEvidenceAnalysis)
  const [scoreImportPreview, setScoreImportPreview] = useState<ScoreImportContract | null>(null)
  const [scoreWorkflowBusy, setScoreWorkflowBusy] = useState(false)
  const [scoreQuestionMappings, setScoreQuestionMappings] = useState<Record<string, string | null>>({})
  const [scoreQuestionOptions, setScoreQuestionOptions] = useState<Array<{ value: string; label: string }>>([])
  const [analysisMessage, setAnalysisMessage] = useState('点击查看摘要后，会聚焦当前讲评建议和导出状态。')
  const [importStartedAt] = useState<Date>(() => new Date())
  const [nowMs, setNowMs] = useState<number>(() => Date.now())
  const [importActionCount, setImportActionCount] = useState(0)
  const [failureTakeoverCount, setFailureTakeoverCount] = useState(0)
  const [lastTakeoverAction, setLastTakeoverAction] = useState<string | null>(null)
  const [importUploadBusy, setImportUploadBusy] = useState(false)
  const localIdRef = useRef(0)
  const uploadInputRef = useRef<HTMLInputElement | null>(null)
  const uploadDropzoneRef = useRef<HTMLButtonElement | null>(null)
  const realExamAutoLoadStartedRef = useRef(false)
  const realExamLoadRequestRef = useRef(0)

  const selectedSegments = useMemo(
    () => segments.filter((segment) => selectedIds.includes(segment.id)),
    [segments, selectedIds],
  )
  const sourceMaterialsQuery = useSourceMaterialsQuery(
    sourceTypeFilter === 'all' ? undefined : sourceTypeFilter,
  )
  const importJobQuery = useImportJobQuery(importJobLookupId.trim(), importJobLookupId.trim().length > 0)
  const readyHealth = readyHealthQuery.data?.ok ? readyHealthQuery.data.data : undefined
  const sourceMaterials =
    sourceMaterialsQuery.data?.ok ? sourceMaterialsQuery.data.data.sourceDocuments : []
  const previewQuery = useSourcePreviewQuery(selectedSourceDocumentId, selectedSourceDocumentId.length > 0)
  const cutCandidatesQuery = useCutCandidatesQuery(
    selectedSourceDocumentId,
    selectedSourceDocumentId.length > 0,
  )
  const cutCandidates = cutCandidatesQuery.data?.ok ? cutCandidatesQuery.data.data : undefined
  const sourcePreview = previewQuery.data?.ok ? previewQuery.data.data : undefined
  const importJob = importJobQuery.data?.ok ? importJobQuery.data.data : undefined
  const selectedRealExamReview = realExamQueue.find((item) => item.id === selectedRealExamReviewId)
  const realExamYearOptions = useMemo(() => {
    const years = [...new Set(realExamQueue.map((item) => item.payload.year).filter(Boolean))].sort()
    return (years.length > 0 ? years : Array.from({ length: 11 }, (_, index) => 2015 + index))
      .map((year) => ({ value: year, label: `${year} 年` }))
  }, [realExamQueue])
  const realExamPaperOptions = useMemo(() => {
    const options = new Map<string, string>()
    realExamQueue
      .filter((item) => item.payload.year === realExamReviewYear)
      .forEach((item) => options.set(realExamPaperKey(item), realExamPaperTitle(item)))
    if (options.size === 0) {
      options.set(`${realExamReviewYear}:primary-paper`, `${realExamReviewYear} 广州中考物理试卷`)
    }
    return [...options].map(([value, label]) => ({ value, label }))
  }, [realExamQueue, realExamReviewYear])
  const activeRealExamPaperId = selectedRealExamPaperId || realExamPaperOptions[0]?.value || ''
  const visibleRealExamQueue = useMemo(
    () => realExamQueue.filter(
      (item) => item.payload.year === realExamReviewYear && realExamPaperKey(item) === activeRealExamPaperId,
    ),
    [activeRealExamPaperId, realExamQueue, realExamReviewYear],
  )
  const realExamQuestionOptions = useMemo(
    () => [...visibleRealExamQueue]
      .sort((left, right) => left.payload.questionNo - right.payload.questionNo)
      .map((item) => ({ value: item.id, label: `第 ${item.payload.questionNo} 题` })),
    [visibleRealExamQueue],
  )
  const realExamPreviewRows = useMemo(() => {
    if (realExamQueue.length === 0) {
      return realExamReviewYear === 2015 ? guangzhou2015EvidencePreview : []
    }

    return [...visibleRealExamQueue]
      .sort((left, right) => (left.payload.questionNo || 0) - (right.payload.questionNo || 0))
      .map<RealExamPreviewRow>((item) => ({
        questionNo: item.payload.questionNo || 0,
        textPreview: item.payload.textPreview,
        answer: item.payload.answer,
        primaryKnowledgeLabel: item.payload.primaryKnowledgeLabel,
        knowledgeTags: item.payload.knowledgeTags,
        sourceLabel: item.payload.sourceDocumentId ? '来自数据库复核队列' : '来源待回看',
      }))
  }, [realExamQueue.length, realExamReviewYear, visibleRealExamQueue])
  const selectedEvidenceQuestion =
    guangzhou2015EvidencePreview.find((item) => item.questionNo === selectedEvidenceQuestionNo) ??
    guangzhou2015EvidencePreview[0]
  const selectedRealExamPreview: RealExamPreviewRow = selectedRealExamReview
    ? {
      questionNo: selectedRealExamReview.payload.questionNo || 0,
      textPreview: realExamRevision.textPreview,
      answer: realExamRevision.answer,
      primaryKnowledgeLabel: realExamRevision.primaryKnowledgeLabel,
      knowledgeTags: realExamRevision.knowledgeTagsText.split(/[、,，/]/).map((tag) => tag.trim()).filter(Boolean),
      sourceLabel: loadedRealExamQuestion ? '来自数据库复核队列' : '来源待回看',
    }
    : selectedEvidenceQuestion
  const selectedQuestionAssetRegions = savedQuestionSourceRegions
    .filter(isQuestionAssetRegion)
    .sort(
      (left, right) =>
        left.pageNumber - right.pageNumber ||
        sourceRegionRank(left.regionType) - sourceRegionRank(right.regionType),
    )
  const readyHealthStatusLabel = readyHealth?.status === 'ok' ? '正常' : '服务未连接'
  const importElapsedMinutes = Math.max(
    0,
    Math.round((nowMs - importStartedAt.getTime()) / 60000),
  )
  const s003dEvidenceSummary = JSON.stringify(
    {
      contract: 's003d-import-efficiency',
      elapsedMinutes: importElapsedMinutes,
      actionCount: importActionCount,
      failureTakeoverCount,
      lastTakeoverAction,
      sourceMaterialCount: sourceMaterials.length,
      importJobStatus: importJob?.status ?? 'not_queried',
      updatedAt: new Date().toISOString(),
    },
    null,
    2,
  )

  const toggleAdminWorkspace = useCallback(() => {
    setAdminWorkspaceVisible((current) => {
      const next = !current
      if (typeof window !== 'undefined') {
        const url = new URL(window.location.href)
        if (next) {
          url.searchParams.set('admin', '1')
        } else {
          url.searchParams.delete('admin')
        }

        window.history.replaceState({}, '', `${url.pathname}${url.search}${url.hash}`)
      }

      return next
    })
  }, [])

  useEffect(() => {
    const timer = window.setInterval(() => setNowMs(Date.now()), 30_000)
    return () => window.clearInterval(timer)
  }, [])

  const {
    activeEvidenceFilter,
    applyEvidenceFilter,
    changeQuestionEvidenceMode,
    clearEvidenceFilters,
    openQuestionEvidenceSource,
    questionEvidenceMode,
    questionEvidenceSearch,
    questionEvidenceSearchQuery,
    questionInteractionMessage,
    returnToQuestionBasket,
    selectQuestionEvidenceCard,
    selectedEvidenceQuestionId,
  } = useQuestionEvidenceWorkbench(appendLog)

  const nextLocalId = (prefix: string) => {
    localIdRef.current += 1
    return `${prefix}-${localIdRef.current}`
  }

  const trackImportAction = () => {
    setImportActionCount((count) => count + 1)
  }

  const openTeacherView = (view: TeacherView) => {
    setActiveTeacherView(view)
    if (view === 'import') {
      window.requestAnimationFrame(() => {
        uploadDropzoneRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' })
        uploadDropzoneRef.current?.focus({ preventScroll: true })
      })
    }
  }

  const selectEvidenceQuestion = (item: RealExamPreviewRow) => {
    setSelectedRealExamReviewId('')
    setSelectedEvidenceQuestionNo(item.questionNo)
    setRealExamRevision({
      textPreview: item.textPreview,
      answer: item.answer,
      primaryKnowledgeLabel: item.primaryKnowledgeLabel,
      knowledgeTagsText: item.knowledgeTags.join(' / '),
      difficultyEstimated: null,
    })
    setSavedQuestionSourceSummary(item.sourceLabel)
    setRealExamQueueMessage('当前显示本地证据预览；连接 API 后可直接确认、退回和写入审核记录。')
  }

  const handlePaperUploadFile = async (file: File) => {
    if (importUploadBusy) {
      return
    }

    setImportUploadBusy(true)
    trackImportAction()
    appendLog(`正在上传：${file.name}`)

    const uploadResult = await uploadImportFile(file)
    if (!uploadResult.ok) {
      appendLog(`上传失败：${uploadResult.error.message}`)
      setImportUploadBusy(false)
      return
    }

    const importJobId = uploadResult.data.id
    const sourceDocumentId = uploadResult.data.sourceDocumentId
    setImportJobLookupId(importJobId)
    if (sourceDocumentId) {
      setSelectedSourceDocumentId(sourceDocumentId)
    }
    appendLog(`已创建导入任务：${importJobId}`)

    const workerResult = await runDocumentWorkerSmoke(importJobId)
    if (!workerResult.ok) {
      appendLog(`本地解析失败：${workerResult.error.message}`)
      setImportUploadBusy(false)
      return
    }

    appendLog(`本地解析完成：${workerResult.data.status}`)
    await sourceMaterialsQuery.refetch()

    if (sourceDocumentId) {
      const candidateResult = await getCutCandidates(sourceDocumentId)
      if (candidateResult.ok && candidateResult.data.items.length > 0) {
        applyCutCandidatesToWorkspace(candidateResult.data.items)
      } else if (candidateResult.ok) {
        appendLog('本地解析未生成候选，请进入人工接管补切。')
      } else {
        appendLog(`候选查询失败：${candidateResult.error.message}`)
      }
    }

    setImportUploadBusy(false)
  }

  const toggleSegment = (id: string) => {
    trackImportAction()
    setSelectedIds((current) =>
      current.includes(id) ? current.filter((item) => item !== id) : [...current, id],
    )
  }

  const mergeSelected = async () => {
    const sourceDocumentId = selectedSourceDocumentId.trim()
    if (sourceDocumentId && selectedSegments.length >= 2) {
      const result = await runWorkbenchAction('merge')
      if (result) {
        return
      }
    }

    if (selectedSegments.length < 2) {
      return
    }

    const merged = {
      id: nextLocalId('q'),
      title: `${selectedSegments[0].title} 合并题`,
      page: selectedSegments.map((segment) => segment.page).join(' / '),
      region: selectedSegments.map((segment) => segment.region).join(' + '),
      asset: selectedSegments.find((segment) => segment.asset)?.asset ?? '',
      confidence:
        selectedSegments.reduce((sum, segment) => sum + segment.confidence, 0) /
        selectedSegments.length,
      failureReason: '',
      takeoverAction: 'manual_review',
      status: 'pending_review',
    }
    const selected = new Set(selectedIds)
    setSegments((current) => [merged, ...current.filter((segment) => !selected.has(segment.id))])
    setSelectedIds([merged.id])
    trackImportAction()
    appendLog(`已合并 ${selectedSegments.length} 个片段为 ${merged.title}`)
  }

  const splitSelected = async () => {
    const sourceDocumentId = selectedSourceDocumentId.trim()
    if (sourceDocumentId && selectedSegments.length === 1) {
      const result = await runWorkbenchAction('split')
      if (result) {
        return
      }
    }

    if (selectedSegments.length !== 1) {
      return
    }

    const [target] = selectedSegments
    const split = [
      {
        ...target,
        id: `${target.id}-a`,
        title: `${target.title} A`,
        region: `${target.region} 上半`,
        confidence: Math.max(0.1, target.confidence - 0.05),
      },
      {
        ...target,
        id: `${target.id}-b`,
        title: `${target.title} B`,
        region: `${target.region} 下半`,
        confidence: Math.max(0.1, target.confidence - 0.05),
      },
    ]
    setSegments((current) =>
      current.flatMap((segment) => (segment.id === target.id ? split : [segment])),
    )
    setSelectedIds(split.map((segment) => segment.id))
    trackImportAction()
    appendLog(`已拆分 ${target.title}`)
  }

  const associateAsset = async () => {
    if (selectedSourceDocumentId.trim() && selectedIds.length > 0) {
      const result = await runWorkbenchAction('associate')
      if (result) {
        return
      }
    }

    if (selectedIds.length === 0) {
      return
    }

    const selected = new Set(selectedIds)
    setSegments((current) =>
      current.map((segment) =>
        selected.has(segment.id) ? { ...segment, asset: selectedAsset } : segment,
      ),
    )
    trackImportAction()
    appendLog(`已关联 ${selectedAsset} 到 ${selectedIds.length} 个片段`)
  }

  const takeoverFailure = async (action: string) => {
    if (selectedSourceDocumentId.trim() && selectedIds.length > 0) {
      const mappedAction = action.includes('重跑')
        ? 'rerun'
        : action.includes('跳过')
          ? 'skip'
          : undefined
      if (mappedAction) {
        const result = await runWorkbenchAction(mappedAction)
        if (result) {
          return
        }
      }
    }

    trackImportAction()
    setFailureTakeoverCount((count) => count + 1)
    setLastTakeoverAction(action)
    appendLog(`失败接管：${action}`)
  }

  const selectExceptionItems = () => {
    setSelectedIds(
      segments
        .filter((segment) => segment.confidence < 0.85 || segment.failureReason.length > 0)
        .slice(0, 5)
        .map((segment) => segment.id),
    )
    trackImportAction()
    appendLog('已筛选需要确认的异常项')
  }

  const batchConfirmSelected = async () => {
    if (selectedSourceDocumentId.trim() && selectedIds.length > 0) {
      const result = await runWorkbenchAction('save_question')
      if (result) {
        return
      }
    }

    if (selectedIds.length === 0) {
      return
    }

    appendLog(`已批量确认 ${selectedIds.length} 个异常项`)
    trackImportAction()
    setSelectedIds([])
  }

  const undoLast = async () => {
    if (selectedSourceDocumentId.trim() && selectedIds.length > 0) {
      const result = await runWorkbenchAction('undo')
      if (result) {
        return
      }
    }

    setSegments(initialSegments)
    setSelectedIds(['q-02', 'q-03'])
    trackImportAction()
    replaceLatestWithUndoLog()
  }

  const runCutCandidateGeneration = async () => {
    const sourceDocumentId = selectedSourceDocumentId.trim()
    if (!sourceDocumentId) {
      appendLog('请先输入来源文档 ID 再生成候选')
      return
    }

    trackImportAction()
    const result = await generateCutCandidates(sourceDocumentId)
    if (!result.ok) {
      appendLog(`候选生成失败：${result.error.message}`)
      return
    }

    appendLog(
      `候选生成完成：${result.data.generatedCount} 条，低置信度 ${result.data.lowConfidenceReviewQueueCount} 条`,
    )
    const refreshed = await cutCandidatesQuery.refetch()
    const latest = refreshed.data?.ok ? refreshed.data.data : undefined
    if (latest && latest.items.length > 0) {
      applyCutCandidatesToWorkspace(latest.items)
    }
  }

  const runWorkbenchAction = async (
    action: 'merge' | 'split' | 'skip' | 'rerun' | 'associate' | 'undo' | 'save_question',
  ) => {
    const sourceDocumentId = selectedSourceDocumentId.trim()
    if (!sourceDocumentId || selectedIds.length === 0) {
      return false
    }

    const result = await applyReviewWorkbenchAction({
      action,
      sourceDocumentId,
      candidateIds: selectedIds,
      assetLabel: action === 'associate' ? selectedAsset : undefined,
      reviewedBy: 'teacher_workbench',
      reason: `ui_${action}`,
    })
    if (!result.ok) {
      appendLog(`工作台操作失败：${result.error.message}`)
      return false
    }

    await cutCandidatesQuery.refetch()
    appendLog(`工作台操作完成：${teacherLabelFor(action)}，影响 ${result.data.touchedIds.length} 项`)
    if (result.data.createdQuestionId) {
      appendLog(`已保存题目：${result.data.createdQuestionId}`)
      const sourceResult = await getQuestionSources(result.data.createdQuestionId)
      if (sourceResult.ok) {
        if (sourceResult.data.sourceRegions.length === 0) {
          setSavedQuestionSourceSummary('来源回看失败：题目缺少来源区域，请先在人工接管中补齐来源区域后重试保存。')
          setSavedQuestionSourceRegions([])
        } else {
          setSavedQuestionSourceSummary(
            `来源回看成功：共 ${sourceResult.data.sourceRegions.length} 个区域，可按页码和区域继续核对。`,
          )
          setSavedQuestionSourceRegions(sourceResult.data.sourceRegions)
        }
      } else if (sourceResult.error.message.includes('HTTP 409')) {
        setSavedQuestionSourceSummary('来源回看失败：来源截图缺失，请恢复截图文件后重试。')
        setSavedQuestionSourceRegions([])
      } else if (sourceResult.error.message.includes('HTTP 403')) {
        setSavedQuestionSourceSummary('来源回看失败：当前账号无权限访问该来源，请联系管理员授权。')
        setSavedQuestionSourceRegions([])
      } else if (sourceResult.error.message.includes('HTTP 404')) {
        setSavedQuestionSourceSummary('来源回看失败：题目不存在或已不可访问，请刷新后重试。')
        setSavedQuestionSourceRegions([])
      } else {
        setSavedQuestionSourceSummary(`来源回看失败：${sourceResult.error.message}`)
        setSavedQuestionSourceRegions([])
      }
    }
    return true
  }

  const applyCutCandidatesToWorkspace = (
    items: Array<{
      id: string
      sourceRegionId: string | null
      sequenceNo: number
      segmentType: string
      confidence: number
      pageNumber: number
      textPreview: string
      failureReason: string
      takeoverAction: string
      status: string
    }>,
  ) => {
    const nextSegments = items.map((row) => ({
      id: row.id,
      title: row.textPreview
        ? row.textPreview.length > 42
          ? `${row.textPreview.slice(0, 42)}...`
          : row.textPreview
        : `候选片段 ${row.sequenceNo}`,
      page: row.pageNumber > 0 ? `第 ${row.pageNumber} 页` : '页码待确认',
      region: row.sourceRegionId ? `${row.segmentType} / 来源区域已关联` : row.segmentType,
      asset: '',
      confidence: row.confidence,
      failureReason: row.failureReason,
      takeoverAction: row.takeoverAction,
      status: row.status,
    }))

    setSegments(nextSegments)
    setSelectedIds(nextSegments.slice(0, Math.min(2, nextSegments.length)).map((x) => x.id))
    appendLog(`已加载候选 ${nextSegments.length} 条到人工确认队列`)
  }

  const loadRealExamReviewItem = useCallback(async (item: ReviewQueueItemContract) => {
    const payload = item.payload
    const requestId = ++realExamLoadRequestRef.current
    setRealExamReviewYear(payload.year)
    setSelectedRealExamPaperId(realExamPaperKey(item))
    setSelectedRealExamReviewId(item.id)
    setLoadedRealExamQuestion(null)
    setSavedQuestionSourceRegions([])
    setSavedQuestionSourceSummary(`${payload.year} 年第 ${payload.questionNo} 题来源加载中`)
    setCropDraft(null)
    setCropUndoSnapshot(null)
    setSelectedSourceDocumentId('')
    setRealExamQueueBusy(true)
    const [questionResult, sourceResult] = await Promise.all([
      getQuestion(payload.questionItemId),
      getQuestionSources(payload.questionItemId),
    ])

    if (requestId !== realExamLoadRequestRef.current) {
      return
    }
    setRealExamQueueBusy(false)

    if (!questionResult.ok) {
      setRealExamQueueMessage(`第 ${payload.questionNo} 题详情加载失败：${questionResult.error.message}，队列状态未改变`)
      return
    }

    const question = questionResult.data
    const stem = question.blocks.find((block) => block.blockType === 'stem')
    const answerBlock = question.blocks.find((block) => block.blockType === 'answer')
    const custom = question.customFields
    const textPreview = typeof stem?.content.text === 'string' ? stem.content.text : ''
    const answer = typeof answerBlock?.content.value === 'string'
      ? answerBlock.content.value
      : typeof (custom.answer as Record<string, unknown> | undefined)?.value === 'string'
        ? String((custom.answer as Record<string, unknown>).value)
        : ''
    const primaryKnowledgeLabel = typeof custom.primaryKnowledgeLabel === 'string'
      ? custom.primaryKnowledgeLabel
      : ''
    const knowledgeTags = Array.isArray(custom.knowledgeTags)
      ? custom.knowledgeTags.map(String)
      : Array.isArray(custom.abilityDimensions)
        ? custom.abilityDimensions.map(String)
        : []

    setLoadedRealExamQuestion(question)
    setRealExamRevision({
      textPreview,
      answer,
      primaryKnowledgeLabel,
      knowledgeTagsText: knowledgeTags.join(' / '),
      difficultyEstimated: question.difficultyEstimated,
    })
    setRealExamReviewNote(`${payload.year} 年第 ${payload.questionNo} 题已核对题干、答案、标签、难度和来源`)

    const sourceDocumentId = typeof custom.sourceDocumentId === 'string' ? custom.sourceDocumentId : ''
    if (sourceDocumentId) {
      setSelectedSourceDocumentId(sourceDocumentId)
    }

    if (sourceResult.ok) {
      setSavedQuestionSourceSummary(
        `${payload.year} 年第 ${payload.questionNo} 题来源回看：${sourceResult.data.sourceRegions.length} 个区域`,
      )
      setSavedQuestionSourceRegions(sourceResult.data.sourceRegions)
      const questionRegion = sourceResult.data.sourceRegions.find((region) => region.regionType.includes('question'))
        ?? sourceResult.data.sourceRegions[0]
        ?? null
      setCropDraft(questionRegion)
      setCropUndoSnapshot(null)
    } else {
      setSavedQuestionSourceSummary(`第 ${payload.questionNo} 题来源回看失败：${sourceResult.error.message}`)
      setSavedQuestionSourceRegions([])
      setCropDraft(null)
    }
    appendLog(`已载入 ${payload.year} 年真卷第 ${payload.questionNo || '?'} 题`)
  }, [appendLog])

  const loadRealExamReviewQueue = useCallback(async () => {
    setRealExamQueueBusy(true)
    const result = await getReviewQueueItems({
      status: 'open',
      reviewType: 'guangzhou_v2_question_candidate_review',
      sortBy: 'year_question_no',
      order: 'asc',
      limit: 500,
    })
    setRealExamQueueBusy(false)

    if (!result.ok) {
      setRealExamQueueMessage(`API 未连接，真实审核队列未改变。错误：${result.error.message}`)
      return
    }

    setRealExamQueue(result.data.items)
    setRealExamQueueTotal(result.data.totalCount)
    setRealExamQueueMessage(`已加载 ${result.data.items.length}/${result.data.totalCount} 条 2015-2025 真卷待复核题目`)
    const selectedStillOpen = result.data.items.find(
      (item) => item.id === selectedRealExamReviewId && item.payload.year === realExamReviewYear,
    )
    const firstInYear = result.data.items.find((item) => item.payload.year === realExamReviewYear)
    const next = selectedStillOpen ?? firstInYear ?? result.data.items[0]
    if (next) {
      await loadRealExamReviewItem(next)
    }
  }, [loadRealExamReviewItem, realExamReviewYear, selectedRealExamReviewId])

  const saveRealExamRevision = async (item: ReviewQueueItemContract) => {
    if (!loadedRealExamQuestion || loadedRealExamQuestion.id !== item.payload.questionItemId) {
      setRealExamQueueMessage('题目详情尚未加载，未执行保存')
      return false
    }

    const stem = loadedRealExamQuestion.blocks.find((block) => block.blockType === 'stem')
    const answerBlock = loadedRealExamQuestion.blocks.find((block) => block.blockType === 'answer')
    const knowledgeTags = realExamRevision.knowledgeTagsText
      .split(/[、,，/]/)
      .map((tag) => tag.trim())
      .filter(Boolean)
    const blocks = [
      ...(stem ? [{ ...stem, content: { ...stem.content, text: realExamRevision.textPreview.trim(), reviewStatus: 'pending_review' } }] : []),
      ...(answerBlock ? [{ ...answerBlock, content: { ...answerBlock.content, value: realExamRevision.answer.trim(), reviewStatus: 'pending_review' } }] : []),
    ]
    const result = await updateQuestion(item.payload.questionItemId, {
      reviewedBy: 'teacher-real-exam-workbench',
      reason: realExamReviewNote.trim() || 'ui_real_exam_revision_saved',
      difficultyEstimated: realExamRevision.difficultyEstimated ?? undefined,
      blocks,
      answer: { value: realExamRevision.answer.trim(), status: 'pending_review' },
      primaryKnowledgeLabel: realExamRevision.primaryKnowledgeLabel.trim(),
      knowledgeTags,
    })
    if (!result.ok) {
      setRealExamQueueMessage(`保存失败：${result.error.message}，当前输入仍保留，可修正后重试`)
      return false
    }

    setLoadedRealExamQuestion(result.data.question)
    setRealExamQueueMessage(`已保存 ${item.payload.year} 年第 ${item.payload.questionNo} 题修订，审计 ${result.data.auditId}`)
    appendLog(`${item.payload.year} 年第 ${item.payload.questionNo} 题修订已保存`)
    return true
  }

  const saveTeacherQuestionExtraction = async (draft: TeacherQuestionExtractionDraft) => {
    if (!loadedRealExamQuestion || !selectedRealExamReview) {
      setRealExamQueueMessage('题目详情尚未加载，未执行识别结果保存')
      return
    }

    const stem = loadedRealExamQuestion.blocks.find((block) => block.blockType === 'stem')
    if (!stem) {
      setRealExamQueueMessage('当前题目缺少题干块，未执行保存')
      return
    }
    const existingOptions = new Map(
      loadedRealExamQuestion.blocks
        .filter((block) => block.blockType === 'option')
        .map((block) => [String(block.content.label ?? '').toUpperCase(), block]),
    )
    const existingImageReview = loadedRealExamQuestion.blocks.find(
      (block) => block.blockType === 'image' && block.content.status === 'needs_separate_crop',
    )
    const answerBlock = loadedRealExamQuestion.blocks.find((block) => block.blockType === 'answer')
    const optionPatches = (['A', 'B', 'C', 'D'] as const)
      .filter((label) => draft.options[label].trim())
      .map((label, index) => {
        const existing = existingOptions.get(label)
        return {
          ...(existing ? { id: existing.id } : {}),
          blockType: 'option',
          sortOrder: stem.sortOrder + index + 1,
          sourceRegionId: existing?.sourceRegionId ?? stem.sourceRegionId,
          content: {
            ...(existing?.content ?? {}),
            label,
            text: draft.options[label].trim(),
            reviewStatus: 'pending_review',
          },
        }
      })
    const blocks = [
      {
        id: stem.id,
        blockType: 'stem',
        sortOrder: stem.sortOrder,
        sourceRegionId: stem.sourceRegionId,
        content: { ...stem.content, text: draft.stem.trim(), reviewStatus: 'pending_review' },
      },
      ...optionPatches,
      ...(answerBlock && optionPatches.length > 0 ? [{
        id: answerBlock.id,
        sortOrder: stem.sortOrder + optionPatches.length + 1,
      }] : []),
      ...(draft.visualNeedsSeparateCrop
        ? [{
          ...(existingImageReview ? { id: existingImageReview.id } : {}),
          blockType: 'image',
          sortOrder: existingImageReview?.sortOrder ?? stem.sortOrder + 10,
          sourceRegionId: existingImageReview?.sourceRegionId ?? stem.sourceRegionId,
          content: {
            ...(existingImageReview?.content ?? {}),
            status: 'needs_separate_crop',
            reviewStatus: 'pending_review',
          },
        }]
        : []),
    ]

    setRealExamExtractionSaving(true)
    const result = await updateQuestion(loadedRealExamQuestion.id, {
      reviewedBy: 'teacher-question-extraction',
      reason: 'teacher_checked_extracted_text_options_and_visual_status',
      blocks,
    })
    setRealExamExtractionSaving(false)
    if (!result.ok) {
      setRealExamQueueMessage(`识别结果保存失败：${result.error.message}，当前输入仍保留`)
      return
    }

    setLoadedRealExamQuestion(result.data.question)
    setRealExamQueueMessage(`已保存第 ${selectedRealExamReview.payload.questionNo} 题识别结果，仍在待复核队列中`)
    appendLog(`${selectedRealExamReview.payload.year} 年真卷第 ${selectedRealExamReview.payload.questionNo} 题识别结果已保存为待复核`)
  }

  const finishRealExamReviewItem = async (
    item: ReviewQueueItemContract,
    decision: 'resolved' | 'dismissed',
  ) => {
    if (!await saveRealExamRevision(item)) {
      return
    }

    const note = realExamReviewNote.trim()
    const revision = {
      textPreview: realExamRevision.textPreview.trim(),
      answer: realExamRevision.answer.trim(),
      primaryKnowledgeLabel: realExamRevision.primaryKnowledgeLabel.trim(),
      knowledgeTags: realExamRevision.knowledgeTagsText.split(/[、,，/]/).map((tag) => tag.trim()).filter(Boolean),
    }
    const result = await resolveReviewQueueItem(item.id, {
      reviewedBy: 'teacher-real-exam-workbench',
      decision,
      reason: note || (decision === 'resolved' ? 'ui_real_exam_review_confirmed' : 'ui_real_exam_review_returned'),
      revision,
    })
    if (!result.ok) {
      setRealExamQueueMessage(`${decision === 'resolved' ? '确认' : '退回'}失败：${result.error.message}；题目修订已保存，队列仍可继续处理`)
      return
    }

    setLastReviewedRealExamItem(result.data)
    setRealExamQueue((current) => current.filter((row) => row.id !== item.id))
    setRealExamQueueTotal((count) => Math.max(0, count - 1))
    setSelectedRealExamReviewId('')
    const verb = decision === 'resolved' ? '确认' : '退回'
    setRealExamQueueMessage(`已${verb} ${item.payload.year} 年第 ${item.payload.questionNo} 题；可用“撤销上次审核”恢复`)
    appendLog(`${item.payload.year} 年真卷第 ${item.payload.questionNo} 题已${verb}`)
  }

  const undoLastRealExamReview = async () => {
    if (!lastReviewedRealExamItem) {
      return
    }
    const result = await reopenReviewQueueItem(lastReviewedRealExamItem.id, {
      reviewedBy: 'teacher-real-exam-workbench',
      reason: 'ui_real_exam_review_undo',
    })
    if (!result.ok) {
      setRealExamQueueMessage(`撤销失败：${result.error.message}，可重新加载队列继续`)
      return
    }
    setLastReviewedRealExamItem(null)
    setRealExamQueueTotal((count) => count + 1)
    setRealExamQueue((current) => [...current, result.data])
    await loadRealExamReviewItem(result.data)
    setRealExamQueueMessage(`已撤销 ${result.data.payload.year} 年第 ${result.data.payload.questionNo} 题的上次审核，恢复为待复核`)
  }

  const saveRealExamRecrop = async () => {
    if (!cropDraft) {
      return
    }
    const before = savedQuestionSourceRegions.find((region) => region.id === cropDraft.id)
    if (!before) {
      return
    }
    const result = await updateSourceRegion(cropDraft.id, {
      pageNumber: cropDraft.pageNumber,
      x: cropDraft.x,
      y: cropDraft.y,
      width: cropDraft.width,
      height: cropDraft.height,
      coordinateUnit: cropDraft.coordinateUnit,
      regionType: cropDraft.regionType,
      reviewedBy: 'teacher-real-exam-workbench',
      reason: 'ui_real_exam_recrop',
    })
    if (!result.ok) {
      setRealExamQueueMessage(`重裁保存失败：${result.error.message}，坐标输入仍保留`)
      return
    }
    const updated = { ...before, ...result.data.region }
    setCropUndoSnapshot(before)
    setCropDraft(updated)
    setSavedQuestionSourceRegions((current) => current.map((region) => region.id === updated.id ? updated : region))
    setRealExamQueueMessage(`重裁已保存，审计 ${result.data.auditId}；可撤销本次重裁`)
  }

  const undoRealExamRecrop = async () => {
    if (!cropUndoSnapshot) {
      return
    }
    const snapshot = cropUndoSnapshot
    const result = await updateSourceRegion(snapshot.id, {
      pageNumber: snapshot.pageNumber,
      x: snapshot.x,
      y: snapshot.y,
      width: snapshot.width,
      height: snapshot.height,
      coordinateUnit: snapshot.coordinateUnit,
      regionType: snapshot.regionType,
      reviewedBy: 'teacher-real-exam-workbench',
      reason: 'ui_real_exam_recrop_undo',
    })
    if (!result.ok) {
      setRealExamQueueMessage(`重裁撤销失败：${result.error.message}，可重新载入来源后继续`)
      return
    }
    setCropDraft(snapshot)
    setCropUndoSnapshot(null)
    setSavedQuestionSourceRegions((current) => current.map((region) => region.id === snapshot.id ? snapshot : region))
    setRealExamQueueMessage(`已撤销本次重裁，恢复原坐标；撤销动作审计 ${result.data.auditId}`)
  }

  useEffect(() => {
    if (readyHealth?.status !== 'ok' || realExamAutoLoadStartedRef.current) {
      return
    }

    realExamAutoLoadStartedRef.current = true
    void loadRealExamReviewQueue()
  }, [loadRealExamReviewQueue, readyHealth?.status])

  const parsePaperRequest = async () => {
    setPaperWorkflowBusy(true)
    setPaperWorkflowMessage('正在生成可确认细目表...')
    const result = await createPaperBlueprintReview({
      teacherRequest: paperRequest,
      textbookVersion: '人教版八年级',
    })
    setPaperWorkflowBusy(false)

    if (!result.ok) {
      setPaperBlueprintReviewId('')
      setPaperBasketId('')
      setPaperConstraintMessage('题库服务暂时无法连接，请稍后重试；本页仍保留当前填写内容。')
      setPaperWorkflowMessage(`细目表生成失败：${result.error.message}`)
      return
    }

    const review = result.data
    setPaperBlueprintReviewId(review.id)
    setPaperBasketId(review.confirmedPaperBasketId ?? '')
    setPaperConstraintMessage(
      review.mustConfirmBeforeTakingQuestions && !review.opaqueGenerationAllowed
        ? '已生成可确认细目表；确认前不会取题，也不会生成不可解释试卷。'
        : '请先人工核对细目表约束，再继续取题。',
    )
    setPaperWorkflowMessage(`细目表已生成：${review.blueprint.length} 行，等待确认。`)
    setPaperUnderstanding({
      mode: review.mode,
      productionEligible: review.productionEligible,
      allowRealModelCalls: review.allowRealModelCalls,
      systemUnderstanding: `按当前题库生成组卷理解：${review.requestText}`,
      paperType: 'unit_practice',
      subject: review.subject,
      grade: review.grade,
      totalScore: review.totalScore,
      difficultyTarget: review.difficultyTarget,
      scope: review.scope,
      blueprint: review.blueprint,
      reviewQuestions: review.reviewQuestions,
    })
  }

  const confirmPaperBlueprint = async () => {
    if (!paperBlueprintReviewId) {
      setPaperWorkflowMessage('请先生成细目表，再确认取题。')
      return
    }

    setPaperWorkflowBusy(true)
    setPaperWorkflowMessage('正在确认细目表并保存题篮...')
    const result = await confirmPaperBlueprintReview(paperBlueprintReviewId, 'teacher-paper-workbench')
    setPaperWorkflowBusy(false)

    if (!result.ok) {
      setPaperWorkflowMessage(`确认失败：${result.error.message}`)
      setPaperConstraintMessage('题目不足或服务不可用时，请先调整细目表或补充题库。')
      return
    }

    setPaperBasketId(result.data.paperBasketId ?? '')
    setPaperWorkflowMessage(result.data.teacherMessage || `已保存题篮，包含 ${result.data.selectedQuestionCount} 题。`)
    setPaperConstraintMessage('题篮由已确认细目表生成，可继续换题、撤销和导出前审校。')
    appendLog(`已确认细目表并保存题篮：${result.data.selectedQuestionCount} 题`)
  }

  const replacePaperQuestionFromApi = async () => {
    setPaperWorkflowBusy(true)
    setPaperWorkflowMessage('正在按当前约束查找替换题...')
    const result = await replacePaperQuestion(paperDraft.currentQuestion)
    setPaperWorkflowBusy(false)

    if (!result.ok) {
      setPaperWorkflowMessage(`换题失败：${result.error.message}；原题和当前组卷内容已保留。`)
      appendLog(`换题失败，已保留原题：${result.error.message}`)
      return
    }

    setPaperDraft((current) => ({
      ...current,
      mode: result.data.mode,
      productionEligible: result.data.productionEligible,
      allowRealModelCalls: result.data.allowRealModelCalls,
      replacementQuestion: {
        ...result.data.replacement,
        difficultyEstimated:
          result.data.replacement.difficultyEstimated ?? current.currentQuestion.difficultyEstimated,
      },
      undoSnapshot: {
        undoToken: result.data.undo.undoToken,
        revertAction: result.data.undo.revertAction,
      },
      auditTrail: result.data.auditTrail,
    }))
    setPaperWorkflowMessage('已生成受约束替换题；可撤销并恢复原题。')
    appendLog('已通过真实 API 按同知识点、同题型、相近难度和同分值生成替换题')
  }

  const undoPaperReplacement = () => {
    setPaperDraft((current) => ({
      ...current,
      replacementQuestion: null,
      undoSnapshot: null,
      auditTrail: ['restored before question'],
    }))
    appendLog('已撤销换题并恢复原题')
  }

  const importScoreSheet = async (file: File) => {
    setScoreWorkflowBusy(true)
    setScoreMappingMessage(`正在读取 ${file.name} 并生成字段映射...`)
    const result = await createScoreImport(file)
    setScoreWorkflowBusy(false)

    if (!result.ok) {
      setScoreImportPreview(null)
      setScoreMappingMessage(`Excel 导入失败：${result.error.message}`)
      appendLog(`Excel 导入失败：${result.error.message}`)
      return ''
    }

    const assessmentId = result.data.assessmentId ?? ''
    setScoreImportPreview(result.data)
    setScoreMappingAssessmentId(assessmentId)
    setScoreMappingMessage(
      `${result.data.teacherMessage} 已导入 ${result.data.importedCount}/${result.data.rowCount} 行，异常 ${result.data.errorCount} 行。`,
    )
    appendLog(`已导入 Excel 成绩：${result.data.importedCount} 行，异常 ${result.data.errorCount} 行`)
    const mappingPreview = await previewScoreMappings(assessmentId, {})
    const candidates = await searchQuestions({ limit: 50, sortBy: 'question_no', order: 'asc' })
    if (candidates.ok) {
      setScoreQuestionOptions(candidates.data.items.map((item) => ({
        value: item.id,
        label: `第 ${item.questionNo ?? '?'} 题 · ${item.preview || item.questionType || '题目预览'}`,
      })))
    }
    if (mappingPreview) {
      setScoreQuestionMappings(Object.fromEntries(mappingPreview.rows.map((row) => [row.questionNo, null])))
    }
    return assessmentId
  }

  const previewScoreMappings = async (
    overrideAssessmentId?: string,
    overrideMappings: Record<string, string | null> = scoreQuestionMappings,
  ) => {
    const assessmentId = (overrideAssessmentId ?? scoreMappingAssessmentId).trim()
    if (!assessmentId) {
      setScoreMappingMessage('请先输入成绩批次 ID，再预览小题映射。')
      return null
    }

    const result = await previewItemScoreMappings({
      assessmentId,
      mappings: Object.entries(overrideMappings).map(([questionNo, questionItemId]) => ({ questionNo, questionItemId })),
    })
    if (!result.ok) {
      setScoreMappingMessage(`映射预览失败：${result.error.message}`)
      return null
    }

    setScoreMappingMessage(result.data.teacherMessage)
    setItemScoreMappingPreview({
      teacherMessage: result.data.teacherMessage,
      itemCount: result.data.itemCount,
      mappedCount: result.data.mappedCount,
      unclearCount: result.data.unclearCount,
      rows: result.data.rows.map((row) => ({
        questionNo: row.questionNo,
        scoreRecordCount: row.scoreRecordCount,
        averageScoreRate: row.averageScoreRate,
        questionPreview: row.questionPreview,
        primaryKnowledge: row.primaryKnowledge
          ? {
              title: row.primaryKnowledge.title,
              status: row.primaryKnowledge.status,
              version: row.primaryKnowledge.version,
            }
          : null,
        status: row.status,
        issueCodes: row.issueCodes,
      })),
    })
    return result.data
  }

  const generateScoreAnalysis = async () => {
    const assessmentId = scoreMappingAssessmentId.trim()
    if (!assessmentId) {
      setScoreMappingMessage('请先选择并上传 Excel 成绩表，再生成分析。')
      return
    }

    const mappingPreview = await previewScoreMappings(assessmentId)
    if (!mappingPreview) {
      return
    }
    const result = await previewScoreEvidenceAnalysis({
      assessmentId,
      containsStudentPii: false,
      mappings: Object.entries(scoreQuestionMappings).map(([questionNo, questionItemId]) => ({ questionNo, questionItemId })),
    })
    if (!result.ok) {
      setScoreEvidenceAnalysis(initialScoreEvidenceAnalysis)
      setAnalysisMessage(`证据分析失败：${result.error.message}`)
      return
    }

    setScoreEvidenceAnalysis(result.data)
    setAnalysisMessage(result.data.teacherMessage)
    appendLog(result.data.status === 'ready' ? '已生成成绩证据分析预览' : '成绩证据分析已按门禁阻断')
  }

  const exportScoreReport = async () => {
    const assessmentId = scoreMappingAssessmentId.trim()
    if (!assessmentId) {
      setCommentaryReportPreview({
        ...initialCommentaryReportPreview,
        teacherMessage: '请先输入成绩批次 ID，再导出讲评报告草稿。',
        status: 'blocked',
      })
      return
    }

    const result = await exportCommentaryReport({
      assessmentId,
      format: 'md',
      allowAiDraftText: false,
      mappings: [
        ...Object.entries(scoreQuestionMappings).map(([questionNo, questionItemId]) => ({ questionNo, questionItemId })),
      ],
    })
    if (!result.ok) {
      setCommentaryReportPreview({
        ...initialCommentaryReportPreview,
        teacherMessage: `讲评报告暂未生成：${result.error.message}`,
        status: 'blocked',
      })
      return
    }

    setCommentaryReportPreview({
      teacherMessage: result.data.teacherMessage,
      status: result.data.status,
      artifactPath: result.data.artifactPath ?? '',
      manifestSha256: result.data.manifestSha256 ?? '',
      sections: result.data.sections,
    })
  }

  const handleScoreWorkbenchAction = (action: string) => {
    if (action === 'generate-score-analysis') {
      void generateScoreAnalysis()
      return
    }

    if (action === 'export-score-report') {
      void exportScoreReport()
    }
  }

  const openAnalysisSummary = () => {
    setAnalysisMessage(
      commentaryReportPreview.status === 'ready'
        ? `讲评摘要已生成：${commentaryReportPreview.sections.map((section) => section.title).join('、')}`
        : scoreEvidenceAnalysis.teacherMessage,
    )
    appendLog('已打开讲评摘要')
  }

  const addEvidenceQuestionToPaperDraft = (card: QuestionEvidenceCardContract) => {
    setPaperDraft((current) => ({
      ...current,
      currentQuestion: paperDraftQuestionFor(card),
      replacementQuestion: null,
      undoSnapshot: null,
      auditTrail: [],
    }))
  }

  const runStarterDemo = (step: StarterDemoStep) => {
    openTeacherView(step.view)
    if (step.view === 'scores') {
      setScoreMappingMessage('已切到成绩工作台，可点击“上传 Excel”选择本机成绩表。')
    }
    if (step.view === 'analysis') {
      openAnalysisSummary()
    }
    if (step.view === 'paper') {
      setPaperWorkflowMessage('已载入默认组卷需求，点击“生成理解”查看细目表。')
    }
    appendLog(`已打开新手示例：${step.title}`)
  }

  const exportPaper = async (format: 'docx' | 'pdf') => {
    if (!paperBasketId) {
      setPaperWorkflowMessage('请先确认细目表并保存题篮，再导出试卷。')
      return
    }
    setPaperWorkflowBusy(true)
    const result = await downloadPaperArtifact(paperBasketId, format)
    setPaperWorkflowBusy(false)
    if (!result.ok) {
      setPaperWorkflowMessage(`导出被阻断：${result.error.message}`)
      appendLog(`${format.toUpperCase()} 导出失败：${result.error.message}`)
      return
    }
    const url = URL.createObjectURL(result.data.blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = result.data.fileName
    anchor.click()
    URL.revokeObjectURL(url)
    setPaperWorkflowMessage(`${result.data.fileName} 已生成并开始下载。`)
    appendLog(`已下载真实 ${format.toUpperCase()} 试卷工件`)
  }

  return (
    <ConfigProvider
      theme={{
        token: {
          borderRadius: 6,
          colorPrimary: '#23705a',
          colorInfo: '#23705a',
          colorBgLayout: '#f5f7f4',
          fontFamily:
            '"Noto Sans SC", "Microsoft YaHei UI", "Microsoft YaHei", sans-serif',
        },
      }}
    >
      <Layout className="shell">
        <header className="topbar">
          <div>
            <Typography.Text className="eyebrow">K12 Question Graph</Typography.Text>
            <Typography.Title level={1}>校本题谱</Typography.Title>
          </div>
          <Space size="small" wrap>
            <Tag color="green">本机可用</Tag>
            <Tag>初中物理</Tag>
            <Tag data-contract="server-state-query-boundary">
              服务状态 {readyHealthStatusLabel}
            </Tag>
            <Button
              size="small"
              onClick={toggleAdminWorkspace}
              aria-expanded={adminWorkspaceVisible}
              data-action="toggle-admin-governance-panels"
              data-contract="admin-governance-entry"
            >
              {adminWorkspaceVisible ? '收起管理员入口' : '管理员调试入口'}
            </Button>
          </Space>
        </header>

        <main className={`workspace teacher-view-${activeTeacherView}`}>
          <section
            className="primary-panel"
            aria-label="普通教师入口"
            data-flow="teacher-home"
            data-contract="four-default-actions"
          >
            <TeacherHomePanelContent
              activeTeacherView={activeTeacherView}
              onOpenTeacherView={openTeacherView}
              onRunStarterDemo={runStarterDemo}
            />
          </section>

          <section className="status-panel" aria-label="系统状态">
            <div className="status-strip">
              <div>
                <Typography.Text type="secondary">导入向导</Typography.Text>
                <Typography.Title level={3}>4 步</Typography.Title>
              </div>
              <Badge status="processing" text="可继续" />
            </div>

            <Alert
              showIcon
              type={readyHealth?.status === 'ok' ? 'info' : 'warning'}
              title={readyHealth?.status === 'ok' ? '可以开始处理' : 'API 未连接'}
              description={
                readyHealth?.status === 'ok'
                  ? '上传后会显示处理进度；失败时保留原文件，可继续人工处理。'
                  : '当前只能看本地证据预览；需要启动 5275 API 后才能加载数据库队列、确认或退回真卷题目。'
              }
            />

            <div className="real-exam-hero" data-contract="real-guangzhou-2015-primary-workbench" data-workflow="guangzhou-physics-2015-2025-v2">
              <div className="real-exam-hero-head">
                <div>
                  <Typography.Text type="secondary">2015-2025 广州中考物理</Typography.Text>
                  <Typography.Title level={2}>真题浏览与复核</Typography.Title>
                </div>
                <Space size="small" wrap>
                  <Tag color={realExamQueue.length > 0 ? 'green' : 'orange'}>
                    {realExamQueue.length > 0 ? '题目已载入' : '正在载入题目'}
                  </Tag>
                  <Tag>{realExamQueue.length > 0 ? `${realExamQueueTotal} 题` : '本地预览'}</Tag>
                </Space>
              </div>

              <div className="real-exam-navigation" aria-label="真卷选择">
                <label>
                  <span>年份</span>
                  <Select
                    aria-label="真卷年份"
                    value={realExamReviewYear}
                    options={realExamYearOptions}
                    onChange={(year) => {
                      setRealExamReviewYear(year)
                      const next = realExamQueue.find((item) => item.payload.year === year)
                      setSelectedRealExamPaperId(next ? realExamPaperKey(next) : `${year}:primary-paper`)
                      if (next) void loadRealExamReviewItem(next)
                    }}
                  />
                </label>
                <label>
                  <span>试卷</span>
                  <Select
                    aria-label="真卷试卷"
                    value={activeRealExamPaperId}
                    options={realExamPaperOptions}
                    onChange={(paperId) => {
                      setSelectedRealExamPaperId(paperId)
                      const next = realExamQueue.find(
                        (item) => item.payload.year === realExamReviewYear && realExamPaperKey(item) === paperId,
                      )
                      if (next) void loadRealExamReviewItem(next)
                    }}
                  />
                </label>
                <label>
                  <span>题号</span>
                  <Select
                    aria-label="真卷题号"
                    value={selectedRealExamReview?.id}
                    options={realExamQuestionOptions}
                    placeholder="选择题号"
                    onChange={(reviewId) => {
                      const next = visibleRealExamQueue.find((item) => item.id === reviewId)
                      if (next) void loadRealExamReviewItem(next)
                    }}
                  />
                </label>
              </div>

              <div className="real-exam-focus">
                <div className="real-exam-question">
                  <span className="real-exam-number">第 {selectedRealExamPreview.questionNo || '?'} 题</span>
                  {selectedQuestionAssetRegions.length > 0 ? (
                    <div className="real-exam-original-question" aria-label="完整原题" data-contract="question-visual-source-of-truth">
                      {selectedQuestionAssetRegions.map((region) => (
                        <a
                          key={region.id}
                          className="real-exam-question-page"
                          href={region.screenshotUrl ?? undefined}
                          target="_blank"
                          rel="noreferrer"
                        >
                          <img
                            src={region.screenshotUrl ?? undefined}
                            alt={`第 ${selectedRealExamPreview.questionNo || '?'} 题完整原题，第 ${region.pageNumber} 页`}
                            loading="eager"
                          />
                        </a>
                      ))}
                    </div>
                  ) : (
                    <Alert
                      type="warning"
                      showIcon
                      title="完整原题正在载入"
                      description="题目裁图可用后会在这里显示。"
                    />
                  )}
                  <TeacherQuestionExtractionPanel
                    question={loadedRealExamQuestion}
                    sourceRegions={savedQuestionSourceRegions}
                    saving={realExamExtractionSaving}
                    onSave={(draft) => void saveTeacherQuestionExtraction(draft)}
                  />
                  <details className="real-exam-search-text">
                    <summary>原始辅助文本（仅供对照）</summary>
                    <div className="question-text" aria-label="辅助题干文本">
                      {splitQuestionText(selectedRealExamPreview.textPreview).map((line, index) => (
                        <p key={`${selectedRealExamPreview.questionNo}-${index}`}>
                          {renderMathAwareText(line)}
                        </p>
                      ))}
                    </div>
                  </details>
                  <div className="real-exam-answer">
                    <Typography.Text type="secondary">参考答案</Typography.Text>
                    <strong>{selectedRealExamPreview.answer || '待核对'}</strong>
                  </div>
                  <div className="real-exam-tags">
                    <Tag color="blue">{selectedRealExamPreview.primaryKnowledgeLabel || '标签待确认'}</Tag>
                    {selectedRealExamPreview.knowledgeTags.map((tag) => (
                      <Tag key={tag}>{tag}</Tag>
                    ))}
                  </div>
                </div>
                {adminWorkspaceVisible ? (
                <div className="real-exam-source-preview" aria-label="题图与来源区域">
                  <div className="source-preview-head">
                    <strong>来源回看</strong>
                    <Tag color={savedQuestionSourceRegions.some(hasRenderableImage) ? 'green' : 'default'}>
                      {savedQuestionSourceRegions.some(hasRenderableImage)
                        ? '有来源图片'
                        : '暂无可显示图片'}
                    </Tag>
                  </div>
                  <div className="source-preview-list">
                    {savedQuestionSourceRegions.length > 0 ? (
                      [...savedQuestionSourceRegions]
                        .sort((left, right) => sourceRegionRank(left.regionType) - sourceRegionRank(right.regionType))
                        .map((region) => (
                        <span key={region.id} className={hasRenderableImage(region) ? 'source-preview-card has-image' : 'source-preview-card'}>
                          <strong>
                            第 {region.pageNumber} 页 · {formatRegionKind(region.regionType)}
                          </strong>
                          {hasRenderableImage(region) ? (
                            <span className="source-preview-image-frame">
                              <img
                                src={region.screenshotUrl ?? undefined}
                                alt={`第 ${region.pageNumber} 页 ${formatRegionKind(region.regionType)}`}
                                loading="lazy"
                              />
                            </span>
                          ) : null}
                          <span className="source-preview-actions">
                            {region.screenshotUrl ? (
                              <Button size="small" href={region.screenshotUrl} target="_blank" rel="noreferrer">
                                打开裁图
                              </Button>
                            ) : null}
                            {region.pageScreenshotUrl ? (
                              <Button size="small" href={region.pageScreenshotUrl} target="_blank" rel="noreferrer">
                                查看第 {region.pageNumber} 页
                              </Button>
                            ) : null}
                          </span>
                          <small>
                            {region.sourceTitle ?? '来源文档'} · {region.regionType} ·{' '}
                            {region.screenshotRelativePath ?? '未生成截图'}
                          </small>
                        </span>
                      ))
                    ) : (
                      <span>
                        <strong>未加载来源区域</strong>
                        <small>点击“加载数据库队列”后显示题干和答案来源。</small>
                      </span>
                    )}
                  </div>
                  <Typography.Text type="secondary">{savedQuestionSourceSummary}</Typography.Text>
                </div>
                ) : null}
                <div className="real-exam-actions">
                  <Button
                    icon={<FileSearchOutlined />}
                    onClick={loadRealExamReviewQueue}
                    loading={realExamQueueBusy}
                    data-action="load-real-guangzhou-2015-review-queue-primary"
                  >
                    刷新题目
                  </Button>
                  <Button
                    type="primary"
                    icon={<EditOutlined />}
                    onClick={() =>
                      selectedRealExamReview
                        ? void finishRealExamReviewItem(selectedRealExamReview, 'resolved')
                        : setRealExamQueueMessage('题目尚未载入，请稍后刷新。')
                    }
                    disabled={!selectedRealExamReview}
                    data-action="confirm-real-guangzhou-2015-review-item-primary"
                  >
                    确认无误
                  </Button>
                  <Button
                    icon={<UndoOutlined />}
                    onClick={() =>
                      selectedRealExamReview
                        ? void finishRealExamReviewItem(selectedRealExamReview, 'dismissed')
                        : setRealExamQueueMessage('题目尚未载入，请稍后刷新。')
                    }
                    disabled={!selectedRealExamReview}
                    data-action="dismiss-real-guangzhou-2015-review-item-primary"
                  >
                    退回修正
                  </Button>
                  <Typography.Text type="secondary">{realExamQueueMessage}</Typography.Text>
                </div>
              </div>

              <div className="real-exam-strip" aria-label={`${realExamReviewYear} 年广州中考题目列表`}>
                {realExamPreviewRows.slice(0, 24).map((item) => {
                  const active = selectedRealExamReview
                    ? selectedRealExamReview.payload.questionNo === item.questionNo
                    : selectedEvidenceQuestionNo === item.questionNo
                  const liveItem = visibleRealExamQueue.find((row) => row.payload.questionNo === item.questionNo)
                  return (
                    <button
                      key={`${item.questionNo}-${item.answer}`}
                      type="button"
                      className={active ? 'real-exam-chip active' : 'real-exam-chip'}
                      onClick={() =>
                        liveItem ? void loadRealExamReviewItem(liveItem) : selectEvidenceQuestion(item)
                      }
                    >
                      <strong>{item.questionNo}</strong>
                      <span>{item.primaryKnowledgeLabel}</span>
                      <small>答案 {item.answer || '-'}</small>
                    </button>
                  )
                })}
              </div>
            </div>

            <div className="import-wizard" data-flow="paper-import-wizard">
              {importWizardSteps.map(([title, detail], index) => (
                <div className="import-step" key={title} data-contract={`import-step-${index + 1}`}>
                  <strong>{index + 1}</strong>
                  <span>
                    <Typography.Text>{title}</Typography.Text>
                    <small>{detail}</small>
                  </span>
                </div>
              ))}
            </div>

            <button
              ref={uploadDropzoneRef}
              className="upload-dropzone"
              type="button"
              data-action="upload-paper"
              disabled={importUploadBusy}
              onClick={() => uploadInputRef.current?.click()}
            >
              <input
                ref={uploadInputRef}
                type="file"
                accept=".pdf,.docx,.png,.jpg,.jpeg"
                hidden
                onChange={(event) => {
                  const file = event.currentTarget.files?.[0]
                  event.currentTarget.value = ''
                  if (file) {
                    void handlePaperUploadFile(file)
                  }
                }}
              />
              <CloudUploadOutlined />
              <span>
                <strong>{importUploadBusy ? '正在处理' : '上传试卷'}</strong>
                <small>选择文件后自动上传、解析并生成切题候选。</small>
              </span>
            </button>

            {adminWorkspaceVisible ? (
            <>
            <div className="score-field-mapping" data-contract="s003b-source-materials-query">
              <Typography.Text type="secondary">来源资料（真实 API）</Typography.Text>
              <Space size="small" wrap>
                <Button
                  type={sourceTypeFilter === 'all' ? 'primary' : 'default'}
                  onClick={() => setSourceTypeFilter('all')}
                >
                  全部
                </Button>
                <Button
                  type={sourceTypeFilter === 'textbook' ? 'primary' : 'default'}
                  onClick={() => setSourceTypeFilter('textbook')}
                >
                  textbook
                </Button>
                <Button
                  type={sourceTypeFilter === 'local_exam_paper' ? 'primary' : 'default'}
                  onClick={() => setSourceTypeFilter('local_exam_paper')}
                >
                  local_exam_paper
                </Button>
              </Space>
              <div className="review-summary">
                <span>
                  <Typography.Text type="secondary">查询状态</Typography.Text>
                  <strong>{sourceMaterialsQuery.isLoading ? '加载中' : '已加载'}</strong>
                </span>
                <span>
                  <Typography.Text type="secondary">来源条数</Typography.Text>
                  <strong>{sourceMaterials.length}</strong>
                </span>
              </div>
              <Space.Compact block>
                <Input
                  value={selectedSourceDocumentId}
                  onChange={(event) => setSelectedSourceDocumentId(event.target.value)}
                  placeholder="输入 SourceDocumentId 查询预览"
                  data-action="lookup-source-preview"
                />
                <Button onClick={() => previewQuery.refetch()} disabled={!selectedSourceDocumentId.trim()}>
                  查询预览
                </Button>
              </Space.Compact>
              <Space size="small" wrap>
                <Button
                  type="primary"
                  onClick={runCutCandidateGeneration}
                  disabled={!selectedSourceDocumentId.trim()}
                  data-action="generate-cut-candidates"
                >
                  生成候选
                </Button>
                <Button
                  onClick={() => cutCandidatesQuery.refetch()}
                  disabled={!selectedSourceDocumentId.trim()}
                  data-action="load-cut-candidates"
                >
                  查询候选
                </Button>
                <Button
                  onClick={() =>
                    cutCandidates?.items.length
                      ? applyCutCandidatesToWorkspace(cutCandidates.items)
                      : appendLog('当前没有可加载的候选，请先生成或查询')
                  }
                  disabled={!selectedSourceDocumentId.trim()}
                  data-action="apply-cut-candidates"
                >
                  应用候选
                </Button>
              </Space>
            </div>

            <RealExamReviewWorkbench
              queue={realExamQueue}
              queueTotal={realExamQueueTotal}
              queueBusy={realExamQueueBusy}
              queueMessage={realExamQueueMessage}
              reviewYear={realExamReviewYear}
              selectedReviewId={selectedRealExamReviewId}
              selectedReview={selectedRealExamReview}
              visibleQueue={visibleRealExamQueue}
              revision={realExamRevision}
              cropDraft={cropDraft}
              cropUndoAvailable={Boolean(cropUndoSnapshot)}
              loadedQuestionAvailable={Boolean(loadedRealExamQuestion)}
              lastReviewedAvailable={Boolean(lastReviewedRealExamItem)}
              sourceSummary={savedQuestionSourceSummary}
              reviewNote={realExamReviewNote}
              onYearChange={(year) => {
                setRealExamReviewYear(year)
                const next = realExamQueue.find((item) => item.payload.year === year)
                if (next) void loadRealExamReviewItem(next)
              }}
              onRevisionChange={(patch) => setRealExamRevision((current) => ({ ...current, ...patch }))}
              onCropChange={(field, value) =>
                setCropDraft((current) => current ? { ...current, [field]: value } : current)
              }
              onSaveCrop={() => void saveRealExamRecrop()}
              onUndoCrop={() => void undoRealExamRecrop()}
              onReviewNoteChange={setRealExamReviewNote}
              onLoadQueue={() => void loadRealExamReviewQueue()}
              onLoadSelected={() =>
                selectedRealExamReview
                  ? void loadRealExamReviewItem(selectedRealExamReview)
                  : setRealExamQueueMessage('请先选择一题')
              }
              onSaveSelected={() => {
                if (selectedRealExamReview) void saveRealExamRevision(selectedRealExamReview)
              }}
              onConfirmSelected={() =>
                selectedRealExamReview
                  ? void finishRealExamReviewItem(selectedRealExamReview, 'resolved')
                  : setRealExamQueueMessage('请先选择一题')
              }
              onDismissSelected={() =>
                selectedRealExamReview
                  ? void finishRealExamReviewItem(selectedRealExamReview, 'dismissed')
                  : setRealExamQueueMessage('请先选择一题')
              }
              onUndoLastReview={() => void undoLastRealExamReview()}
              onSelectReview={(item) => void loadRealExamReviewItem(item)}
            />
            <div className="score-field-mapping" data-contract="s003b-import-job-query">
              <Typography.Text type="secondary">导入任务状态（真实 API）</Typography.Text>
              <Space.Compact block>
                <Input
                  value={importJobLookupId}
                  onChange={(event) => setImportJobLookupId(event.target.value)}
                  placeholder="输入 ImportJobId"
                  data-action="lookup-import-job"
                />
                <Button onClick={() => importJobQuery.refetch()} disabled={!importJobLookupId.trim()}>
                  查询任务
                </Button>
              </Space.Compact>
              <div className="review-summary">
                <span>
                  <Typography.Text type="secondary">任务状态</Typography.Text>
                  <strong>{importJob?.status ?? '未查询'}</strong>
                </span>
                <span>
                  <Typography.Text type="secondary">错误码</Typography.Text>
                  <strong>{importJob?.lastErrorCode ?? '-'}</strong>
                </span>
              </div>
            </div>
            </>
            ) : null}

            <div className="job-list">
              {jobStates.map((state) => (
                <div className="job-row" key={state.label}>
                  <span>{state.label}</span>
                  <Progress
                    percent={state.value}
                    size="small"
                    showInfo={false}
                    strokeColor="#23705a"
                  />
                  <strong>{state.value}</strong>
                </div>
              ))}
            </div>

            {adminWorkspaceVisible ? (
            <div className="score-analysis-summary" data-contract="s003d-import-efficiency">
              <Typography.Text type="secondary">导入效率摘要</Typography.Text>
              <div className="analysis-summary-grid compact">
                <span>
                  <strong>{importElapsedMinutes} 分钟</strong>
                  <small>上传到当前耗时</small>
                </span>
                <span>
                  <strong>{importActionCount}</strong>
                  <small>关键操作次数</small>
                </span>
                <span>
                  <strong>{failureTakeoverCount}</strong>
                  <small>失败接管次数</small>
                </span>
              </div>
              <Typography.Text type="secondary">证据摘要（S003D）</Typography.Text>
              <pre aria-label="s003d-evidence-summary">{s003dEvidenceSummary}</pre>
            </div>
            ) : null}
          </section>

          <section className="score-panel" aria-label="成绩导入" data-flow="score-import-workbench">
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>成绩导入分析工作台</Typography.Title>
                <Typography.Text type="secondary">
                  Excel 字段映射、异常行、知识点分析和报告导出在同一屏完成。
                </Typography.Text>
              </div>
              <Space size="small" wrap>
                <Tag color="green" data-contract="local-score-xlsx">
                  本机 Excel
                </Tag>
                <Tag data-contract="score-productionEligible=false">
                  正式启用前预览
                </Tag>
              </Space>
            </div>
            <ScoreWorkbenchPanelContent
              scoreWorkflowBusy={scoreWorkflowBusy}
              scoreMappingAssessmentId={scoreMappingAssessmentId}
              onScoreMappingAssessmentIdChange={setScoreMappingAssessmentId}
              scoreMappingMessage={scoreMappingMessage}
              itemScoreMappingPreview={itemScoreMappingPreview}
              commentaryReportPreview={commentaryReportPreview}
              scoreImportPreview={scoreImportPreview}
              scoreQuestionMappings={scoreQuestionMappings}
              scoreQuestionOptions={scoreQuestionOptions}
              onScoreQuestionMappingChange={(questionNo, questionItemId) =>
                setScoreQuestionMappings((current) => ({ ...current, [questionNo]: questionItemId }))
              }
              onUploadScoreSheet={(file) => void importScoreSheet(file)}
              onHandleScoreWorkbenchAction={handleScoreWorkbenchAction}
              onPreviewScoreMappings={() => void previewScoreMappings()}
            />
          </section>

          <section className="analysis-panel" aria-label="讲评分析" data-flow="teacher-analysis-workbench">
            <AnalysisPanelContent
              analysisMessage={analysisMessage}
              analysis={scoreEvidenceAnalysis}
              onOpenAnalysisSummary={openAnalysisSummary}
            />
          </section>

          <PaperWorkbenchPanels
            paperBasketId={paperBasketId}
            paperConstraintMessage={paperConstraintMessage}
            paperBlueprintReviewId={paperBlueprintReviewId}
            paperWorkflowBusy={paperWorkflowBusy}
            paperWorkflowMessage={paperWorkflowMessage}
            paperRequest={paperRequest}
            paperUnderstanding={paperUnderstanding}
            paperDraft={paperDraft}
            questionEvidenceSearch={questionEvidenceSearch}
            questionEvidenceSearchError={questionEvidenceSearchQuery.data?.ok === false}
            questionEvidenceSearchFetching={questionEvidenceSearchQuery.isFetching}
            questionEvidenceMode={questionEvidenceMode}
            activeEvidenceFilter={activeEvidenceFilter}
            questionInteractionMessage={questionInteractionMessage}
            selectedEvidenceQuestionId={selectedEvidenceQuestionId}
            onPaperRequestChange={setPaperRequest}
            onParsePaperRequest={parsePaperRequest}
            onConfirmPaperBlueprint={confirmPaperBlueprint}
            onRefreshQuestionEvidence={() => questionEvidenceSearchQuery.refetch()}
            onEvidenceModeChange={changeQuestionEvidenceMode}
            onApplyEvidenceFilter={applyEvidenceFilter}
            onClearEvidenceFilters={clearEvidenceFilters}
            onSelectEvidenceQuestion={(card) => selectQuestionEvidenceCard(card, addEvidenceQuestionToPaperDraft)}
            onOpenQuestionSource={(card, sourceKind) => void openQuestionEvidenceSource(card, sourceKind)}
            onReturnToBasket={() => returnToQuestionBasket(Boolean(paperBasketId))}
            onReplacePaperQuestion={() => void replacePaperQuestionFromApi()}
            onUndoPaperReplacement={undoPaperReplacement}
            onExportPaper={exportPaper}
          />

          {adminWorkspaceVisible ? (
          <section
            className="review-panel"
            aria-label="导入确认"
            data-flow="manual-review"
            data-contract="import-wizard-review"
          >
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>异常确认与来源回看</Typography.Title>
                <Typography.Text type="secondary">
                  处理跨页、误切和共用题图，只记录必要修正。
                </Typography.Text>
              </div>
              <Tag color="green">B004</Tag>
            </div>

            <div className="review-workspace">
              <div className="page-preview" aria-label="来源页预览" data-contract="source-review">
                <div className="review-summary" data-contract="s003c-source-preview-state">
                  <span>
                    <Typography.Text type="secondary">预览状态</Typography.Text>
                    <strong>
                      {previewQuery.isLoading
                        ? '加载中'
                        : previewQuery.isError
                          ? '加载失败'
                          : sourcePreview
                            ? '已加载'
                            : '未查询'}
                    </strong>
                  </span>
                  <span>
                    <Typography.Text type="secondary">页数</Typography.Text>
                    <strong>{sourcePreview?.pages.length ?? 0}</strong>
                  </span>
                  <span>
                    <Typography.Text type="secondary">区域数</Typography.Text>
                    <strong>
                      {sourcePreview ? sourcePreview.pages.reduce((sum, page) => sum + page.regions.length, 0) : 0}
                    </strong>
                  </span>
                </div>
                <div className="source-review-cards">
                  {segments.slice(0, 3).map((segment) => (
                    <button
                      className="source-review-card"
                      type="button"
                      key={segment.id}
                      onClick={() => toggleSegment(segment.id)}
                    >
                      <strong>{segment.title}</strong>
                      <span>{segment.page}</span>
                      <small>{segment.region}</small>
                      <Tag color={segment.asset ? 'green' : undefined}>
                        {segment.asset || '未关联题图'}
                      </Tag>
                    </button>
                  ))}
                </div>
              </div>

              <div className="review-queue">
                <div className="review-summary" data-contract="review-queue-summary">
                  <span>
                    <Typography.Text type="secondary">待确认</Typography.Text>
                    <strong>{segments.length}</strong>
                  </span>
                  <span>
                    <Typography.Text type="secondary">已选择</Typography.Text>
                    <strong>{selectedIds.length}</strong>
                  </span>
                  <span>
                    <Typography.Text type="secondary">预计处理</Typography.Text>
                    <strong>8 分钟</strong>
                  </span>
                  <span>
                    <Typography.Text type="secondary">低置信度</Typography.Text>
                    <strong>{segments.filter((segment) => segment.takeoverAction === 'manual_review').length}</strong>
                  </span>
                </div>

                <div className="review-toolbar" aria-label="人工确认操作">
                  <Button icon={<SearchOutlined />} onClick={selectExceptionItems} data-action="filter-exceptions">
                    只看异常
                  </Button>
                  <Button
                    icon={<MergeCellsOutlined />}
                    onClick={mergeSelected}
                    disabled={selectedSegments.length < 2}
                    data-action="merge"
                  >
                    合并
                  </Button>
                  <Button
                    icon={<SplitCellsOutlined />}
                    onClick={splitSelected}
                    disabled={selectedSegments.length !== 1}
                    data-action="split"
                  >
                    拆分
                  </Button>
                  <select
                    value={selectedAsset}
                    onChange={(event) => setSelectedAsset(event.target.value)}
                    aria-label="共用题图"
                  >
                    {sharedAssets.map((asset) => (
                      <option key={asset} value={asset}>
                        {asset}
                      </option>
                    ))}
                  </select>
                  <Button
                    icon={<LinkOutlined />}
                    onClick={associateAsset}
                    disabled={selectedIds.length === 0}
                    data-action="associate"
                  >
                    关联
                  </Button>
                  <Button icon={<UndoOutlined />} onClick={undoLast} data-action="undo">
                    撤销
                  </Button>
                  <Button
                    type="primary"
                    icon={<CheckCircleOutlined />}
                    onClick={batchConfirmSelected}
                    disabled={selectedIds.length === 0}
                    data-action="batch-confirm"
                  >
                    批量确认
                  </Button>
                </div>

                <div className="segment-list" aria-label="题目片段">
                  {segments.map((segment) => {
                    const active = selectedIds.includes(segment.id)
                    return (
                      <button
                        type="button"
                        className={active ? 'segment-row active' : 'segment-row'}
                        key={segment.id}
                        onClick={() => toggleSegment(segment.id)}
                      >
                        <span>
                          <strong>{segment.title}</strong>
                          <small>
                            {segment.page} · {segment.region} · {teacherDifficultyLabelFor(segment.confidence)}
                          </small>
                          {segment.failureReason ? <small>失败原因：{segment.failureReason}</small> : null}
                        </span>
                        <Tag color={segment.asset ? 'green' : undefined}>
                          {segment.asset || '未关联题图'}
                        </Tag>
                        <Tag color={segment.takeoverAction === 'manual_review' ? 'orange' : 'green'}>
                          {segment.takeoverAction === 'manual_review' ? '需人工接管' : teacherLabelFor(segment.takeoverAction)}
                        </Tag>
                      </button>
                    )
                  })}
                </div>

                <Divider />

                <div className="revision-log" aria-label="修订记录">
                  <Typography.Text type="secondary">修订记录</Typography.Text>
                  {actionLog.length === 0 ? (
                    <Typography.Text>暂无修正</Typography.Text>
                  ) : (
                    actionLog.map((item) => <Typography.Text key={item.id}>{item.message}</Typography.Text>)
                  )}
                </div>

                <div className="revision-log" aria-label="保存后来源回看" data-contract="s006c-source-review">
                  <Typography.Text type="secondary">保存后来源回看</Typography.Text>
                  <Typography.Text>{savedQuestionSourceSummary}</Typography.Text>
                  {savedQuestionSourceRegions.slice(0, 3).map((region) => (
                    <Typography.Text key={region.id}>
                      {`第 ${region.pageNumber} 页 · ${region.regionType} · ${
                        region.screenshotRelativePath ?? '无截图路径'
                      }`}
                    </Typography.Text>
                  ))}
                </div>

                <div
                  className="failure-takeover"
                  aria-label="失败接管"
                  data-flow="failure-takeover"
                >
                  <Alert
                    showIcon
                    type="warning"
                    title="解析器失败可人工接管"
                    description="保留原始文件、来源区域和诊断信息，教师继续处理当前导入。"
                  />
                  <div className="diagnostics-row">
                    <Tag data-diagnostic="adapter_failed">解析器失败</Tag>
                    <Typography.Text type="secondary">
                      诊断：版面块解析超时
                    </Typography.Text>
                  </div>
                  <div className="takeover-actions">
                    <Button onClick={() => takeoverFailure('框选区域')} data-action="manual-box">
                      框选
                    </Button>
                    <Button onClick={splitSelected} data-action="takeover-split">
                      拆分
                    </Button>
                    <Button onClick={mergeSelected} data-action="takeover-merge">
                      合并
                    </Button>
                    <Button onClick={() => takeoverFailure('跳过当前页')} data-action="skip-page">
                      跳过
                    </Button>
                    <Button onClick={() => takeoverFailure('重跑解析器')} data-action="rerun-adapter">
                      重跑
                    </Button>
                  </div>
                </div>
              </div>
            </div>
          </section>
          ) : null}

        </main>
        {adminWorkspaceVisible ? (
          <aside
            className="admin-workspace is-open"
            data-shell="admin-governance-staging"
            data-contract="admin-governance-reachable"
            aria-hidden={false}
          >
            <Suspense fallback={<div className="admin-workspace-loading">正在加载管理员治理面板…</div>}>
              <AdminGovernancePanels />
            </Suspense>
          </aside>
        ) : (
          <aside
            className="admin-workspace"
            data-shell="admin-governance-staging"
            aria-hidden="true"
          />
        )}
      </Layout>
    </ConfigProvider>
  )
}

export default App
