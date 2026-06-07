import { Button, Tag, Typography } from 'antd'
import { InboxOutlined } from '@ant-design/icons'
import { apiContractSnapshot } from '../api/contracts'
import { uiStateBoundary } from '../state/uiState'
import {
  starterDemoSteps,
  teacherActions,
  type StarterDemoStep,
  type TeacherView,
} from './workbenchData'

type TeacherHomePanelContentProps = {
  activeTeacherView: TeacherView
  onOpenTeacherView: (view: TeacherView) => void
  onRunStarterDemo: (step: StarterDemoStep) => void
}

export function TeacherHomePanelContent({
  activeTeacherView,
  onOpenTeacherView,
  onRunStarterDemo,
}: TeacherHomePanelContentProps) {
  return (
    <>
      <div className="panel-heading">
        <div>
          <Typography.Title level={2}>今天要做什么</Typography.Title>
          <Typography.Text type="secondary">
            默认只放四件常用事，其他设置交给管理员。
          </Typography.Text>
        </div>
        <Button
          type="primary"
          icon={<InboxOutlined />}
          size="large"
          onClick={() => onOpenTeacherView('import')}
        >
          打开导入
        </Button>
      </div>

      <div className="action-grid">
        {teacherActions.map((action) => (
          <button
            className={
              activeTeacherView === action.view
                ? 'action-card active'
                : 'action-card'
            }
            key={action.title}
            type="button"
            onClick={() => onOpenTeacherView(action.view)}
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

      <div
        className="starter-demo"
        data-flow="first-run-starter-demo"
        data-contract="teacher-default-values"
      >
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
              onClick={() => onRunStarterDemo(step)}
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
    </>
  )
}
