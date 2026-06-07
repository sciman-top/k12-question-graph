import { Alert, Button, Input, Tag, Typography } from 'antd'
import { LinkOutlined } from '@ant-design/icons'
import {
  initialCommentaryReportPreview,
  initialItemScoreMappingPreview,
  scoreAnalysisHighlights,
  scoreFieldMappings,
  scoreWorkbenchActions,
  scoreWorkbenchSteps,
} from './workbenchData'
import { teacherLabelFor } from './teacherLabels'

type ScoreWorkbenchPanelContentProps = {
  scoreWorkflowBusy: boolean
  scoreMappingAssessmentId: string
  onScoreMappingAssessmentIdChange: (value: string) => void
  scoreMappingMessage: string
  itemScoreMappingPreview: typeof initialItemScoreMappingPreview
  commentaryReportPreview: typeof initialCommentaryReportPreview
  onHandleScoreWorkbenchAction: (action: string) => void
  onPreviewScoreMappings: () => void
}

export function ScoreWorkbenchPanelContent({
  scoreWorkflowBusy,
  scoreMappingAssessmentId,
  onScoreMappingAssessmentIdChange,
  scoreMappingMessage,
  itemScoreMappingPreview,
  commentaryReportPreview,
  onHandleScoreWorkbenchAction,
  onPreviewScoreMappings,
}: ScoreWorkbenchPanelContentProps) {
  return (
    <>
      <div className="score-workbench" data-flow="score-analysis-workbench">
        <div className="score-upload-lane">
          {scoreWorkbenchActions.map((item) => (
            <Button
              key={item.action}
              type={item.kind === 'primary' ? 'primary' : 'default'}
              icon={item.icon}
              loading={scoreWorkflowBusy && item.action !== 'export-score-report'}
              onClick={() => onHandleScoreWorkbenchAction(item.action)}
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
              onChange={(event) =>
                onScoreMappingAssessmentIdChange(event.target.value)
              }
              data-contract="s011b-assessment-id-input"
            />
            <Button
              icon={<LinkOutlined />}
              onClick={onPreviewScoreMappings}
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
                    {row.scoreRecordCount} 条成绩 · 得分率{' '}
                    {Math.round(row.averageScoreRate * 100)}%
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
          <strong>
            {commentaryReportPreview.artifactPath ||
              '导入后直接生成讲评摘要，再导出给备课使用。'}
          </strong>
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
            <span>
              <strong>{title}</strong>
              <small>{detail}</small>
            </span>
          </div>
        ))}
      </div>
    </>
  )
}
