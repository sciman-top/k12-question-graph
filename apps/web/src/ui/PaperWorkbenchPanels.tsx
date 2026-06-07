import { Alert, Button, Space, Tag, Typography, Input } from 'antd'
import {
  CheckCircleOutlined,
  FileSearchOutlined,
  FileTextOutlined,
  SearchOutlined,
  SwapOutlined,
  UndoOutlined,
} from '@ant-design/icons'
import type { QuestionSearchContract } from '../api/contracts'
import {
  initialPaperDraft,
  initialPaperUnderstanding,
  paperWorkbenchSteps,
  paperWorkbenchSummaryCards,
  questionSearchFilterChips,
  replacementAuditTags,
  labelFor,
} from './workbenchData'
import { teacherDifficultyLabelFor, teacherLabelFor } from './teacherLabels'

type PaperWorkbenchPanelsProps = {
  paperBasketId: string
  paperConstraintMessage: string
  paperBlueprintReviewId: string
  paperWorkflowBusy: boolean
  paperWorkflowMessage: string
  paperRequest: string
  paperUnderstanding: typeof initialPaperUnderstanding
  paperDraft: typeof initialPaperDraft
  questionSearch?: QuestionSearchContract
  questionSearchError: boolean
  questionSearchFetching: boolean
  activeQuestionFilter: string
  questionInteractionMessage: string
  selectedQuestionId: string
  onPaperRequestChange: (value: string) => void
  onParsePaperRequest: () => void
  onConfirmPaperBlueprint: () => void
  onRefreshQuestionSearch: () => void
  onApplyQuestionFilter: (filter: string, label: string) => void
  onSelectQuestionCard: (cardId: string, preview: string) => void
  onReplacePaperQuestion: () => void
  onUndoPaperReplacement: () => void
  onExportPaper: (format: 'docx' | 'pdf') => void
}

export function PaperWorkbenchPanels({
  paperBasketId,
  paperConstraintMessage,
  paperBlueprintReviewId,
  paperWorkflowBusy,
  paperWorkflowMessage,
  paperRequest,
  paperUnderstanding,
  paperDraft,
  questionSearch,
  questionSearchError,
  questionSearchFetching,
  activeQuestionFilter,
  questionInteractionMessage,
  selectedQuestionId,
  onPaperRequestChange,
  onParsePaperRequest,
  onConfirmPaperBlueprint,
  onRefreshQuestionSearch,
  onApplyQuestionFilter,
  onSelectQuestionCard,
  onReplacePaperQuestion,
  onUndoPaperReplacement,
  onExportPaper,
}: PaperWorkbenchPanelsProps) {
  return (
    <>
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
            <Tag color="green" data-contract="ten-minute-target">
              10 分钟目标
            </Tag>
            <Tag data-contract="single-workbench">单工作台</Tag>
          </Space>
        </div>

        <div className="paper-workbench-flow" aria-label="组卷流程">
          {paperWorkbenchSteps.map(([title, description], index) => (
            <div
              className="paper-workbench-step"
              key={title}
              data-contract={`paper-step-${index + 1}`}
            >
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
            <strong data-contract="paper-constraint-visible">
              {paperConstraintMessage}
            </strong>
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
              {questionSearch
                ? `${teacherLabelFor(questionSearch.knowledgeStatus)} v${questionSearch.knowledgeVersion ?? '-'}`
                : '校本题库'}
            </Tag>
            <Button
              icon={<SearchOutlined />}
              loading={questionSearchFetching}
              onClick={onRefreshQuestionSearch}
              data-action="question-search-refresh"
            >
              检索
            </Button>
          </Space>
        </div>

        <div className="filter-row" aria-label="筛选条件">
          {questionSearchFilterChips.map((item) => (
            <button
              className={
                activeQuestionFilter === item.filter
                  ? 'filter-chip active'
                  : 'filter-chip'
              }
              data-filter={item.filter}
              key={item.filter}
              type="button"
              onClick={() => onApplyQuestionFilter(item.filter, item.label)}
            >
              {item.label}
            </button>
          ))}
        </div>
        <Typography.Text type="secondary" data-action="question-interaction-message">
          {questionInteractionMessage}
        </Typography.Text>

        <div
          className="question-card-list"
          aria-label="题目卡片"
          data-contract="s008b-real-api-question-cards"
        >
          {questionSearchError ? (
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
            <button
              className={
                selectedQuestionId === card.id
                  ? 'question-card active'
                  : 'question-card'
              }
              data-card="question-card"
              key={card.id}
              type="button"
              onClick={() => onSelectQuestionCard(card.id, card.preview)}
            >
              <span>
                <strong>
                  {card.questionNo ? `第 ${card.questionNo} 题 · ` : ''}
                  {card.preview || '未命名题目'}
                </strong>
                <small>
                  {card.primaryKnowledge?.title ?? '待补知识点'} ·{' '}
                  {card.sources.titles[0] ?? '来源待补'}
                </small>
              </span>
              <span className="question-meta">
                <Tag>{teacherLabelFor(card.questionType)}</Tag>
                <Tag>
                  {teacherDifficultyLabelFor(card.difficultyEstimated ?? 0)}
                </Tag>
                <Tag>
                  {card.primaryKnowledge
                    ? `v${card.primaryKnowledge.version}`
                    : '待定版本'}
                </Tag>
                <Tag>
                  {card.sources.types[0]
                    ? teacherLabelFor(card.sources.types[0])
                    : '来源待补'}
                </Tag>
                <Tag color={card.sources.permissions.length > 0 ? 'green' : 'orange'}>
                  {card.sources.permissions[0]
                    ? teacherLabelFor(card.sources.permissions[0])
                    : '授权待确认'}
                </Tag>
                <Tag color={card.sources.sharingAllowed ? 'green' : 'gold'}>
                  {card.sources.sharingAllowed ? '可校内共享' : '共享受限'}
                </Tag>
                {card.sources.containsStudentPii ? (
                  <Tag color="red">含学生信息</Tag>
                ) : (
                  <Tag>无学生信息</Tag>
                )}
                {card.hasImage ? <Tag color="green">题图</Tag> : <Tag>无题图</Tag>}
                {!card.hasImage && card.sources.screenshotCount > 0 ? (
                  <Tag color="gold">有来源截图</Tag>
                ) : null}
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
              onChange={(event) => onPaperRequestChange(event.target.value)}
              autoSize={{ minRows: 4, maxRows: 6 }}
              data-contract="synthetic-paper-request"
            />
            <Button
              type="primary"
              icon={<FileSearchOutlined />}
              loading={paperWorkflowBusy}
              onClick={onParsePaperRequest}
              data-action="parse-paper-request"
            >
              生成理解
            </Button>
            <Button
              icon={<CheckCircleOutlined />}
              loading={paperWorkflowBusy}
              disabled={!paperBlueprintReviewId || Boolean(paperBasketId)}
              onClick={onConfirmPaperBlueprint}
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
                <strong>
                  {teacherDifficultyLabelFor(paperUnderstanding.difficultyTarget)}
                </strong>
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
            <Typography.Title level={3}>
              {paperDraft.currentQuestion.stemPreview}
            </Typography.Title>
            <Space size="small" wrap>
              <Tag>{labelFor(paperDraft.currentQuestion.questionType)}</Tag>
              <Tag>{paperDraft.currentQuestion.score} 分</Tag>
              <Tag>
                {teacherDifficultyLabelFor(
                  paperDraft.currentQuestion.difficultyEstimated,
                )}
              </Tag>
              <Tag>{paperDraft.currentQuestion.primaryKnowledgeTitle}</Tag>
            </Space>
          </div>

          <div className="replacement-actions">
            <Button
              type="primary"
              icon={<SwapOutlined />}
              onClick={onReplacePaperQuestion}
              data-action="replace-question"
            >
              换题
            </Button>
            <Button
              icon={<UndoOutlined />}
              onClick={onUndoPaperReplacement}
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
              <Tag>
                {labelFor(
                  paperDraft.replacementQuestion?.questionType ??
                    paperDraft.currentQuestion.questionType,
                )}
              </Tag>
              <Tag>
                {paperDraft.replacementQuestion?.score ??
                  paperDraft.currentQuestion.score}{' '}
                分
              </Tag>
              <Tag>
                {teacherDifficultyLabelFor(
                  paperDraft.replacementQuestion?.difficultyEstimated ??
                    paperDraft.currentQuestion.difficultyEstimated,
                )}
              </Tag>
              <Tag>
                {paperDraft.replacementQuestion?.primaryKnowledgeTitle ??
                  paperDraft.currentQuestion.primaryKnowledgeTitle}
              </Tag>
            </Space>
          </div>
        </div>

        <div className="replacement-audit" data-contract="replacement-audit-trail">
          {replacementAuditTags.map((item) => (
            <Tag key={item}>{item}</Tag>
          ))}
        </div>
      </section>

      <section className="paper-export-panel" aria-label="试卷导出" data-flow="paper-export">
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
              onClick={() => onExportPaper('docx')}
              data-action="export-docx"
            >
              导出 Word
            </Button>
            <Button
              icon={<FileTextOutlined />}
              onClick={() => onExportPaper('pdf')}
              data-action="export-pdf"
            >
              导出 PDF
            </Button>
          </div>
        </div>
      </section>
    </>
  )
}
