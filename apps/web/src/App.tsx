import { useMemo, useState } from 'react'
import {
  Alert,
  Badge,
  Button,
  ConfigProvider,
  Divider,
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
  { label: 'queued', value: 0 },
  { label: 'running', value: 0 },
  { label: 'failed', value: 0 },
  { label: 'retry_waiting', value: 0 },
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

function App() {
  const [segments, setSegments] = useState(initialSegments)
  const [selectedIds, setSelectedIds] = useState<string[]>(['q-02', 'q-03'])
  const [selectedAsset, setSelectedAsset] = useState(sharedAssets[0])
  const [actionLog, setActionLog] = useState<string[]>([])

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
                <Typography.Text type="secondary">ImportJob</Typography.Text>
                <Typography.Title level={3}>0</Typography.Title>
              </div>
              <Badge status="processing" text="API /health ready" />
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
                  draft_test 先验证题卡筛选合同，正式知识点激活后再进入生产筛题。
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
                synthetic
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
                    <Tag>{card.type}</Tag>
                    <Tag>{card.difficulty}</Tag>
                    <Tag>{card.source}</Tag>
                    <Tag color="green">{card.status}</Tag>
                  </span>
                </button>
              ))}
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
                    message="Adapter 失败可人工接管"
                    description="保留原始文件、SourceRegion 和 diagnostics，教师继续处理当前导入。"
                  />
                  <div className="diagnostics-row">
                    <Tag>adapter_failed</Tag>
                    <Typography.Text type="secondary">
                      stderr: layout block parse timeout
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
                    <Button onClick={() => takeoverFailure('重跑 Adapter')} data-action="rerun-adapter">
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
