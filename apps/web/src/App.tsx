import { useEffect, useMemo, useRef, useState } from 'react'
import {
  Alert,
  Badge,
  Button,
  ConfigProvider,
  Divider,
  Input,
  Layout,
  Progress,
  Space,
  Tag,
  Typography,
} from 'antd'
import {
  BarChartOutlined,
  CheckCircleOutlined,
  CloudUploadOutlined,
  FileSearchOutlined,
  FileTextOutlined,
  InboxOutlined,
  LinkOutlined,
  MergeCellsOutlined,
  SearchOutlined,
  SplitCellsOutlined,
  SwapOutlined,
  UndoOutlined,
} from '@ant-design/icons'
import './App.css'
import { apiContractSnapshot } from './api/contracts'
import {
  applyReviewWorkbenchAction,
  confirmPaperBlueprintReview,
  createPaperBlueprintReview,
  exportCommentaryReport,
  generateCutCandidates,
  getCutCandidates,
  getQuestionSources,
  getReviewQueueItems,
  previewItemScoreMappings,
  resolveReviewQueueItem,
  runDocumentWorkerSmoke,
  uploadImportFile,
} from './api/client'
import type { ReviewQueueItemContract } from './api/contracts'
import {
  useCutCandidatesQuery,
  useImportJobQuery,
  useReadyHealthQuery,
  useQuestionSearchQuery,
  useSourceMaterialsQuery,
  useSourcePreviewQuery,
} from './api/queries'
import { uiStateBoundary } from './state/uiState'
import { AdminGovernancePanels } from './ui/AdminGovernancePanels'
import {
  teacherDifficultyLabelFor,
  teacherDifficultyRangeLabelFor,
  teacherLabelFor,
} from './ui/teacherLabels'

type TeacherView = 'import' | 'paper' | 'scores' | 'analysis'

const teacherActions = [
  {
    title: '导入试卷',
    description: '上传文件，只处理异常项',
    icon: <CloudUploadOutlined />,
    view: 'import' as TeacherView,
    status: '常用',
  },
  {
    title: '找题组卷',
    description: '找题、换题、导出样卷',
    icon: <FileSearchOutlined />,
    view: 'paper' as TeacherView,
    status: '10 分钟目标',
  },
  {
    title: '导入成绩',
    description: '上传 Excel，复用字段映射',
    icon: <FileTextOutlined />,
    view: 'scores' as TeacherView,
    status: '模板复用',
  },
  {
    title: '查看分析',
    description: '查看薄弱点和讲评摘要',
    icon: <BarChartOutlined />,
    view: 'analysis' as TeacherView,
    status: '讲评',
  },
]

const jobStates = [
  { state: 'queued', label: '排队中', value: 0 },
  { state: 'running', label: '处理中', value: 0 },
  { state: 'failed', label: '失败', value: 0 },
  { state: 'retry_waiting', label: '等待重试', value: 0 },
]

const initialSegments = [
  {
    id: 'q-01',
    title: '第 1 题',
    page: '第 1 页',
    region: 'x10 y12 w62 h18',
    asset: '',
    confidence: 0.9,
    failureReason: '',
    takeoverAction: 'skip',
    status: 'pending_review',
  },
  {
    id: 'q-02',
    title: '第 2 题上半部分',
    page: '第 1-2 页',
    region: 'x8 y76 w70 h20',
    asset: '',
    confidence: 0.78,
    failureReason: 'cross_page_split_required',
    takeoverAction: 'split',
    status: 'pending_review',
  },
  {
    id: 'q-03',
    title: '第 2 题下半部分',
    page: '第 2 页',
    region: 'x8 y6 w70 h24',
    asset: '',
    confidence: 0.82,
    failureReason: 'cross_page_merge_required',
    takeoverAction: 'merge',
    status: 'pending_review',
  },
]

const sharedAssets = ['图 A：滑轮组示意图', '图 B：电路图', '表 1：实验数据']
const defaultDifficultyFilterLabel = teacherDifficultyRangeLabelFor('0.4-0.7')

const starterDemoSteps = [
  { title: '导入样卷', detail: '使用示例试卷，不需要先准备真实资料', view: 'import' as TeacherView, contract: 'starter-step-1' },
  { title: '生成样卷', detail: '默认初中物理、力学基础、30 分', view: 'paper' as TeacherView, contract: 'starter-step-2' },
  { title: '导入样例成绩', detail: '字段映射自动匹配，异常行集中处理', view: 'scores' as TeacherView, contract: 'starter-step-3' },
  { title: '查看讲评摘要', detail: '直接看到薄弱知识点和导出入口', view: 'analysis' as TeacherView, contract: 'starter-step-4' },
]

const importWizardSteps = [
  ['上传文件', 'Word、PDF、图片'],
  ['查看状态', '排队、处理中、失败、等待重试'],
  ['确认异常', '只处理跨页、误切、共用题图'],
  ['回看来源', '页码、区域和原文件可追溯'],
]

const scoreWorkbenchSteps = [
  ['选择成绩表', '支持总分和小题分'],
  ['确认字段', '系统记住本次映射'],
  ['处理异常行', '只集中处理缺失和超分记录'],
  ['生成分析', '导入后直接进入讲评摘要'],
]

const paperWorkbenchSteps = [
  ['找题', '按知识点、题型、难度筛选'],
  ['题篮', '已选 2 题，8 分'],
  ['细目表', '单选 1 题，填空 1 题'],
  ['换题', '保持知识点、题型、分值一致'],
  ['导出', 'Word/PDF 草稿可打印'],
]

const scoreFieldMappings = [
  ['student_key', '学生编号'],
  ['total_score', '总分'],
  ['q1_score', '第 1 题'],
  ['q2_score', '第 2 题'],
]

const scoreAnalysisHighlights = [
  ['87.5%', '班级得分率'],
  ['运动快慢与速度', '薄弱点 1 个'],
  ['区分度可用', '讲评参考报告'],
]

const initialItemScoreMappingPreview = {
  teacherMessage: '输入成绩批次后，可集中预览小题到题目和知识点的映射。',
  itemCount: 2,
  mappedCount: 1,
  unclearCount: 1,
  rows: [
    {
      questionNo: 'Q1',
      scoreRecordCount: 2,
      averageScoreRate: 0.8,
      questionPreview: '关于惯性的选择题',
      primaryKnowledge: { title: '牛顿第一定律与惯性', status: 'active', version: 1 },
      status: 'mapped',
      issueCodes: [] as string[],
    },
    {
      questionNo: 'Q2',
      scoreRecordCount: 2,
      averageScoreRate: 0.77,
      questionPreview: null as string | null,
      primaryKnowledge: null as null | { title: string; status: string; version: number },
      status: 'needs_review',
      issueCodes: ['question_mapping_missing'],
    },
  ],
}

const initialCommentaryReportPreview = {
  teacherMessage: '小题映射确认后，可导出讲评报告草稿。',
  status: 'draft',
  artifactPath: '',
  manifestSha256: '',
  sections: [
    { sectionId: 'class_summary', title: '班级概览', summary: '等待生成' },
    { sectionId: 'weak_points', title: '优先讲评', summary: '等待生成' },
    { sectionId: 'practice_plan', title: '巩固练习', summary: '等待生成' },
  ],
}

const scoreWorkbenchActions = [
  { action: 'upload-score-sheet', label: '上传 Excel', icon: <FileTextOutlined />, kind: 'primary' },
  { action: 'generate-score-analysis', label: '生成分析', icon: <BarChartOutlined /> },
  { action: 'export-score-report', label: '导出报告', icon: <FileTextOutlined /> },
]

const teacherAnalysisHighlights = [
  ['班级得分率', '87.5%', '示例基线'],
  ['优先讲评', '运动快慢与速度', '薄弱点 1 个'],
  ['下一步', '加入巩固题', '按当前知识版本选题'],
]

const analysisActions = [{ action: 'open-analysis-summary', label: '查看摘要', icon: <BarChartOutlined /> }]

const paperWorkbenchSummaryCards = [
  ['question-basket', '题篮', '2 题 · 8 分', '从检索结果直接加入'],
  ['blueprint-table-entry', '细目表', '力学基础', '难度中等到略高'],
  ['replacement-entry', '换题入口', '保持约束', '可撤销草稿'],
  ['export-entry', '导出入口', 'Word / PDF', '先验证工件'],
]

const replacementAuditTags = ['同知识点', '同题型', '难度相近', '分值一致', '避开近期练过', '示例约束']

const questionSearchFilterChips = [
  { filter: 'knowledge', label: '惯性' },
  { filter: 'question-type', label: '单选题' },
  { filter: 'difficulty', label: defaultDifficultyFilterLabel },
  { filter: 'source', label: '示例来源' },
]

const labelFor = teacherLabelFor

const reviewRiskColorFor = (riskLevel: string) => {
  if (riskLevel === 'high') {
    return 'red'
  }
  if (riskLevel === 'medium') {
    return 'orange'
  }
  return 'green'
}

const initialPaperRequest =
  '八年级物理，牛顿第一定律与惯性，单选 5 题、计算 2 题、实验 1 题，总分 30 分，难度中等'

const initialPaperUnderstanding = {
  mode: 'draft_test',
  productionEligible: false,
  allowRealModelCalls: false,
  systemUnderstanding:
    '按初中物理要求生成组卷理解：八年级物理，牛顿第一定律与惯性，单选 5 题、计算 2 题、实验 1 题，总分 30 分，难度中等',
  paperType: 'unit_practice',
  subject: 'physics',
  grade: 'grade_8',
  totalScore: 30,
  difficultyTarget: 'medium',
  scope: ['牛顿第一定律与惯性'],
  blueprint: [
    {
      questionType: 'single_choice',
      count: 5,
      score: 15,
      assetStatus: 'draft_dynamic_asset',
      reviewStatus: 'pending_review',
    },
    {
      questionType: 'calculation',
      count: 2,
      score: 10,
      assetStatus: 'draft_dynamic_asset',
      reviewStatus: 'pending_review',
    },
    {
      questionType: 'experiment',
      count: 1,
      score: 5,
      assetStatus: 'draft_dynamic_asset',
      reviewStatus: 'pending_review',
    },
  ],
  reviewQuestions: [
    '是否需要限定教材版本或章节范围？',
    '是否需要排除最近已练过的题目？',
    '是否确认使用草稿测试细目表继续生成试卷草稿？',
  ],
}

const initialPaperDraft = {
  mode: 'draft_test',
  productionEligible: false,
  allowRealModelCalls: false,
  currentQuestion: {
    id: 'paper-q-01',
    stemPreview: '关于惯性的说法，下列哪项正确？',
    questionType: 'single_choice',
    score: 3,
    difficultyEstimated: 0.62,
    primaryKnowledgeId: 'PHY-JH-MECH-FORCE-NEWTON1',
    primaryKnowledgeTitle: '牛顿第一定律与惯性',
    sourceType: 'synthetic',
    recentUseStatus: 'not_recently_used',
  },
  replacementQuestion: null as null | {
    id: string
    stemPreview: string
    questionType: string
    score: number
    difficultyEstimated: number
    primaryKnowledgeId: string
    primaryKnowledgeTitle: string
    sourceType: string
    recentUseStatus: string
  },
  undoSnapshot: null as null | {
    undoToken: string
    revertAction: string
  },
  auditTrail: [] as string[],
}

function App() {
  const readyHealthQuery = useReadyHealthQuery()
  const [sourceTypeFilter, setSourceTypeFilter] = useState('all')
  const [importJobLookupId, setImportJobLookupId] = useState('')
  const [selectedSourceDocumentId, setSelectedSourceDocumentId] = useState('')
  const [realExamQueue, setRealExamQueue] = useState<ReviewQueueItemContract[]>([])
  const [realExamQueueTotal, setRealExamQueueTotal] = useState(0)
  const [realExamQueueBusy, setRealExamQueueBusy] = useState(false)
  const [realExamQueueMessage, setRealExamQueueMessage] = useState('尚未查询 2015 真卷复核队列')
  const [selectedRealExamReviewId, setSelectedRealExamReviewId] = useState('')
  const [realExamReviewNote, setRealExamReviewNote] = useState('已核对题干、答案、标签和来源')
  const [activeTeacherView, setActiveTeacherView] = useState<TeacherView>('import')
  const [segments, setSegments] = useState(initialSegments)
  const [selectedIds, setSelectedIds] = useState<string[]>(['q-02', 'q-03'])
  const [selectedAsset, setSelectedAsset] = useState(sharedAssets[0])
  const [actionLog, setActionLog] = useState<string[]>([])
  const [savedQuestionSourceSummary, setSavedQuestionSourceSummary] = useState('尚未保存题目')
  const [savedQuestionSourceRegions, setSavedQuestionSourceRegions] = useState<
    Array<{ id: string; pageNumber: number; regionType: string; screenshotRelativePath: string | null }>
  >([])
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
  const [importStartedAt] = useState<Date>(() => new Date())
  const [nowMs, setNowMs] = useState<number>(() => Date.now())
  const [importActionCount, setImportActionCount] = useState(0)
  const [failureTakeoverCount, setFailureTakeoverCount] = useState(0)
  const [lastTakeoverAction, setLastTakeoverAction] = useState<string | null>(null)
  const [importUploadBusy, setImportUploadBusy] = useState(false)
  const localIdRef = useRef(0)
  const uploadInputRef = useRef<HTMLInputElement | null>(null)
  const uploadDropzoneRef = useRef<HTMLButtonElement | null>(null)

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
  const questionSearchQuery = useQuestionSearchQuery(1, 10)
  const cutCandidates = cutCandidatesQuery.data?.ok ? cutCandidatesQuery.data.data : undefined
  const questionSearch = questionSearchQuery.data?.ok ? questionSearchQuery.data.data : undefined
  const sourcePreview = previewQuery.data?.ok ? previewQuery.data.data : undefined
  const importJob = importJobQuery.data?.ok ? importJobQuery.data.data : undefined
  const selectedRealExamReview = realExamQueue.find((item) => item.id === selectedRealExamReviewId)
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

  useEffect(() => {
    const timer = window.setInterval(() => setNowMs(Date.now()), 30_000)
    return () => window.clearInterval(timer)
  }, [])

  const appendLog = (message: string) => {
    setActionLog((current) => [message, ...current].slice(0, 5))
  }

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
    setActionLog((current) => [`已撤销：${current[0] ?? '最近操作'}`, ...current.slice(1)])
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

  const loadRealExamReviewQueue = async () => {
    setRealExamQueueBusy(true)
    const result = await getReviewQueueItems({
      status: 'open',
      reviewType: 'guangzhou_2015_question_review',
      limit: 50,
    })
    setRealExamQueueBusy(false)

    if (!result.ok) {
      setRealExamQueueMessage(`真卷队列查询失败：${result.error.message}`)
      return
    }

    setRealExamQueue(result.data.items)
    setRealExamQueueTotal(result.data.totalCount)
    setRealExamQueueMessage(`已加载 ${result.data.items.length} 条 2015 真卷待复核题目`)
    if (!selectedRealExamReviewId && result.data.items.length > 0) {
      setSelectedRealExamReviewId(result.data.items[0].id)
    }
  }

  const loadRealExamReviewItem = async (item: ReviewQueueItemContract) => {
    const payload = item.payload
    setSelectedRealExamReviewId(item.id)
    setRealExamReviewNote(
      payload.questionNo
        ? `第 ${payload.questionNo} 题已核对题干、答案、标签和来源`
        : '已核对题干、答案、标签和来源',
    )
    if (payload.sourceDocumentId) {
      setSelectedSourceDocumentId(payload.sourceDocumentId)
    }
    if (payload.candidateId) {
      setSelectedIds([payload.candidateId])
      setSegments([
        {
          id: payload.candidateId,
          title: `第 ${payload.questionNo || '?'} 题`,
          page: '真卷来源页待回看',
          region: payload.sourceRegionId ? '已关联来源区域' : '来源区域待确认',
          asset: '',
          confidence: item.confidence ?? payload.confidence ?? 0.86,
          failureReason: item.reason ?? payload.reason,
          takeoverAction: item.requiredAction || payload.requiredAction || 'manual_review',
          status: item.status,
        },
      ])
    }

    if (payload.questionItemId) {
      const sourceResult = await getQuestionSources(payload.questionItemId)
      if (sourceResult.ok) {
        setSavedQuestionSourceSummary(
          `第 ${payload.questionNo} 题来源回看：${sourceResult.data.sourceRegions.length} 个区域`,
        )
        setSavedQuestionSourceRegions(sourceResult.data.sourceRegions)
      } else {
        setSavedQuestionSourceSummary(`第 ${payload.questionNo} 题来源回看失败：${sourceResult.error.message}`)
        setSavedQuestionSourceRegions([])
      }
    }
    appendLog(`已载入 2015 真卷第 ${payload.questionNo || '?'} 题`)
  }

  const finishRealExamReviewItem = async (
    item: ReviewQueueItemContract,
    decision: 'resolved' | 'dismissed',
  ) => {
    const note = realExamReviewNote.trim()
    const result = await resolveReviewQueueItem(item.id, {
      reviewedBy: 'teacher-real-exam-workbench',
      decision,
      reason: note || (decision === 'resolved' ? 'ui_real_exam_review_confirmed' : 'ui_real_exam_review_returned'),
    })
    if (!result.ok) {
      setRealExamQueueMessage(`${decision === 'resolved' ? '确认' : '退回'}失败：${result.error.message}`)
      return
    }

    setRealExamQueue((current) => current.filter((row) => row.id !== item.id))
    setRealExamQueueTotal((count) => Math.max(0, count - 1))
    setSelectedRealExamReviewId('')
    setRealExamReviewNote('已核对题干、答案、标签和来源')
    const verb = decision === 'resolved' ? '确认' : '退回'
    setRealExamQueueMessage(`已${verb}第 ${item.payload.questionNo || '?'} 题，队列已记录审核人、时间和说明`)
    appendLog(`2015 真卷第 ${item.payload.questionNo || '?'} 题已${verb}`)
  }

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

  const replacePaperQuestion = () => {
    const replacement = {
      ...paperDraft.currentQuestion,
      id: nextLocalId('paper-q-replacement'),
      stemPreview: '关于惯性的理解，下列说法正确的是哪一项？',
      difficultyEstimated: Math.min(1, paperDraft.currentQuestion.difficultyEstimated + 0.03),
      recentUseStatus: 'not_recently_used',
    }
    setPaperDraft((current) => ({
      ...current,
      replacementQuestion: replacement,
      undoSnapshot: {
        undoToken: nextLocalId('undo'),
        revertAction: 'restore_before_question',
      },
      auditTrail: [
        'kept primary knowledge constraint',
        'kept question type constraint',
        'kept score constraint',
        'kept draft_test non-production boundary',
      ],
    }))
    appendLog('已按同知识点、同题型、相近难度和同分值生成替换题')
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

  const previewScoreMappings = async () => {
    const assessmentId = scoreMappingAssessmentId.trim()
    if (!assessmentId) {
      setScoreMappingMessage('请先输入成绩批次 ID，再预览小题映射。')
      return
    }

    const result = await previewItemScoreMappings({
      assessmentId,
      mappings: [
        { questionNo: 'Q1', questionItemId: null },
        { questionNo: 'Q2', questionItemId: null },
      ],
    })
    if (!result.ok) {
      setScoreMappingMessage(`映射预览失败：${result.error.message}`)
      return
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
        { questionNo: 'Q1', questionItemId: null },
        { questionNo: 'Q2', questionItemId: null },
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

  const exportPaper = (format: 'docx' | 'pdf') => {
    appendLog(`已生成 ${format.toUpperCase()} 示例导出工件`)
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
          </Space>
        </header>

        <main className={`workspace teacher-view-${activeTeacherView}`}>
          <section
            className="primary-panel"
            aria-label="普通教师入口"
            data-flow="teacher-home"
            data-contract="four-default-actions"
          >
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>今天要做什么</Typography.Title>
                <Typography.Text type="secondary">
                  默认只放四件常用事，其他设置交给管理员。
                </Typography.Text>
              </div>
              <Button type="primary" icon={<InboxOutlined />} size="large" onClick={() => openTeacherView('import')}>
                打开导入
              </Button>
            </div>

            <div className="action-grid">
              {teacherActions.map((action) => (
                <button
                  className={activeTeacherView === action.view ? 'action-card active' : 'action-card'}
                  key={action.title}
                  type="button"
                  onClick={() => openTeacherView(action.view)}
                  aria-pressed={activeTeacherView === action.view}
                  data-action="teacher-entry"
                  data-view={action.view}
                >
                  <span className="action-icon">{action.icon}</span>
                  <span className="action-copy">
                    <strong>{action.title}</strong>
                    <span>{action.description}</span>
                  </span>
                  <Tag>{action.status}</Tag>
                </button>
              ))}
            </div>

            <div className="starter-demo" data-flow="first-run-starter-demo" data-contract="teacher-default-values">
              <div>
                <Typography.Text type="secondary">新手示例</Typography.Text>
                <Typography.Title level={3}>用默认样例跑一遍</Typography.Title>
              </div>
              <div className="starter-demo-grid">
                {starterDemoSteps.map((step, index) => (
                  <button
                    className="starter-step"
                    key={step.title}
                    type="button"
                    data-action="run-starter-example"
                    data-contract={step.contract}
                    onClick={() => openTeacherView(step.view)}
                  >
                    <strong>{index + 1}</strong>
                    <span>
                      <b>{step.title}</b>
                      <small>{step.detail}</small>
                    </span>
                  </button>
                ))}
              </div>
            </div>

            <div
              className="state-boundary-strip"
              data-flow="frontend-state-boundary"
              data-contract={apiContractSnapshot.version}
              data-server-state={uiStateBoundary.serverState}
              data-draft-state={uiStateBoundary.teacherDraftState}
              data-high-risk-state={uiStateBoundary.highRiskOperationState}
            >
              <span>服务状态自动同步</span>
              <span>教师修改留在当前页面</span>
              <span>重要操作会先确认</span>
            </div>
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
              type="info"
              title="可以开始处理"
              description="上传后会显示处理进度；失败时保留原文件，可继续人工处理。"
            />

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

            <div className="real-exam-review" data-contract="real-guangzhou-2015-review-workbench">
              <div className="panel-heading compact">
                <div>
                  <Typography.Text type="secondary">2015 广州真卷</Typography.Text>
                  <Typography.Title level={3}>逐题复核</Typography.Title>
                </div>
                <Tag color={realExamQueue.length > 0 ? 'orange' : 'default'}>
                  {realExamQueue.length > 0 ? `${realExamQueue.length} 待确认` : '未加载'}
                </Tag>
              </div>
              <div className="review-summary" data-contract="real-exam-review-summary">
                <span>
                  <Typography.Text type="secondary">队列总数</Typography.Text>
                  <strong>{realExamQueueTotal}</strong>
                </span>
                <span>
                  <Typography.Text type="secondary">当前题号</Typography.Text>
                  <strong>{selectedRealExamReview?.payload.questionNo || '-'}</strong>
                </span>
                <span>
                  <Typography.Text type="secondary">状态</Typography.Text>
                  <strong>{realExamQueueBusy ? '查询中' : realExamQueue.length > 0 ? '待确认' : '未加载'}</strong>
                </span>
              </div>
              <Typography.Text>{realExamQueueMessage}</Typography.Text>
              <div className="real-exam-detail" data-contract="real-exam-review-detail">
                <span>
                  <Typography.Text type="secondary">题干预览</Typography.Text>
                  <strong>{selectedRealExamReview?.payload.textPreview || '请选择一题后载入'}</strong>
                </span>
                <span>
                  <Typography.Text type="secondary">答案</Typography.Text>
                  <strong>{selectedRealExamReview?.payload.answer || '-'}</strong>
                </span>
                <span>
                  <Typography.Text type="secondary">标签</Typography.Text>
                  <strong>
                    {selectedRealExamReview?.payload.primaryKnowledgeLabel || '-'}
                    {selectedRealExamReview?.payload.knowledgeTags.length
                      ? ` · ${selectedRealExamReview.payload.knowledgeTags.join(' / ')}`
                      : ''}
                  </strong>
                </span>
                <span>
                  <Typography.Text type="secondary">来源</Typography.Text>
                  <strong>{savedQuestionSourceSummary}</strong>
                </span>
              </div>
              <Input.TextArea
                aria-label="2015 真卷审核说明"
                data-action="real-guangzhou-2015-review-note"
                value={realExamReviewNote}
                onChange={(event) => setRealExamReviewNote(event.target.value)}
                autoSize={{ minRows: 2, maxRows: 4 }}
                placeholder="填写确认或退回说明"
              />
              <Space size="small" wrap>
                <Button
                  icon={<FileSearchOutlined />}
                  onClick={loadRealExamReviewQueue}
                  disabled={realExamQueueBusy}
                  data-action="load-real-guangzhou-2015-review-queue"
                >
                  查询真卷队列
                </Button>
                <Button
                  icon={<SearchOutlined />}
                  onClick={() =>
                    selectedRealExamReview
                      ? void loadRealExamReviewItem(selectedRealExamReview)
                      : setRealExamQueueMessage('请先选择一题')
                  }
                  disabled={!selectedRealExamReview}
                  data-action="load-real-guangzhou-2015-review-item"
                >
                  载入当前题
                </Button>
                <Button
                  type="primary"
                  icon={<CheckCircleOutlined />}
                  onClick={() =>
                    selectedRealExamReview
                      ? void finishRealExamReviewItem(selectedRealExamReview, 'resolved')
                      : setRealExamQueueMessage('请先选择一题')
                  }
                  disabled={!selectedRealExamReview}
                  data-action="confirm-real-guangzhou-2015-review-item"
                >
                  确认当前题
                </Button>
                <Button
                  icon={<UndoOutlined />}
                  onClick={() =>
                    selectedRealExamReview
                      ? void finishRealExamReviewItem(selectedRealExamReview, 'dismissed')
                      : setRealExamQueueMessage('请先选择一题')
                  }
                  disabled={!selectedRealExamReview}
                  data-action="dismiss-real-guangzhou-2015-review-item"
                >
                  退回当前题
                </Button>
              </Space>
              <div className="real-exam-list" aria-label="2015 广州真卷待复核题目">
                {realExamQueue.slice(0, 18).map((item) => {
                  const selected = item.id === selectedRealExamReviewId
                  return (
                    <button
                      key={item.id}
                      type="button"
                      className={selected ? 'real-exam-row active' : 'real-exam-row'}
                      onClick={() => setSelectedRealExamReviewId(item.id)}
                      data-review-type={item.reviewType}
                    >
                      <span>
                        <strong>第 {item.payload.questionNo || '?'} 题</strong>
                        <small>
                          真卷复核 · {teacherLabelFor(item.requiredAction)}
                        </small>
                      </span>
                      <Tag color={reviewRiskColorFor(item.riskLevel)}>
                        {teacherLabelFor(`risk_${item.riskLevel}`)}
                      </Tag>
                    </button>
                  )
                })}
              </div>
            </div>

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
                <Tag color="green" data-contract="synthetic-score-fixture">示例数据</Tag>
                <Tag data-contract="score-productionEligible=false">正式启用前预览</Tag>
              </Space>
            </div>

            <div className="score-workbench" data-flow="score-analysis-workbench">
              <div className="score-upload-lane">
                {scoreWorkbenchActions.map((item) => (
                  <Button
                    key={item.action}
                    type={item.kind === 'primary' ? 'primary' : 'default'}
                    icon={item.icon}
                    onClick={item.action === 'export-score-report' ? exportScoreReport : undefined}
                    data-action={item.action}
                  >
                    {item.label}
                  </Button>
                ))}
              </div>

              <div className="score-field-mapping" data-contract="excel-field-mapping-preview">
                <Typography.Text type="secondary">字段映射预览</Typography.Text>
                {scoreFieldMappings.map(([field, label]) => (
                  <div className="mapping-row" key={field}>
                    <code>{field}</code>
                    <span>{label}</span>
                    <Tag>已匹配</Tag>
                  </div>
                ))}
              </div>

              <div className="score-exception-list" data-contract="score-exception-rows">
                <Typography.Text type="secondary">异常行</Typography.Text>
                <div className="exception-row">
                  <strong>第 3 行</strong>
                  <span>q2_score 超过满分，暂不导入</span>
                  <Tag color="orange">需确认</Tag>
                </div>
                <small>有效记录 2 行，异常 1 行；教师只处理异常，不重填整张表。</small>
              </div>

              <div
                className="item-score-mapping-preview"
                data-flow="item-score-mapping-workbench"
                data-contract="s011b-item-score-mapping-ui-api"
              >
                <Typography.Text type="secondary">小题映射预览</Typography.Text>
                <div className="score-mapping-controls">
                  <Input
                    aria-label="成绩批次 ID"
                    placeholder="成绩批次 ID"
                    value={scoreMappingAssessmentId}
                    onChange={(event) => setScoreMappingAssessmentId(event.target.value)}
                    data-contract="s011b-assessment-id-input"
                  />
                  <Button
                    icon={<LinkOutlined />}
                    onClick={previewScoreMappings}
                    data-action="preview-item-score-mapping"
                  >
                    预览映射
                  </Button>
                </div>
                <Alert
                  showIcon
                  type={itemScoreMappingPreview.unclearCount > 0 ? 'warning' : 'success'}
                  title={scoreMappingMessage}
                  data-contract="centralized-unclear-item-score-mappings"
                />
                <div className="analysis-summary-grid compact">
                  <span>
                    <strong>{itemScoreMappingPreview.itemCount}</strong>
                    <small>小题</small>
                  </span>
                  <span>
                    <strong>{itemScoreMappingPreview.mappedCount}</strong>
                    <small>已映射</small>
                  </span>
                  <span>
                    <strong>{itemScoreMappingPreview.unclearCount}</strong>
                    <small>待集中处理</small>
                  </span>
                </div>
                <div className="item-score-mapping-list">
                  {itemScoreMappingPreview.rows.map((row) => (
                    <div className="item-score-mapping-row" key={row.questionNo}>
                      <span>
                        <strong>{row.questionNo}</strong>
                        <small>
                          {row.scoreRecordCount} 条成绩 · 得分率 {Math.round(row.averageScoreRate * 100)}%
                        </small>
                      </span>
                      <span>
                        <strong>{row.questionPreview ?? '题目未确认'}</strong>
                        <small>
                          {row.primaryKnowledge
                            ? `${row.primaryKnowledge.title} · ${teacherLabelFor(row.primaryKnowledge.status)} v${row.primaryKnowledge.version}`
                            : '知识点待确认'}
                        </small>
                      </span>
                      <Tag color={row.status === 'mapped' ? 'green' : 'orange'}>
                        {row.status === 'mapped' ? '已映射' : '需确认'}
                      </Tag>
                    </div>
                  ))}
                </div>
              </div>

              <div className="score-analysis-summary" data-contract="knowledge-analysis-summary">
                <Typography.Text type="secondary">知识点分析</Typography.Text>
                <div className="analysis-summary-grid compact">
                  {scoreAnalysisHighlights.map(([value, detail]) => (
                    <div key={detail}>
                      <strong>{value}</strong>
                      <small>{detail}</small>
                    </div>
                  ))}
                </div>
              </div>

              <div className="score-report-path" data-contract="analysis-report-export-path">
                <Typography.Text type="secondary">报告导出路径</Typography.Text>
                <Alert
                  showIcon
                  type={commentaryReportPreview.status === 'ready' ? 'success' : 'info'}
                  title={commentaryReportPreview.teacherMessage}
                  data-contract="s011c-commentary-report-export"
                />
                <strong>{commentaryReportPreview.artifactPath || '导入后直接生成讲评摘要，再导出给备课使用。'}</strong>
                <small>
                  {commentaryReportPreview.manifestSha256
                    ? `manifest: ${commentaryReportPreview.manifestSha256.slice(0, 12)}`
                    : '不使用真实学生数据，不写正式历史学情。'}
                </small>
                <div className="commentary-section-list">
                  {commentaryReportPreview.sections.map((section) => (
                    <span key={section.sectionId}>
                      <strong>{section.title}</strong>
                      <small>{section.summary}</small>
                    </span>
                  ))}
                </div>
              </div>
            </div>

            <div className="teacher-step-list">
              {scoreWorkbenchSteps.map(([title, detail]) => (
                <div className="teacher-step" key={title}>
                  <CheckCircleOutlined />
                  <span>
                    <strong>{title}</strong>
                    <small>{detail}</small>
                  </span>
                </div>
              ))}
            </div>
          </section>

          <section className="analysis-panel" aria-label="讲评分析" data-flow="teacher-analysis-workbench">
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>讲评分析</Typography.Title>
                <Typography.Text type="secondary">
                  先看班级薄弱点，再决定讲评和练习。
                </Typography.Text>
              </div>
              {analysisActions.map((item) => (
                <Button key={item.action} icon={item.icon} data-action={item.action}>
                  {item.label}
                </Button>
              ))}
            </div>
            <div className="analysis-summary-grid">
              {teacherAnalysisHighlights.map(([label, value, detail]) => (
                <div key={label}>
                  <Typography.Text type="secondary">{label}</Typography.Text>
                  <strong>{value}</strong>
                  <small>{detail}</small>
                </div>
              ))}
            </div>

          </section>

          <section
            className="paper-workbench-panel"
            aria-label="找题组卷工作台"
            data-flow="paper-assembly-workbench"
          >
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>找题组卷工作台</Typography.Title>
                <Typography.Text type="secondary">
                  检索、题篮、细目表、换题和导出放在同一屏，目标是 10 分钟内完成一份可打印样卷。
                </Typography.Text>
              </div>
              <Space size="small" wrap>
                <Tag color="green" data-contract="ten-minute-target">10 分钟目标</Tag>
                <Tag data-contract="single-workbench">单工作台</Tag>
              </Space>
            </div>

            <div className="paper-workbench-flow" aria-label="组卷流程">
              {paperWorkbenchSteps.map(([title, description], index) => (
                <div className="paper-workbench-step" key={title} data-contract={`paper-step-${index + 1}`}>
                  <strong>{index + 1}</strong>
                  <span>
                    <b>{title}</b>
                    <small>{description}</small>
                  </span>
                </div>
              ))}
            </div>

            <div className="paper-workbench-summary">
              {paperWorkbenchSummaryCards.map(([contract, title, value, detail]) => (
                <div data-contract={contract} key={contract}>
                  <Typography.Text type="secondary">{title}</Typography.Text>
                  <strong>
                    {contract === 'question-basket' && paperBasketId ? '已保存' : value}
                  </strong>
                  <small>{detail}</small>
                </div>
              ))}
            </div>

            <div
              className="paper-workflow-status"
              data-contract="s009c-real-blueprint-api"
              data-blueprint-review-id={paperBlueprintReviewId}
              data-paper-basket-id={paperBasketId}
            >
              <span>
                <Typography.Text type="secondary">当前题篮</Typography.Text>
                <strong data-contract="confirmed-paper-basket">
                  {paperBasketId ? '已保存题篮' : '等待确认细目表'}
                </strong>
              </span>
              <span>
                <Typography.Text type="secondary">约束</Typography.Text>
                <strong data-contract="paper-constraint-visible">{paperConstraintMessage}</strong>
              </span>
            </div>
          </section>

          <section className="question-panel" aria-label="题库检索" data-flow="question-search">
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>题库检索</Typography.Title>
                <Typography.Text type="secondary">
                  默认使用当前校本题库，保留来源、版本、难度和题图公式状态。
                </Typography.Text>
              </div>
              <Space size="small" wrap>
                <Tag data-contract="s008b-active-version">
                  {questionSearch ? `${teacherLabelFor(questionSearch.knowledgeStatus)} v${questionSearch.knowledgeVersion ?? '-'}` : '校本题库'}
                </Tag>
                <Button
                  icon={<SearchOutlined />}
                  loading={questionSearchQuery.isFetching}
                  onClick={() => questionSearchQuery.refetch()}
                  data-action="question-search-refresh"
                >
                  检索
                </Button>
              </Space>
            </div>

            <div className="filter-row" aria-label="筛选条件">
              {questionSearchFilterChips.map((item) => (
                <button className="filter-chip" data-filter={item.filter} key={item.filter} type="button">
                  {item.label}
                </button>
              ))}
            </div>

            <div
              className="question-card-list"
              aria-label="题目卡片"
              data-contract="s008b-real-api-question-cards"
            >
              {questionSearchQuery.data?.ok === false ? (
                <Alert
                  showIcon
                  type="warning"
                  title="题库暂时无法连接"
                  description="可先继续组卷草稿，稍后重新检索。"
                  data-state="question-search-error"
                />
              ) : null}
              {questionSearch && questionSearch.items.length === 0 ? (
                <Alert
                  showIcon
                  type="info"
                  title="暂无可用题目"
                  description="完成导入和确认后，题目会出现在这里。"
                  data-state="question-search-empty"
                />
              ) : null}
              {questionSearch?.items.map((card) => (
                <button className="question-card" data-card="question-card" key={card.id} type="button">
                  <span>
                    <strong>{card.preview || '未命名题目'}</strong>
                    <small>
                      {card.primaryKnowledge?.title ?? '待补知识点'} · {card.sources.titles[0] ?? '来源待补'}
                    </small>
                  </span>
                  <span className="question-meta">
                    <Tag>{teacherLabelFor(card.questionType)}</Tag>
                    <Tag>{teacherDifficultyLabelFor(card.difficultyEstimated ?? 0)}</Tag>
                    <Tag>{card.primaryKnowledge ? `v${card.primaryKnowledge.version}` : '待定版本'}</Tag>
                    <Tag>{card.sources.types[0] ? teacherLabelFor(card.sources.types[0]) : '来源待补'}</Tag>
                    {card.hasImage ? <Tag color="green">题图</Tag> : <Tag>无题图</Tag>}
                    {card.hasFormula ? <Tag color="blue">公式</Tag> : null}
                    {card.hasTable ? <Tag color="cyan">表格</Tag> : null}
                    <Tag color="green">{teacherLabelFor(card.status)}</Tag>
                  </span>
                </button>
              ))}
            </div>
          </section>

          <section
            className="paper-request-panel"
            aria-label="自然语言组卷"
            data-flow="paper-request-understanding"
          >
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>自然语言组卷</Typography.Title>
                <Typography.Text type="secondary">
                  先展示系统理解和细目表，教师确认后再继续选题。
                </Typography.Text>
              </div>
              <Space size="small" wrap>
                <Tag color="green">{teacherLabelFor(paperUnderstanding.mode)}</Tag>
                <Tag data-contract="productionEligible=false">正式启用前预览</Tag>
              </Space>
            </div>

            <div className="paper-request-workspace">
              <div className="paper-request-input">
                <Input.TextArea
                  aria-label="组卷需求"
                  value={paperRequest}
                  onChange={(event) => setPaperRequest(event.target.value)}
                  autoSize={{ minRows: 4, maxRows: 6 }}
                  data-contract="synthetic-paper-request"
                />
                <Button
                  type="primary"
                  icon={<FileSearchOutlined />}
                  loading={paperWorkflowBusy}
                  onClick={parsePaperRequest}
                  data-action="parse-paper-request"
                >
                  生成理解
                </Button>
                <Button
                  icon={<CheckCircleOutlined />}
                  loading={paperWorkflowBusy}
                  disabled={!paperBlueprintReviewId || Boolean(paperBasketId)}
                  onClick={confirmPaperBlueprint}
                  data-action="confirm-paper-blueprint"
                >
                  确认细目表
                </Button>
              </div>

              <div className="paper-understanding" data-contract="paper-understanding">
                <Alert
                  showIcon
                  type="info"
                  title="系统理解"
                  description={paperUnderstanding.systemUnderstanding}
                />
                <Alert
                  showIcon
                  type={paperBasketId ? 'success' : paperBlueprintReviewId ? 'warning' : 'info'}
                  title={paperWorkflowMessage}
                  description={paperConstraintMessage}
                  data-state="s009c-paper-workflow-message"
                />
                <div className="paper-summary">
                  <span>
                    <strong>{paperUnderstanding.totalScore}</strong>
                    <small>总分</small>
                  </span>
                  <span>
                    <strong>{teacherDifficultyLabelFor(paperUnderstanding.difficultyTarget)}</strong>
                    <small>难度目标</small>
                  </span>
                  <span>
                    <strong>{paperUnderstanding.scope.join('、')}</strong>
                    <small>范围</small>
                  </span>
                </div>

                <div className="blueprint-table" data-contract="blueprint-draft">
                  {paperUnderstanding.blueprint.map((row) => (
                    <div className="blueprint-row" key={row.questionType}>
                      <strong>{labelFor(row.questionType)}</strong>
                      <span>{row.count} 题</span>
                      <span>{row.score} 分</span>
                      <Tag>{teacherLabelFor(row.assetStatus)}</Tag>
                      <Tag color="orange">{teacherLabelFor(row.reviewStatus)}</Tag>
                    </div>
                  ))}
                </div>

                <div className="review-questions" data-contract="paper-review-questions">
                  {paperUnderstanding.reviewQuestions.map((item) => (
                    <Typography.Text key={item}>{item}</Typography.Text>
                  ))}
                </div>
              </div>
            </div>
          </section>

          <section
            className="paper-replacement-panel"
            aria-label="一键换题与撤销"
            data-flow="paper-question-replacement"
          >
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>一键换题</Typography.Title>
                <Typography.Text type="secondary">
                  保持约束一致，先生成可撤销替换题。
                </Typography.Text>
              </div>
              <Space size="small" wrap>
                <Tag color="green">{teacherLabelFor(paperDraft.mode)}</Tag>
                <Tag data-contract="replacement-productionEligible=false">正式启用前预览</Tag>
                <Tag data-contract="replacement-undo-snapshot">可撤销</Tag>
              </Space>
            </div>

            <div className="replacement-workspace" data-contract="replacement-constraints">
              <div className="replacement-card" data-contract="before-question">
                <Typography.Text type="secondary">当前题</Typography.Text>
                <Typography.Title level={3}>{paperDraft.currentQuestion.stemPreview}</Typography.Title>
                <Space size="small" wrap>
                  <Tag>{labelFor(paperDraft.currentQuestion.questionType)}</Tag>
                  <Tag>{paperDraft.currentQuestion.score} 分</Tag>
                  <Tag>{teacherDifficultyLabelFor(paperDraft.currentQuestion.difficultyEstimated)}</Tag>
                  <Tag>{paperDraft.currentQuestion.primaryKnowledgeTitle}</Tag>
                </Space>
              </div>

              <div className="replacement-actions">
                <Button
                  type="primary"
                  icon={<SwapOutlined />}
                  onClick={replacePaperQuestion}
                  data-action="replace-question"
                >
                  换题
                </Button>
                <Button
                  icon={<UndoOutlined />}
                  onClick={undoPaperReplacement}
                  disabled={!paperDraft.undoSnapshot}
                  data-action="undo-question-replacement"
                >
                  撤销
                </Button>
              </div>

              <div className="replacement-card" data-contract="after-question">
                <Typography.Text type="secondary">替换题</Typography.Text>
                <Typography.Title level={3}>
                  {paperDraft.replacementQuestion?.stemPreview ?? '等待生成替换题'}
                </Typography.Title>
                <Space size="small" wrap>
                  <Tag>{labelFor(paperDraft.replacementQuestion?.questionType ?? paperDraft.currentQuestion.questionType)}</Tag>
                  <Tag>{paperDraft.replacementQuestion?.score ?? paperDraft.currentQuestion.score} 分</Tag>
                  <Tag>
                    {teacherDifficultyLabelFor(
                      paperDraft.replacementQuestion?.difficultyEstimated ?? paperDraft.currentQuestion.difficultyEstimated,
                    )}
                  </Tag>
                  <Tag>{paperDraft.replacementQuestion?.primaryKnowledgeTitle ?? paperDraft.currentQuestion.primaryKnowledgeTitle}</Tag>
                </Space>
              </div>
            </div>

            <div className="replacement-audit" data-contract="replacement-audit-trail">
              {replacementAuditTags.map((item) => (
                <Tag key={item}>{item}</Tag>
              ))}
            </div>
          </section>

          <section
            className="paper-export-panel"
            aria-label="试卷导出"
            data-flow="paper-export"
          >
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>试卷导出</Typography.Title>
                <Typography.Text type="secondary">
                  先导出可打印样卷，验证公式、题图和表格不丢失。
                </Typography.Text>
              </div>
              <Space size="small" wrap>
                <Tag color="green">示例导出</Tag>
                <Tag data-contract="export-productionEligible=false">正式启用前预览</Tag>
                <Tag data-contract="export-artifact-checks">自动检查</Tag>
              </Space>
            </div>

            <div className="export-workspace">
              <div className="export-preview" data-contract="export-preview">
                <Typography.Text type="secondary">样卷预览</Typography.Text>
                <Typography.Title level={3}>校本题谱示例导出样卷</Typography.Title>
                <p>Q1. 质量为 2 kg 的物体受到恒力作用，公式：F=ma。</p>
                <div className="export-table-preview" aria-label="导出表格预览">
                  <span>物理量</span>
                  <span>单位</span>
                  <strong>力</strong>
                  <strong>N</strong>
                </div>
                <Tag>答案：B</Tag>
              </div>

              <div className="export-actions">
                <Button
                  type="primary"
                  icon={<FileTextOutlined />}
                  onClick={() => exportPaper('docx')}
                  data-action="export-docx"
                >
                  导出 Word
                </Button>
                <Button
                  icon={<FileTextOutlined />}
                  onClick={() => exportPaper('pdf')}
                  data-action="export-pdf"
                >
                  导出 PDF
                </Button>
              </div>
            </div>
          </section>

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
                <div className="page-sheet">
                  <span className="page-number">第 1 页</span>
                  <button
                    className="source-region region-a"
                    type="button"
                    onClick={() => toggleSegment('q-01')}
                  >
                    第 1 题
                  </button>
                  <button
                    className="source-region region-b"
                    type="button"
                    onClick={() => toggleSegment('q-02')}
                  >
                    第 2 题上
                  </button>
                </div>
                <div className="page-sheet">
                  <span className="page-number">第 2 页</span>
                  <button
                    className="source-region region-c"
                    type="button"
                    onClick={() => toggleSegment('q-03')}
                  >
                    第 2 题下
                  </button>
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
                    actionLog.map((item) => <Typography.Text key={item}>{item}</Typography.Text>)
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

        </main>
        <aside className="admin-workspace" data-shell="admin-governance-staging" aria-hidden="true">
          <AdminGovernancePanels />
        </aside>
      </Layout>
    </ConfigProvider>
  )
}

export default App
