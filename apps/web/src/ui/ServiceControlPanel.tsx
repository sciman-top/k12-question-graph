import {
  CheckCircleOutlined,
  ClockCircleOutlined,
  DatabaseOutlined,
  FolderOpenOutlined,
  LinkOutlined,
  SafetyCertificateOutlined,
} from '@ant-design/icons'
import { Alert, Button, Space, Tag, Typography } from 'antd'

const serviceControlOverview = {
  runtimeShape: 'Windows Service / 后台进程',
  runtime: 'win-x64',
  contentRoot: 'tmp/ns804/windows-service-package/api',
  dataRoot: 'D:/KQG_Data',
  logRoot: 'tmp/ns804/windows-service-package/published-api.out.log',
  healthStatus: '健康检查通过',
}

const serviceControlCards = [
  {
    key: 'service-status',
    label: '服务状态',
    value: serviceControlOverview.runtimeShape,
    detail: '默认服务端主形态，不依赖当前工作目录',
  },
  {
    key: 'content-root',
    label: 'content root',
    value: serviceControlOverview.contentRoot,
    detail: '程序目录与数据目录分离',
  },
  {
    key: 'data-root',
    label: 'data root',
    value: serviceControlOverview.dataRoot,
    detail: 'file store / backup / logs 均来自显式配置',
  },
  {
    key: 'health',
    label: 'health / readiness',
    value: serviceControlOverview.healthStatus,
    detail: 'worker script、content root 和 data root smoke 已通过',
  },
]

const serviceControlActions = [
  {
    label: '查看服务状态',
    action: 'service-status-overview',
    icon: <CheckCircleOutlined />,
  },
  {
    label: '查看诊断',
    action: 'service-open-diagnostics',
    icon: <SafetyCertificateOutlined />,
  },
  {
    label: '查看配置',
    action: 'service-open-config-diff',
    icon: <DatabaseOutlined />,
  },
  {
    label: '查看备份恢复',
    action: 'service-open-backup-restore',
    icon: <FolderOpenOutlined />,
  },
  {
    label: '查看升级演练',
    action: 'service-open-upgrade-rehearsal',
    icon: <ClockCircleOutlined />,
  },
  {
    label: '打开 Web 工作台',
    action: 'open-teacher-web-workbench',
    icon: <LinkOutlined />,
  },
]

const serviceControlReadiness = [
  {
    label: 'Windows Service 包',
    summary: 'package root、api executable、worker 脚本已封装',
    contract: 'windows-service-package-ready',
  },
  {
    label: '容量与健康',
    summary: 'file store / backup / cache / AI cost / failed task 信号可见',
    contract: 'service-control-health-diagnostics',
  },
  {
    label: '升级演练',
    summary: 'migration bundle、backup verify、restore drill 已留证',
    contract: 'service-control-upgrade-rehearsal',
  },
]

export function ServiceControlPanel() {
  return (
    <section
      className="service-control-panel"
      aria-label="服务端控制面板"
      data-flow="service-control-panel"
      data-contract="ns1302-admin-only"
    >
      <div className="panel-heading">
        <div>
          <Typography.Title level={2}>服务端控制面板</Typography.Title>
          <Typography.Text type="secondary">
            只做服务状态、诊断、配置、备份恢复、升级演练和打开 Web；不承载教师业务页面。
          </Typography.Text>
        </div>
        <Space size="small" wrap>
          <Tag color="green" data-contract="windows-service-default-host">
            Windows Service 默认主形态
          </Tag>
          <Tag data-contract="control-panel-admin-only">仅管理员入口</Tag>
        </Space>
      </div>

      <div className="service-control-grid" data-contract="service-control-roots-and-status">
        {serviceControlCards.map((item) => (
          <div className="service-control-card" key={item.key} data-service-key={item.key}>
            <span className="service-control-icon">
              <SafetyCertificateOutlined />
            </span>
            <span>
              <Typography.Text type="secondary">{item.label}</Typography.Text>
              <strong>{item.value}</strong>
              <small>{item.detail}</small>
            </span>
          </div>
        ))}
      </div>

      <div className="service-control-readiness" data-contract="service-control-readiness">
        {serviceControlReadiness.map((item) => (
          <div className="service-readiness-row" key={item.contract} data-contract={item.contract}>
            <span>
              <strong>{item.label}</strong>
              <small>{item.summary}</small>
            </span>
            <Tag color="green">已验证</Tag>
          </div>
        ))}
      </div>

      <div className="service-control-actions" data-contract="service-control-actions">
        {serviceControlActions.map((item) => (
          <Button key={item.action} icon={item.icon} data-action={item.action}>
            {item.label}
          </Button>
        ))}
      </div>

      <Alert
        showIcon
        type="info"
        title="控制面板不承载教师业务"
        description="不在这里复制导入、组卷、成绩分析等复杂工作流；普通教师仍从浏览器进入四个高频入口。"
        data-contract="no-teacher-workflow-in-control-panel"
      />
    </section>
  )
}
