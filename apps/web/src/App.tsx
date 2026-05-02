import {
  Alert,
  Badge,
  Button,
  ConfigProvider,
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
  SafetyCertificateOutlined,
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

function App() {
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
