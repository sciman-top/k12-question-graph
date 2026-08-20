import { Alert, Button, Tag, Typography } from 'antd'
import type { ScoreEvidenceAnalysisContract } from '../api/contracts'
import { analysisActions } from './workbenchData'

const teacherIssueLabels: Record<string, string> = {
  question_mapping_missing: '题目尚未完成映射',
  question_mapping_ambiguous: '题目映射存在多个候选',
  question_not_found: '找不到对应题目',
  knowledge_mapping_missing: '知识点尚未完成映射',
  knowledge_version_mapping_missing: '知识点版本尚未完成映射',
  knowledge_version_ambiguous: '知识点版本存在歧义',
  assessment_target_mapping_missing: '考查目标尚未完成映射',
  assessment_target_not_reviewed: '考查目标尚未审核',
  assessment_target_ambiguous: '考查目标存在歧义',
  student_pii_detected: '检测到学生隐私字段',
  score_rows_missing: '没有可分析的成绩行',
}

function formatBlockingIssue(scope: string, codes: string[]) {
  const teacherScope = scope === 'assessment' ? '本次成绩' : scope
  const labels = codes.map((code) => teacherIssueLabels[code] ?? code).join('、')
  return `${teacherScope}：${labels}`
}

type AnalysisPanelContentProps = {
  analysisMessage: string
  analysis: ScoreEvidenceAnalysisContract
  onOpenAnalysisSummary: () => void
}

export function AnalysisPanelContent({
  analysisMessage,
  analysis,
  onOpenAnalysisSummary,
}: AnalysisPanelContentProps) {
  const weakestKnowledge = analysis.knowledgeMastery[0]
  const weakestAbility = analysis.abilityPerformance[0]

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
      {analysis.blockingIssues.length > 0 && (
        <Alert
          type="warning"
          showIcon
          title="分析暂未生成"
          description={analysis.blockingIssues
            .map((issue) => formatBlockingIssue(issue.scope, issue.codes))
            .join('；')}
          data-state="score-evidence-analysis-blocked"
        />
      )}
      <div className="analysis-summary-grid" data-contract="cek032-score-evidence-analysis">
        <div>
          <Typography.Text type="secondary">知识掌握</Typography.Text>
          <strong>{weakestKnowledge ? `${Math.round(weakestKnowledge.scoreRate * 100)}%` : '--'}</strong>
          <small>{weakestKnowledge?.displayName ?? '等待已审核映射'}</small>
        </div>
        <div>
          <Typography.Text type="secondary">能力表现</Typography.Text>
          <strong>{weakestAbility ? `${Math.round(weakestAbility.scoreRate * 100)}%` : '--'}</strong>
          <small>{weakestAbility?.displayName ?? '等待考查目标'}</small>
        </div>
        <div>
          <Typography.Text type="secondary">年报背景</Typography.Text>
          <strong>{analysis.observedContexts.length}</strong>
          <small>历史样本，不等同本班表现</small>
        </div>
        <div>
          <Typography.Text type="secondary">错因诊断</Typography.Text>
          <strong>{analysis.teacherConfirmedDiagnoses.length}</strong>
          <small>教师已确认</small>
        </div>
      </div>
      <div className="analysis-evidence-layers">
        <section aria-label="考查目标表现" data-evidence-role="score-derived-performance">
          <Typography.Title level={3}>考查目标表现</Typography.Title>
          {analysis.scoreDerivedPerformance.length === 0 ? (
            <Typography.Text type="secondary">暂无可用数据</Typography.Text>
          ) : analysis.scoreDerivedPerformance.map((item) => (
            <div className="analysis-evidence-row" key={`${item.questionNo}-${item.assessmentTargetStableKey}`}>
              <span><strong>{item.questionNo}</strong> {item.targetStatement}</span>
              <Tag>{Math.round(item.averageScoreRate * 100)}%</Tag>
            </div>
          ))}
        </section>
        <section aria-label="相关错因" data-evidence-role="association-not-cause">
          <Typography.Title level={3}>相关错因</Typography.Title>
          {analysis.errorPatternAssociations.length === 0 ? (
            <Typography.Text type="secondary">暂无已审核线索</Typography.Text>
          ) : analysis.errorPatternAssociations.map((item) => (
            <div className="analysis-evidence-row" key={item.evidenceId}>
              <span>{item.content}</span>
              <Tag color="gold">待教师确认</Tag>
            </div>
          ))}
        </section>
        <section aria-label="讲评建议" data-evidence-role="source-authored-recommendation">
          <Typography.Title level={3}>讲评建议</Typography.Title>
          {analysis.teachingRecommendations.length === 0 ? (
            <Typography.Text type="secondary">暂无已审核建议</Typography.Text>
          ) : analysis.teachingRecommendations.map((item) => (
            <div className="analysis-evidence-row" key={item.recommendationId}>
              <span>{item.content}</span>
              <Tag>{item.authorKind}</Tag>
            </div>
          ))}
        </section>
      </div>
    </>
  )
}
