import { useMemo, useState } from 'react'
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
  ClockCircleOutlined,
  DatabaseOutlined,
  DeleteOutlined,
  ExclamationCircleOutlined,
  FileSearchOutlined,
  FileTextOutlined,
  FolderOpenOutlined,
  InboxOutlined,
  LinkOutlined,
  MergeCellsOutlined,
  ReadOutlined,
  SearchOutlined,
  SafetyCertificateOutlined,
  SplitCellsOutlined,
  SwapOutlined,
  UndoOutlined,
} from '@ant-design/icons'
import './App.css'

const teacherActions = [
  {
    title: '导入试卷',
    description: '上传 Word、PDF 或图片试卷',
    icon: <CloudUploadOutlined />,
    status: 'P0',
  },
  {
    title: '找题组卷',
    description: '按知识点、题型和难度选题',
    icon: <FileSearchOutlined />,
    status: 'P4',
  },
  {
    title: '导入成绩',
    description: '导入 Excel 小题分和总分',
    icon: <FileTextOutlined />,
    status: 'P5',
  },
  {
    title: '查看分析',
    description: '查看班级薄弱点和讲评摘要',
    icon: <BarChartOutlined />,
    status: 'P5',
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
  },
  {
    id: 'q-02',
    title: '第 2 题上半部分',
    page: '第 1-2 页',
    region: 'x8 y76 w70 h20',
    asset: '',
  },
  {
    id: 'q-03',
    title: '第 2 题下半部分',
    page: '第 2 页',
    region: 'x8 y6 w70 h24',
    asset: '',
  },
]

const sharedAssets = ['图 A：滑轮组示意图', '图 B：电路图', '表 1：实验数据']

const questionCards = [
  {
    id: 'draft_test-card-001',
    title: '关于惯性的说法，下列哪项正确？',
    knowledge: '牛顿第一定律与惯性',
    type: 'single_choice',
    difficulty: '0.62',
    source: 'synthetic',
    status: 'draft_test',
  },
  {
    id: 'draft_test-card-002',
    title: '速度与平均速度计算',
    knowledge: '速度与平均速度',
    type: 'calculation',
    difficulty: '0.55',
    source: 'golden',
    status: 'draft_test',
  },
]

const displayText = {
  queued: '排队中',
  running: '处理中',
  failed: '失败',
  retry_waiting: '等待重试',
  single_choice: '单选题',
  calculation: '计算题',
  experiment: '实验题',
  short_answer: '简答题',
  synthetic: '示例来源',
  golden: '黄金样本',
  draft_test: '草稿测试',
  draft_dynamic_asset: '草稿动态资产',
  pending_review: '待审核',
  unit_practice: '单元练习',
  physics: '物理',
  grade_8: '八年级',
  medium: '中等',
  medium_hard: '中等偏难',
  textbook: '教材',
  curriculum_standard: '课程标准',
  local_exam_paper: '当地真题',
  exam_analysis_report: '考情年报',
  school_paper: '校本资料',
  teacher_original: '教师原创',
  uploaded_metadata: '已记录元数据',
} as const

type DisplayKey = keyof typeof displayText

const labelFor = (value: string) =>
  value in displayText ? displayText[value as DisplayKey] : value

const sourceMaterialTypes = [
  {
    type: 'textbook',
    title: '教材',
    requirement: '必需',
    use: '教材章节体系、章节到知识点映射',
  },
  {
    type: 'curriculum_standard',
    title: '课程标准',
    requirement: '必需',
    use: '课标条目、能力要求、知识要求',
  },
  {
    type: 'local_exam_paper',
    title: '当地真题',
    requirement: '必需',
    use: '考点、题型、分值、地区命题口径',
  },
  {
    type: 'exam_analysis_report',
    title: '考情年报',
    requirement: '强烈建议',
    use: '高频考点、趋势、易错点、权重',
  },
  {
    type: 'school_paper',
    title: '校本资料',
    requirement: '可选',
    use: '校本重点、教师经验、校本题库',
  },
]

const sourceMaterialUploads = [
  {
    title: '2025 本地中考物理真题.pdf',
    sourceType: 'local_exam_paper',
    region: '本地',
    year: '2025',
    status: 'uploaded_metadata',
  },
  {
    title: '义务教育物理课程标准.pdf',
    sourceType: 'curriculum_standard',
    region: '全国',
    year: '2022',
    status: 'uploaded_metadata',
  },
  {
    title: '2025 本地物理考情年报.pdf',
    sourceType: 'exam_analysis_report',
    region: '本地',
    year: '2025',
    status: 'uploaded_metadata',
  },
]

const activationOverview = {
  subject: '初中物理',
  region: '广州',
  yearRange: '2016-2025',
  lifecycle: '正式可用',
  activeAssets: 452,
  approvedMappings: 400,
  blockers: 0,
  backupStatus: '已备份',
}

const activationSteps = [
  {
    title: '资料批次',
    status: '已完成',
    description: '来源文件、hash 和导入批次已记录',
    icon: <FolderOpenOutlined />,
  },
  {
    title: '候选结果',
    status: '已完成',
    description: '系统整理知识点、教材、课标、考点和映射',
    icon: <FileSearchOutlined />,
  },
  {
    title: '教师复核',
    status: '已完成',
    description: '只检查明显错误和高影响映射',
    icon: <ReadOutlined />,
  },
  {
    title: '激活前检查',
    status: '已通过',
    description: '无阻断问题，备份和回滚入口已准备',
    icon: <SafetyCertificateOutlined />,
  },
  {
    title: '正式启用',
    status: '已完成',
    description: '本批内容可用于当前生产默认版本',
    icon: <CheckCircleOutlined />,
  },
]

const activationReviewItems = [
  { label: '知识点', count: 82, action: '抽样看层级和命名' },
  { label: '教材章节', count: 117, action: '看章节归属是否明显错位' },
  { label: '课标条目', count: 114, action: '看表述和知识点是否匹配' },
  { label: '广州考点', count: 47, action: '看是否符合本地中考口径' },
  { label: '映射关系', count: 975, action: '重点看一拆多、多合一和低置信度项' },
]

const storageAreas = [
  { name: '题库文件', bytes: '18.4 GB', files: 1248, cleanupAllowed: false },
  { name: '备份包', bytes: '42.7 GB', files: 37, cleanupAllowed: false },
  { name: '日志', bytes: '320 MB', files: 216, cleanupAllowed: false },
  { name: '缓存', bytes: '6.3 GB', files: 931, cleanupAllowed: true },
]

const cleanupPlan = {
  scope: '仅清理配置的缓存目录',
  dryRun: '先预览',
  retention: '保留最近 7 天',
  rollback: '清理前证据报告保留候选文件清单',
}

const initialPaperRequest =
  '八年级物理，牛顿第一定律与惯性，单选 5 题、计算 2 题、实验 1 题，总分 30 分，难度中等'

const initialPaperUnderstanding = {
  mode: 'draft_test',
  productionEligible: false,
  allowRealModelCalls: false,
  systemUnderstanding:
    '按初中物理 draft 动态资产生成组卷理解：八年级物理，牛顿第一定律与惯性，单选 5 题、计算 2 题、实验 1 题，总分 30 分，难度中等',
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
  const [segments, setSegments] = useState(initialSegments)
  const [selectedIds, setSelectedIds] = useState<string[]>(['q-02', 'q-03'])
  const [selectedAsset, setSelectedAsset] = useState(sharedAssets[0])
  const [actionLog, setActionLog] = useState<string[]>([])
  const [paperRequest, setPaperRequest] = useState(initialPaperRequest)
  const [paperUnderstanding, setPaperUnderstanding] = useState(initialPaperUnderstanding)
  const [paperDraft, setPaperDraft] = useState(initialPaperDraft)

  const selectedSegments = useMemo(
    () => segments.filter((segment) => selectedIds.includes(segment.id)),
    [segments, selectedIds],
  )

  const appendLog = (message: string) => {
    setActionLog((current) => [message, ...current].slice(0, 5))
  }

  const toggleSegment = (id: string) => {
    setSelectedIds((current) =>
      current.includes(id) ? current.filter((item) => item !== id) : [...current, id],
    )
  }

  const mergeSelected = () => {
    if (selectedSegments.length < 2) {
      return
    }

    const merged = {
      id: `q-${Date.now()}`,
      title: `${selectedSegments[0].title} 合并题`,
      page: selectedSegments.map((segment) => segment.page).join(' / '),
      region: selectedSegments.map((segment) => segment.region).join(' + '),
      asset: selectedSegments.find((segment) => segment.asset)?.asset ?? '',
    }
    const selected = new Set(selectedIds)
    setSegments((current) => [merged, ...current.filter((segment) => !selected.has(segment.id))])
    setSelectedIds([merged.id])
    appendLog(`已合并 ${selectedSegments.length} 个片段为 ${merged.title}`)
  }

  const splitSelected = () => {
    if (selectedSegments.length !== 1) {
      return
    }

    const [target] = selectedSegments
    const split = [
      { ...target, id: `${target.id}-a`, title: `${target.title} A`, region: `${target.region} 上半` },
      { ...target, id: `${target.id}-b`, title: `${target.title} B`, region: `${target.region} 下半` },
    ]
    setSegments((current) =>
      current.flatMap((segment) => (segment.id === target.id ? split : [segment])),
    )
    setSelectedIds(split.map((segment) => segment.id))
    appendLog(`已拆分 ${target.title}`)
  }

  const associateAsset = () => {
    if (selectedIds.length === 0) {
      return
    }

    const selected = new Set(selectedIds)
    setSegments((current) =>
      current.map((segment) =>
        selected.has(segment.id) ? { ...segment, asset: selectedAsset } : segment,
      ),
    )
    appendLog(`已关联 ${selectedAsset} 到 ${selectedIds.length} 个片段`)
  }

  const takeoverFailure = (action: string) => {
    appendLog(`失败接管：${action}`)
  }

  const undoLast = () => {
    setSegments(initialSegments)
    setSelectedIds(['q-02', 'q-03'])
    setActionLog((current) => [`已撤销：${current[0] ?? '最近操作'}`, ...current.slice(1)])
  }

  const parsePaperRequest = () => {
    setPaperUnderstanding((current) => ({
      ...current,
      systemUnderstanding: `按初中物理 draft 动态资产生成组卷理解：${paperRequest}`,
      scope: paperRequest.includes('速度') ? ['速度与平均速度'] : ['牛顿第一定律与惯性'],
      difficultyTarget: paperRequest.includes('偏难') ? 'medium_hard' : 'medium',
    }))
  }

  const replacePaperQuestion = () => {
    const replacement = {
      ...paperDraft.currentQuestion,
      id: `paper-q-replacement-${Date.now()}`,
      stemPreview: '关于惯性的理解，下列说法正确的是哪一项？',
      difficultyEstimated: Math.min(1, paperDraft.currentQuestion.difficultyEstimated + 0.03),
      recentUseStatus: 'not_recently_used',
    }
    setPaperDraft((current) => ({
      ...current,
      replacementQuestion: replacement,
      undoSnapshot: {
        undoToken: `undo-${Date.now()}`,
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

  const exportPaper = (format: 'docx' | 'pdf') => {
    appendLog(`已生成 ${format.toUpperCase()} draft_test 导出工件`)
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
            <Tag color="green">P0 骨架</Tag>
            <Tag>初中物理</Tag>
          </Space>
        </header>

        <main className="workspace">
          <section className="primary-panel" aria-label="普通教师入口">
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>今日工作台</Typography.Title>
                <Typography.Text type="secondary">
                  普通教师默认入口保持 4 个，高级配置后置。
                </Typography.Text>
              </div>
              <Button type="primary" icon={<InboxOutlined />} size="large">
                打开导入
              </Button>
            </div>

            <div className="action-grid">
              {teacherActions.map((action) => (
                <button className="action-card" key={action.title} type="button">
                  <span className="action-icon">{action.icon}</span>
                  <span className="action-copy">
                    <strong>{action.title}</strong>
                    <span>{action.description}</span>
                  </span>
                  <Tag>{action.status}</Tag>
                </button>
              ))}
            </div>
          </section>

          <section className="status-panel" aria-label="系统状态">
            <div className="status-strip">
              <div>
                <Typography.Text type="secondary">导入任务</Typography.Text>
                <Typography.Title level={3}>0</Typography.Title>
              </div>
              <Badge status="processing" text="服务已就绪" />
            </div>

            <Alert
              showIcon
              type="info"
              title="等待 P1 导入样本"
              description="当前只验证工程骨架和任务状态，不接真实 AI，不使用真实学生数据。"
            />

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
          </section>

          <section className="question-panel" aria-label="题库检索" data-flow="question-search">
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>题库检索</Typography.Title>
                <Typography.Text type="secondary">
                  草稿测试先验证题卡筛选合同，正式知识点激活后再进入生产筛题。
                </Typography.Text>
              </div>
              <Button icon={<SearchOutlined />}>检索</Button>
            </div>

            <div className="filter-row" aria-label="筛选条件">
              <button className="filter-chip" data-filter="knowledge" type="button">
                惯性
              </button>
              <button className="filter-chip" data-filter="question-type" type="button">
                单选题
              </button>
              <button className="filter-chip" data-filter="difficulty" type="button">
                0.4-0.7
              </button>
              <button className="filter-chip" data-filter="source" type="button">
                示例来源
              </button>
            </div>

            <div className="question-card-list" aria-label="题目卡片">
              {questionCards.map((card) => (
                <button className="question-card" data-card="question-card" key={card.id} type="button">
                  <span>
                    <strong>{card.title}</strong>
                    <small>{card.knowledge}</small>
                  </span>
                  <span className="question-meta">
                    <Tag>{labelFor(card.type)}</Tag>
                    <Tag>{card.difficulty}</Tag>
                    <Tag>{labelFor(card.source)}</Tag>
                    <Tag color="green">{labelFor(card.status)}</Tag>
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
                  先展示系统理解和细目表草稿，草稿测试不写生产组卷口径。
                </Typography.Text>
              </div>
              <Space size="small" wrap>
                <Tag color="green">{paperUnderstanding.mode}</Tag>
                <Tag data-contract="productionEligible=false">不进入生产</Tag>
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
                  onClick={parsePaperRequest}
                  data-action="parse-paper-request"
                >
                  生成理解
                </Button>
              </div>

              <div className="paper-understanding" data-contract="paper-understanding">
                <Alert
                  showIcon
                  type="info"
                  title="系统理解"
                  description={paperUnderstanding.systemUnderstanding}
                />
                <div className="paper-summary">
                  <span>
                    <strong>{paperUnderstanding.totalScore}</strong>
                    <small>总分</small>
                  </span>
                  <span>
                    <strong>{paperUnderstanding.difficultyTarget}</strong>
                    <small>难度目标</small>
                  </span>
                  <span>
                    <strong>{paperUnderstanding.scope.join('、')}</strong>
                    <small>draft 范围</small>
                  </span>
                </div>

                <div className="blueprint-table" data-contract="blueprint-draft">
                  {paperUnderstanding.blueprint.map((row) => (
                    <div className="blueprint-row" key={row.questionType}>
                      <strong>{labelFor(row.questionType)}</strong>
                      <span>{row.count} 题</span>
                      <span>{row.score} 分</span>
                      <Tag>{labelFor(row.assetStatus)}</Tag>
                      <Tag color="orange">{labelFor(row.reviewStatus)}</Tag>
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
                  保持约束一致，先生成可撤销草稿。
                </Typography.Text>
              </div>
              <Space size="small" wrap>
                <Tag color="green">{paperDraft.mode}</Tag>
                <Tag data-contract="replacement-productionEligible=false">不进入生产</Tag>
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
                  <Tag>{paperDraft.currentQuestion.difficultyEstimated.toFixed(2)}</Tag>
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
                    {(paperDraft.replacementQuestion?.difficultyEstimated ?? paperDraft.currentQuestion.difficultyEstimated).toFixed(2)}
                  </Tag>
                  <Tag>{paperDraft.replacementQuestion?.primaryKnowledgeTitle ?? paperDraft.currentQuestion.primaryKnowledgeTitle}</Tag>
                </Space>
              </div>
            </div>

            <div className="replacement-audit" data-contract="replacement-audit-trail">
              {[
                'sameKnowledge=true',
                'sameQuestionType=true',
                'similarDifficulty=true',
                'sameScore=true',
                'excludeRecentlyUsed=true',
                'knowledgeStatus=draft',
              ].map((item) => (
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
                  先导出可打印草稿，验证公式、题图和表格不丢失。
                </Typography.Text>
              </div>
              <Space size="small" wrap>
                <Tag color="green">draft_test</Tag>
                <Tag data-contract="export-productionEligible=false">不进入生产</Tag>
                <Tag data-contract="export-artifact-checks">工件校验</Tag>
              </Space>
            </div>

            <div className="export-workspace">
              <div className="export-preview" data-contract="export-preview">
                <Typography.Text type="secondary">样卷预览</Typography.Text>
                <Typography.Title level={3}>校本题谱 draft_test 导出样卷</Typography.Title>
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
            className="source-material-panel"
            aria-label="来源资料工作台"
            data-flow="source-material-workbench"
          >
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>来源资料工作台</Typography.Title>
                <Typography.Text type="secondary">
                  同一上传链路按资料类型分组，外部 AI（含 ChatGPT Web）初提炼只作为候选数据。
                </Typography.Text>
              </div>
              <Space size="small" wrap>
                <Tag color="green">C002I</Tag>
                <Tag data-contract="dual-evidence-chain">双证据链</Tag>
              </Space>
            </div>

            <div className="source-material-workspace">
              <div className="source-type-grid" data-contract="source-type-groups">
                {sourceMaterialTypes.map((item) => (
                  <button className="source-type-card" key={item.type} type="button">
                    <span>
                      <strong>{item.title}</strong>
                      <small>{item.use}</small>
                    </span>
                    <Tag color={item.requirement === '必需' ? 'red' : item.requirement === '可选' ? undefined : 'orange'}>
                      {item.requirement}
                    </Tag>
                  </button>
                ))}
              </div>

              <div className="source-upload-form" data-contract="source-material-metadata">
                <div className="source-form-grid">
                  <label>
                    资料类型
                    <select defaultValue="local_exam_paper" aria-label="资料类型">
                      {sourceMaterialTypes.map((item) => (
                        <option key={item.type} value={item.type}>
                          {item.title}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    地区
                    <Input defaultValue="本地" aria-label="地区" />
                  </label>
                  <label>
                    年份
                    <Input defaultValue="2025" aria-label="年份" />
                  </label>
                  <label>
                    批次
                    <Input defaultValue="local-physics-2015-2025" aria-label="批次" />
                  </label>
                </div>
                <div className="source-permission-row">
                  <Tag>可用于知识点提炼</Tag>
                  <Tag>可用于考点提炼</Tag>
                  <Tag>可用于趋势分析</Tag>
                  <Tag data-contract="productionEligible=false">不进入生产</Tag>
                </div>
                <Button icon={<CloudUploadOutlined />} data-action="upload-source-material">
                  上传来源资料
                </Button>
              </div>

              <div className="source-material-list" data-contract="source-material-list">
                {sourceMaterialUploads.map((item) => (
                  <div className="source-material-row" key={item.title}>
                    <span>
                      <strong>{item.title}</strong>
                      <small>
                        {labelFor(item.sourceType)} · {item.region} · {item.year}
                      </small>
                    </span>
                    <Tag color="green">{labelFor(item.status)}</Tag>
                  </div>
                ))}
              </div>
            </div>
          </section>

          <section
            className="activation-panel"
            aria-label="学科激活工作台"
            data-flow="subject-activation-workbench"
          >
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>学科激活</Typography.Title>
                <Typography.Text type="secondary">
                  教师只做复核和确认；脚本、备份、证据和回滚由系统处理。
                </Typography.Text>
              </div>
              <Space size="small" wrap>
                <Tag color="green" data-contract="activation-state">
                  {activationOverview.lifecycle}
                </Tag>
                <Tag data-contract="no-direct-activation">不在教师端直接激活</Tag>
              </Space>
            </div>

            <div className="activation-summary" data-contract="activation-readiness">
              <div>
                <Typography.Text type="secondary">学科</Typography.Text>
                <strong>{activationOverview.subject}</strong>
                <small>
                  {activationOverview.region} · {activationOverview.yearRange}
                </small>
              </div>
              <div>
                <Typography.Text type="secondary">正式资产</Typography.Text>
                <strong>{activationOverview.activeAssets}</strong>
                <small>知识点、教材、课标、考点等</small>
              </div>
              <div>
                <Typography.Text type="secondary">已确认映射</Typography.Text>
                <strong>{activationOverview.approvedMappings}</strong>
                <small>可追溯、可回滚</small>
              </div>
              <div>
                <Typography.Text type="secondary">阻断问题</Typography.Text>
                <strong>{activationOverview.blockers}</strong>
                <small>{activationOverview.backupStatus}</small>
              </div>
            </div>

            <div className="activation-flow" aria-label="激活进度">
              {activationSteps.map((step) => (
                <div className="activation-step" key={step.title}>
                  <span className="activation-step-icon">{step.icon}</span>
                  <span>
                    <strong>{step.title}</strong>
                    <small>{step.description}</small>
                  </span>
                  <Tag color="green">{step.status}</Tag>
                </div>
              ))}
            </div>

            <div className="activation-review" data-contract="teacher-review">
              <div className="activation-review-copy">
                <Typography.Title level={3}>教师需要做什么</Typography.Title>
                <Typography.Text>
                  不需要看脚本。只检查候选结果是否有明显错误；没有问题就提交复核结论。
                </Typography.Text>
              </div>
              <div className="activation-review-list">
                {activationReviewItems.map((item) => (
                  <div className="activation-review-row" key={item.label}>
                    <span>
                      <strong>{item.label}</strong>
                      <small>{item.action}</small>
                    </span>
                    <Tag>{item.count}</Tag>
                  </div>
                ))}
              </div>
            </div>

            <div className="activation-actions" data-contract="role-split">
              <Button icon={<ReadOutlined />} data-action="open-candidate-review">
                开始复核
              </Button>
              <Button icon={<CheckCircleOutlined />} data-action="open-activation-approval">
                查看确认表
              </Button>
              <Button icon={<FileTextOutlined />} data-action="open-activation-evidence">
                查看证据
              </Button>
              <Button icon={<ClockCircleOutlined />} data-action="open-rollback-summary">
                查看回滚
              </Button>
            </div>

            <Alert
              showIcon
              type="warning"
              icon={<ExclamationCircleOutlined />}
              title="正式激活只给管理员"
              description="普通教师侧不执行激活脚本；管理员确认前必须看到备份、阻断项、复核结论和回滚说明。"
              data-contract="rollback-ready"
            />
          </section>

          <section className="storage-panel" aria-label="存储看板" data-flow="admin-storage-dashboard">
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>存储看板</Typography.Title>
                <Typography.Text type="secondary">
                  管理员查看占用和清理缓存；普通教师不接触路径、脚本和证据文件。
                </Typography.Text>
              </div>
              <Space size="small" wrap>
                <Tag color="green">G002</Tag>
                <Tag data-contract="productionEligible=false">草稿测试</Tag>
              </Space>
            </div>

            <div className="storage-grid" data-contract="storage-summary">
              {storageAreas.map((area) => (
                <div className="storage-card" key={area.name} data-cleanup-allowed={area.cleanupAllowed}>
                  <span className="storage-icon">
                    <DatabaseOutlined />
                  </span>
                  <span>
                    <Typography.Text type="secondary">{area.name}</Typography.Text>
                    <strong>{area.bytes}</strong>
                    <small>{area.files} 个文件</small>
                  </span>
                  <Tag color={area.cleanupAllowed ? 'orange' : undefined}>
                    {area.cleanupAllowed ? '可清理' : '只读'}
                  </Tag>
                </div>
              ))}
            </div>

            <div className="cache-cleanup-panel" data-contract="cache-cleanup-configured-root">
              <div>
                <Typography.Title level={3}>缓存清理</Typography.Title>
                <Typography.Text>
                  {cleanupPlan.scope}，{cleanupPlan.dryRun}，{cleanupPlan.retention}。
                </Typography.Text>
                <small>{cleanupPlan.rollback}</small>
              </div>
              <Space wrap>
                <Button icon={<FileSearchOutlined />} data-action="storage-summary">
                  查看详情
                </Button>
                <Button icon={<DeleteOutlined />} data-action="cache-cleanup-dry-run">
                  预览清理
                </Button>
              </Space>
            </div>

            <Alert
              showIcon
              type="info"
              title="只清理缓存"
              description="文件仓库、备份包、学生成绩和正式资产不属于缓存清理范围。"
              data-contract="no-production-data-delete"
            />
          </section>

          <section className="review-panel" aria-label="导入确认" data-flow="manual-review">
            <div className="panel-heading">
              <div>
                <Typography.Title level={2}>导入确认</Typography.Title>
                <Typography.Text type="secondary">
                  处理跨页、误切和共用题图，只记录必要修正。
                </Typography.Text>
              </div>
              <Tag color="green">B004</Tag>
            </div>

            <div className="review-workspace">
              <div className="page-preview" aria-label="来源页预览">
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
                <div className="review-toolbar" aria-label="人工确认操作">
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
                            {segment.page} · {segment.region}
                          </small>
                        </span>
                        <Tag color={segment.asset ? 'green' : undefined}>
                          {segment.asset || '未关联题图'}
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

          <section className="guardrail-panel" aria-label="数据安全边界">
            <SafetyCertificateOutlined />
            <div>
              <Typography.Title level={3}>P0/P1 数据边界</Typography.Title>
              <Typography.Paragraph>
                fixture、日志、prompt 和外部 AI 调用默认不接收真实学生姓名、学号、班级和成绩。
              </Typography.Paragraph>
            </div>
          </section>
        </main>
      </Layout>
    </ConfigProvider>
  )
}

export default App
