import { Button, Typography } from 'antd'
import { analysisActions, teacherAnalysisHighlights } from './workbenchData'

type AnalysisPanelContentProps = {
  analysisMessage: string
  onOpenAnalysisSummary: () => void
}

export function AnalysisPanelContent({
  analysisMessage,
  onOpenAnalysisSummary,
}: AnalysisPanelContentProps) {
  return (
    <>
      <div className="panel-heading">
        <div>
          <Typography.Title level={2}>讲评分析</Typography.Title>
          <Typography.Text type="secondary">
            先看班级薄弱点，再决定讲评和练习。
          </Typography.Text>
        </div>
        {analysisActions.map((item) => (
          <Button
            key={item.action}
            icon={item.icon}
            onClick={onOpenAnalysisSummary}
            data-action={item.action}
          >
            {item.label}
          </Button>
        ))}
      </div>
      <Typography.Paragraph data-action="analysis-summary-message">
        {analysisMessage}
      </Typography.Paragraph>
      <div className="analysis-summary-grid">
        {teacherAnalysisHighlights.map(([label, value, detail]) => (
          <div key={label}>
            <Typography.Text type="secondary">{label}</Typography.Text>
            <strong>{value}</strong>
            <small>{detail}</small>
          </div>
        ))}
      </div>
    </>
  )
}
