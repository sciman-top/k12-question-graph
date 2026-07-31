import { Alert, Button, Input, Segmented, Select, Space, Spin, Tag, Typography } from 'antd'
import {
  ArrowUpOutlined,
  CheckCircleOutlined,
  ClearOutlined,
  FileSearchOutlined,
  FileTextOutlined,
  LinkOutlined,
  ReloadOutlined,
  SearchOutlined,
  ShoppingCartOutlined,
  SwapOutlined,
  UndoOutlined,
} from '@ant-design/icons'
import type {
  QuestionEvidenceCardContract,
  QuestionEvidenceMode,
  QuestionEvidenceSearchContract,
} from '../api/contracts'
import {
  initialPaperDraft,
  initialPaperUnderstanding,
  paperWorkbenchSteps,
  paperWorkbenchSummaryCards,
  questionEvidenceFilterOptions,
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
  questionEvidenceSearch?: QuestionEvidenceSearchContract
  questionEvidenceSearchError: boolean
  questionEvidenceSearchFetching: boolean
  questionEvidenceMode: QuestionEvidenceMode
  activeEvidenceFilter: string
  questionInteractionMessage: string
  selectedEvidenceQuestionId: string
  onPaperRequestChange: (value: string) => void
  onParsePaperRequest: () => void
  onConfirmPaperBlueprint: () => void
  onRefreshQuestionEvidence: () => void
  onEvidenceModeChange: (mode: QuestionEvidenceMode) => void
  onApplyEvidenceFilter: (filter: string, label: string) => void
  onClearEvidenceFilters: () => void
  onSelectEvidenceQuestion: (card: QuestionEvidenceCardContract) => void
  onOpenQuestionSource: (card: QuestionEvidenceCardContract, sourceKind: 'question' | 'answer') => void
  onReturnToBasket: () => void
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
  questionEvidenceSearch,
  questionEvidenceSearchError,
  questionEvidenceSearchFetching,
  questionEvidenceMode,
  activeEvidenceFilter,
  questionInteractionMessage,
  selectedEvidenceQuestionId,
  onPaperRequestChange,
  onParsePaperRequest,
  onConfirmPaperBlueprint,
  onRefreshQuestionEvidence,
  onEvidenceModeChange,
  onApplyEvidenceFilter,
  onClearEvidenceFilters,
  onSelectEvidenceQuestion,
  onOpenQuestionSource,
  onReturnToBasket,
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

      <section className="question-panel" aria-label="证据题库检索" data-flow="question-evidence-search">
        <div className="panel-heading">
          <div>
            <Typography.Title level={2}>证据题库</Typography.Title>
            <Typography.Text type="secondary" data-action="question-interaction-message">
              {questionInteractionMessage}
            </Typography.Text>
          </div>
          <Space size="small" wrap>
            <Tag color={questionEvidenceMode === 'active' ? 'green' : 'gold'}>
              {questionEvidenceMode === 'active' ? '正式题库' : '预览结果'}
            </Tag>
            <Button icon={<ArrowUpOutlined />} onClick={onReturnToBasket} data-action="return-to-basket">
              返回题篮
            </Button>
          </Space>
        </div>

        <div className="evidence-search-controls" aria-label="证据筛选">
          <Segmented
            block
            value={questionEvidenceMode}
            options={[
              { label: '正式题库', value: 'active' },
              { label: '已审核预览', value: 'reviewed' },
              { label: '候选预览', value: 'candidate' },
            ]}
            onChange={(value) => onEvidenceModeChange(value as QuestionEvidenceMode)}
          />
          <Select
            aria-label="证据筛选条件"
            value={activeEvidenceFilter}
            options={questionEvidenceFilterOptions.map(({ value, label }) => ({ value, label }))}
            onChange={(value) => {
              const selected = questionEvidenceFilterOptions.find((item) => item.value === value)
              onApplyEvidenceFilter(value, selected?.label ?? value)
            }}
          />
          <Button icon={<ClearOutlined />} onClick={onClearEvidenceFilters} data-action="clear-evidence-filters">
            清空
          </Button>
          <Button
            type="primary"
            icon={<SearchOutlined />}
            loading={questionEvidenceSearchFetching}
            onClick={onRefreshQuestionEvidence}
            data-action="question-evidence-search-refresh"
          >
            检索
          </Button>
        </div>

        {questionEvidenceMode !== 'active' ? (
          <Alert
            showIcon
            type="warning"
            title={questionEvidenceMode === 'candidate' ? '候选预览' : '已审核预览'}
            description="预览结果不会进入正式题篮。"
            data-state="question-evidence-preview-boundary"
          />
        ) : null}

        <div className="question-card-list" aria-label="证据题目卡片" data-contract="cek030-evidence-cards">
          {questionEvidenceSearchFetching && !questionEvidenceSearch ? (
            <div className="question-search-loading" data-state="question-evidence-loading">
              <Spin size="small" />
              <Typography.Text type="secondary">正在读取题库</Typography.Text>
            </div>
          ) : null}
          {questionEvidenceSearchError ? (
            <Alert
              showIcon
              type="warning"
              title="题库暂时无法连接"
              description="当前筛选已保留。"
              action={(
                <Button icon={<ReloadOutlined />} onClick={onRefreshQuestionEvidence}>
                  重试
                </Button>
              )}
              data-state="question-evidence-error"
            />
          ) : null}
          {!questionEvidenceSearchError && questionEvidenceSearch?.items.length === 0 ? (
            <Alert
              showIcon
              type="info"
              title="当前范围暂无题目"
              description={questionEvidenceMode === 'active' ? '正式题库尚无已激活证据题目。' : '当前预览范围无匹配题目。'}
              data-state="question-evidence-empty"
            />
          ) : null}
          {questionEvidenceSearch?.items.map((card) => {
            const target = card.assessmentTargets.find((item) => item.isPrimaryTarget) ?? card.assessmentTargets[0]
            const knowledge = target?.knowledge.find((item) => item.role === 'primary') ?? target?.knowledge[0]
            const requirement = target?.requirements[0]
            const observed = target?.observedDifficulty[0]
            const profile = target?.profiles[0]
            const mayAddToBasket = questionEvidenceMode === 'active' && card.productionEligible
            return (
              <article
                className={selectedEvidenceQuestionId === card.questionId ? 'question-card active' : 'question-card'}
                data-card="question-evidence-card"
                data-evidence-mode={questionEvidenceMode}
                key={card.questionId}
              >
                <div className="question-evidence-main">
                  <div className="question-evidence-title">
                    <strong>
                      {card.questionNo ? `第 ${card.questionNo} 题 · ` : ''}
                      {target?.targetStatement || '考查目标待确认'}
                    </strong>
                    <Space size="small" wrap>
                      <Tag>{teacherLabelFor(card.questionType ?? 'pending_review')}</Tag>
                      <Tag color={card.productionEligible ? 'green' : 'gold'}>
                        {card.productionEligible ? '可用于正式题篮' : teacherLabelFor(target?.reviewStatus ?? card.status)}
                      </Tag>
                    </Space>
                  </div>

                  <div className="question-evidence-grid">
                    <span>
                      <small>课标要求</small>
                      <b>{requirement?.displayName ?? '待补课标对齐'}</b>
                      {requirement ? (
                        <Tag color={requirement.originalBasis ? 'green' : 'gold'}>
                          {requirement.originalBasis ? '原命题依据' : '后设对齐'}
                        </Tag>
                      ) : null}
                    </span>
                    <span>
                      <small>考查目标</small>
                      <b>{target?.abilityDimensions.join('、') || '能力待确认'}</b>
                      <em>{knowledge?.displayName ?? '主知识待确认'}</em>
                    </span>
                    <span>
                      <small>广州画像</small>
                      <b>{profile?.displayName ?? '暂无匹配画像'}</b>
                      <em>{profile?.trendStatus ? teacherLabelFor(profile.trendStatus) : '趋势待补'}</em>
                    </span>
                    <span>
                      <small>难度</small>
                      <b>实测：{observed ? observed.value.toFixed(2) : '暂无'}</b>
                      <em>估计：{card.estimatedDifficulty === null ? '暂无' : card.estimatedDifficulty.toFixed(2)}</em>
                    </span>
                  </div>

                  <Space size="small" wrap className="question-evidence-tags">
                    {target?.cognitiveDemands.map((item) => <Tag key={`cognitive-${item}`}>{teacherLabelFor(item)}</Tag>)}
                    {target?.contextType ? <Tag>{teacherLabelFor(target.contextType)}</Tag> : null}
                    {target?.representationTypes.map((item) => <Tag key={`representation-${item}`}>{teacherLabelFor(item)}</Tag>)}
                    <Button
                      type="link"
                      size="small"
                      icon={<LinkOutlined />}
                      onClick={() => onOpenQuestionSource(card, 'question')}
                    >
                      试卷原页
                    </Button>
                    <Button
                      type="link"
                      size="small"
                      icon={<LinkOutlined />}
                      onClick={() => onOpenQuestionSource(card, 'answer')}
                    >
                      答案原页
                    </Button>
                    {requirement?.curriculumSourceDocumentId && requirement.curriculumSourcePageNumber ? (
                      <a
                        href={`/source-documents/${encodeURIComponent(requirement.curriculumSourceDocumentId)}/pages/${requirement.curriculumSourcePageNumber}/screenshot`}
                        target="_blank"
                        rel="noreferrer"
                      >
                        <LinkOutlined /> 课标原页
                      </a>
                    ) : null}
                    {observed?.sourceRegionId ? (
                      <a
                        href={`/source-regions/${encodeURIComponent(observed.sourceRegionId)}/page-screenshot`}
                        target="_blank"
                        rel="noreferrer"
                      >
                        <LinkOutlined /> 年报原页
                      </a>
                    ) : null}
                  </Space>
                </div>
                <Button
                  type="primary"
                  icon={<ShoppingCartOutlined />}
                  disabled={!mayAddToBasket}
                  onClick={() => onSelectEvidenceQuestion(card)}
                  data-action="add-evidence-question-to-basket"
                >
                  {mayAddToBasket ? '加入题篮' : '仅预览'}
                </Button>
              </article>
            )
          })}
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
