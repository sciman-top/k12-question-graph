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
  CloudUploadOutlined,
  FileSearchOutlined,
  FileTextOutlined,
  InboxOutlined,
  LinkOutlined,
  MergeCellsOutlined,
  SearchOutlined,
  SafetyCertificateOutlined,
  SplitCellsOutlined,
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

function App() {
  const [segments, setSegments] = useState(initialSegments)
  const [selectedIds, setSelectedIds] = useState<string[]>(['q-02', 'q-03'])
  const [selectedAsset, setSelectedAsset] = useState(sharedAssets[0])
  const [actionLog, setActionLog] = useState<string[]>([])
  const [paperRequest, setPaperRequest] = useState(initialPaperRequest)
  const [paperUnderstanding, setPaperUnderstanding] = useState(initialPaperUnderstanding)

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
              message="等待 P1 导入样本"
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
                  message="系统理解"
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
                    message="解析器失败可人工接管"
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
