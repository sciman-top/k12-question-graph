import {
  EditOutlined,
  FileSearchOutlined,
  SaveOutlined,
  SearchOutlined,
  UndoOutlined,
} from '@ant-design/icons'
import { Button, Input, InputNumber, Select, Space, Tag, Typography } from 'antd'
import type { QuestionSourceRegionContract, ReviewQueueItemContract } from '../api/contracts'
import { teacherDifficultyLabelFor, teacherLabelFor } from './teacherLabels'
import {
  formatRegionKind,
  realExamDifficultyOptions,
  reviewRiskColorFor,
  type RealExamRevisionState,
} from './workbenchData'

type CropField = 'x' | 'y' | 'width' | 'height'

type RealExamReviewWorkbenchProps = {
  queue: ReviewQueueItemContract[]
  queueTotal: number
  queueBusy: boolean
  queueMessage: string
  reviewYear: number
  selectedReviewId: string
  selectedReview?: ReviewQueueItemContract
  visibleQueue: ReviewQueueItemContract[]
  revision: RealExamRevisionState
  cropDraft: QuestionSourceRegionContract | null
  cropUndoAvailable: boolean
  loadedQuestionAvailable: boolean
  lastReviewedAvailable: boolean
  sourceSummary: string
  reviewNote: string
  onYearChange: (year: number) => void
  onRevisionChange: (patch: Partial<RealExamRevisionState>) => void
  onCropChange: (field: CropField, value: number) => void
  onSaveCrop: () => void
  onUndoCrop: () => void
  onReviewNoteChange: (value: string) => void
  onLoadQueue: () => void
  onLoadSelected: () => void
  onSaveSelected: () => void
  onConfirmSelected: () => void
  onDismissSelected: () => void
  onUndoLastReview: () => void
  onSelectReview: (item: ReviewQueueItemContract) => void
}

export function RealExamReviewWorkbench({
  queue,
  queueTotal,
  queueBusy,
  queueMessage,
  reviewYear,
  selectedReviewId,
  selectedReview,
  visibleQueue,
  revision,
  cropDraft,
  cropUndoAvailable,
  loadedQuestionAvailable,
  lastReviewedAvailable,
  sourceSummary,
  reviewNote,
  onYearChange,
  onRevisionChange,
  onCropChange,
  onSaveCrop,
  onUndoCrop,
  onReviewNoteChange,
  onLoadQueue,
  onLoadSelected,
  onSaveSelected,
  onConfirmSelected,
  onDismissSelected,
  onUndoLastReview,
  onSelectReview,
}: RealExamReviewWorkbenchProps) {
  return (
    <div className="real-exam-review" data-contract="real-guangzhou-2015-review-workbench" data-workflow="guangzhou-physics-2015-2025-v2">
      <div className="panel-heading compact">
        <div>
          <Typography.Text type="secondary">2015-2025 广州真卷</Typography.Text>
          <Typography.Title level={3}>逐题复核</Typography.Title>
        </div>
        <Tag color={queue.length > 0 ? 'orange' : 'default'}>
          {queue.length > 0 ? `${queue.length} 待确认` : '未加载'}
        </Tag>
      </div>
      <div className="review-summary" data-contract="real-exam-review-summary">
        <span>
          <Typography.Text type="secondary">队列总数</Typography.Text>
          <strong>{queueTotal}</strong>
        </span>
        <span>
          <Typography.Text type="secondary">当前题号</Typography.Text>
          <strong>{selectedReview?.payload.questionNo || '-'}</strong>
        </span>
        <span>
          <Typography.Text type="secondary">状态</Typography.Text>
          <strong>{queueBusy ? '查询中' : queue.length > 0 ? '待确认' : '未加载'}</strong>
        </span>
      </div>
      <Typography.Text>{queueMessage}</Typography.Text>
      <Select
        aria-label="真卷年份"
        value={reviewYear}
        options={Array.from({ length: 11 }, (_, index) => ({ value: 2015 + index, label: `${2015 + index} 年` }))}
        onChange={onYearChange}
        data-action="select-real-guangzhou-review-year"
      />
      <div className="real-exam-detail" data-contract="real-exam-review-detail">
        <span>
          <Typography.Text type="secondary">题干预览</Typography.Text>
          <strong>{selectedReview?.payload.textPreview || '请选择一题后载入'}</strong>
        </span>
        <span>
          <Typography.Text type="secondary">答案</Typography.Text>
          <strong>{selectedReview?.payload.answer || '-'}</strong>
        </span>
        <span>
          <Typography.Text type="secondary">标签</Typography.Text>
          <strong>
            {selectedReview?.payload.primaryKnowledgeLabel || '-'}
            {selectedReview?.payload.knowledgeTags.length
              ? ` · ${selectedReview.payload.knowledgeTags.join(' / ')}`
              : ''}
          </strong>
        </span>
        <span>
          <Typography.Text type="secondary">难度</Typography.Text>
          <strong>
            {revision.difficultyEstimated == null
              ? '-'
              : teacherDifficultyLabelFor(revision.difficultyEstimated)}
          </strong>
        </span>
        <span>
          <Typography.Text type="secondary">来源</Typography.Text>
          <strong>{sourceSummary}</strong>
        </span>
      </div>
      <div className="real-exam-revision" data-contract="real-exam-teacher-revision">
        <div>
          <Typography.Text type="secondary">修订题干</Typography.Text>
          <Input.TextArea
            aria-label="广州真卷修订题干"
            data-action="real-guangzhou-2015-revision-stem"
            value={revision.textPreview}
            onChange={(event) => onRevisionChange({ textPreview: event.target.value })}
            autoSize={{ minRows: 2, maxRows: 5 }}
            placeholder="载入题目后可修订题干"
          />
        </div>
        <div>
          <Typography.Text type="secondary">修订答案</Typography.Text>
          <Input.TextArea
            aria-label="广州真卷修订答案"
            data-action="real-guangzhou-2015-revision-answer"
            value={revision.answer}
            onChange={(event) => onRevisionChange({ answer: event.target.value })}
            autoSize={{ minRows: 2, maxRows: 5 }}
            placeholder="载入题目后可修订答案"
          />
        </div>
        <div>
          <Typography.Text type="secondary">修订标签</Typography.Text>
          <Input
            aria-label="广州真卷主标签"
            data-action="real-guangzhou-2015-revision-primary-tag"
            value={revision.primaryKnowledgeLabel}
            onChange={(event) => onRevisionChange({ primaryKnowledgeLabel: event.target.value })}
            placeholder="主标签"
          />
          <Input
            aria-label="广州真卷知识标签"
            data-action="real-guangzhou-2015-revision-tags"
            value={revision.knowledgeTagsText}
            onChange={(event) => onRevisionChange({ knowledgeTagsText: event.target.value })}
            placeholder="多个标签用 / 分隔"
          />
          <Select
            aria-label="真卷预估难度"
            value={revision.difficultyEstimated}
            options={realExamDifficultyOptions}
            onChange={(value) => onRevisionChange({ difficultyEstimated: value })}
            placeholder="选择难度"
            data-action="real-guangzhou-v2-revision-difficulty"
          />
        </div>
      </div>
      {cropDraft ? (
        <div className="real-exam-crop" data-contract="real-exam-source-recrop">
          <Typography.Text type="secondary">
            重裁区域：第 {cropDraft.pageNumber} 页 · {formatRegionKind(cropDraft.regionType)}
          </Typography.Text>
          <Space size="small" wrap>
            {(['x', 'y', 'width', 'height'] as const).map((field) => (
              <InputNumber
                key={field}
                aria-label={`重裁 ${field}`}
                min={0}
                max={100}
                step={1 / 10}
                value={cropDraft[field]}
                prefix={field}
                onChange={(value) => onCropChange(field, value ?? 0)}
                data-action={`real-guangzhou-v2-recrop-${field}`}
              />
            ))}
            <Button icon={<SaveOutlined />} onClick={onSaveCrop} data-action="save-real-guangzhou-v2-recrop">
              保存重裁
            </Button>
            <Button icon={<UndoOutlined />} disabled={!cropUndoAvailable} onClick={onUndoCrop} data-action="undo-real-guangzhou-v2-recrop">
              撤销重裁
            </Button>
          </Space>
        </div>
      ) : null}
      <Input.TextArea
        aria-label="广州真卷审核说明"
        data-action="real-guangzhou-2015-review-note"
        value={reviewNote}
        onChange={(event) => onReviewNoteChange(event.target.value)}
        autoSize={{ minRows: 2, maxRows: 4 }}
        placeholder="填写确认或退回说明"
      />
      <Space size="small" wrap>
        <Button icon={<FileSearchOutlined />} onClick={onLoadQueue} disabled={queueBusy} data-action="load-real-guangzhou-2015-review-queue">
          查询真卷队列
        </Button>
        <Button icon={<SearchOutlined />} onClick={onLoadSelected} disabled={!selectedReview} data-action="load-real-guangzhou-2015-review-item">
          载入当前题
        </Button>
        <Button icon={<SaveOutlined />} onClick={onSaveSelected} disabled={!selectedReview || !loadedQuestionAvailable} data-action="save-real-guangzhou-v2-review-revision">
          保存修订
        </Button>
        <Button type="primary" icon={<EditOutlined />} onClick={onConfirmSelected} disabled={!selectedReview} data-action="confirm-real-guangzhou-2015-review-item">
          确认当前题
        </Button>
        <Button icon={<UndoOutlined />} onClick={onDismissSelected} disabled={!selectedReview} data-action="dismiss-real-guangzhou-2015-review-item">
          退回当前题
        </Button>
        <Button icon={<UndoOutlined />} onClick={onUndoLastReview} disabled={!lastReviewedAvailable} data-action="undo-real-guangzhou-v2-review-item">
          撤销上次审核
        </Button>
      </Space>
      <div className="real-exam-list" aria-label={`${reviewYear} 年广州真卷待复核题目`}>
        {[...visibleQueue]
          .sort((left, right) => (left.payload.questionNo || 0) - (right.payload.questionNo || 0))
          .slice(0, 30)
          .map((item) => (
            <button
              key={item.id}
              type="button"
              className={item.id === selectedReviewId ? 'real-exam-row active' : 'real-exam-row'}
              onClick={() => onSelectReview(item)}
              data-review-type={item.reviewType}
            >
              <span>
                <strong>第 {item.payload.questionNo || '?'} 题</strong>
                <small>
                  {item.payload.year} 真卷复核 · {item.requiredActions.map(teacherLabelFor).join(' / ')}
                </small>
              </span>
              <Tag color={reviewRiskColorFor(item.riskLevel)}>
                {teacherLabelFor(`risk_${item.riskLevel}`)}
              </Tag>
            </button>
          ))}
      </div>
    </div>
  )
}
