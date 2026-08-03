import { Button, Space, Tag, Typography } from 'antd'
import { EditOutlined, FileSearchOutlined, SearchOutlined } from '@ant-design/icons'
import type { QuestionSourceRegionContract, ReviewQueueItemContract } from '../api/contracts'
import {
  formatRegionKind,
  hasRenderableImage,
  renderMathAwareText,
  sourceRegionRank,
  splitQuestionText,
  type RealExamPreviewRow,
} from './workbenchData'

type RealExamHeroProps = {
  queue: ReviewQueueItemContract[]
  queueTotal: number
  queueBusy: boolean
  queueMessage: string
  selectedReview?: ReviewQueueItemContract
  selectedPreview: RealExamPreviewRow
  previewRows: RealExamPreviewRow[]
  selectedEvidenceQuestionNo: number
  questionAssetRegions: QuestionSourceRegionContract[]
  sourceRegions: QuestionSourceRegionContract[]
  sourceSummary: string
  onLoadQueue: () => void
  onLoadSelected: () => void
  onConfirmSelected: () => void
  onSelectReview: (item: ReviewQueueItemContract) => void
  onSelectEvidence: (item: RealExamPreviewRow) => void
}

export function RealExamHero({
  queue,
  queueTotal,
  queueBusy,
  queueMessage,
  selectedReview,
  selectedPreview,
  previewRows,
  selectedEvidenceQuestionNo,
  questionAssetRegions,
  sourceRegions,
  sourceSummary,
  onLoadQueue,
  onLoadSelected,
  onConfirmSelected,
  onSelectReview,
  onSelectEvidence,
}: RealExamHeroProps) {
  return (
    <div className="real-exam-hero" data-contract="real-guangzhou-2015-primary-workbench" data-workflow="guangzhou-physics-2015-2025-v2">
      <div className="real-exam-hero-head">
        <div>
          <Typography.Text type="secondary">2015-2025 广州中考物理</Typography.Text>
          <Typography.Title level={2}>真卷复核</Typography.Title>
        </div>
        <Space size="small" wrap>
          <Tag color={queue.length > 0 ? 'green' : 'orange'}>
            {queue.length > 0 ? '数据库队列' : '本地证据预览'}
          </Tag>
          <Tag>{queue.length > 0 ? `${queueTotal} 题待复核` : 'REAL001 证据'}</Tag>
        </Space>
      </div>

      <div className="real-exam-focus">
        <div className="real-exam-question">
          <span className="real-exam-number">第 {selectedPreview.questionNo || '?'} 题</span>
          <div className="question-text" aria-label="题干">
            {splitQuestionText(selectedPreview.textPreview).map((line, index) => (
              <p key={`${selectedPreview.questionNo}-${index}`}>{renderMathAwareText(line)}</p>
            ))}
          </div>
          {questionAssetRegions.length > 0 ? (
            <div className="real-exam-inline-assets" aria-label="题图" data-contract="question-stem-asset-fusion">
              {questionAssetRegions.map((region) => (
                <a
                  key={region.id}
                  className="real-exam-inline-asset"
                  href={region.screenshotUrl ?? undefined}
                  target="_blank"
                  rel="noreferrer"
                >
                  <img
                    src={region.screenshotUrl ?? undefined}
                    alt={`第 ${selectedPreview.questionNo || '?'} 题题图，第 ${region.pageNumber} 页`}
                    loading="lazy"
                  />
                </a>
              ))}
            </div>
          ) : null}
          <div className="real-exam-tags">
            <Tag color="green">答案：{selectedPreview.answer || '-'}</Tag>
            <Tag color="blue">{selectedPreview.primaryKnowledgeLabel || '标签待确认'}</Tag>
            {selectedPreview.knowledgeTags.map((tag) => <Tag key={tag}>{tag}</Tag>)}
          </div>
        </div>
        <div className="real-exam-source-preview" aria-label="题图与来源区域">
          <div className="source-preview-head">
            <strong>来源回看</strong>
            <Tag color={sourceRegions.some(hasRenderableImage) ? 'green' : 'default'}>
              {sourceRegions.some(hasRenderableImage) ? '有来源图片' : '暂无可显示图片'}
            </Tag>
          </div>
          <div className="source-preview-list">
            {sourceRegions.length > 0 ? (
              [...sourceRegions]
                .sort((left, right) => sourceRegionRank(left.regionType) - sourceRegionRank(right.regionType))
                .map((region) => (
                  <span key={region.id} className={hasRenderableImage(region) ? 'source-preview-card has-image' : 'source-preview-card'}>
                    <strong>第 {region.pageNumber} 页 · {formatRegionKind(region.regionType)}</strong>
                    {hasRenderableImage(region) ? (
                      <span className="source-preview-image-frame">
                        <img
                          src={region.screenshotUrl ?? undefined}
                          alt={`第 ${region.pageNumber} 页 ${formatRegionKind(region.regionType)}`}
                          loading="lazy"
                        />
                      </span>
                    ) : null}
                    <span className="source-preview-actions">
                      {region.screenshotUrl ? <Button size="small" href={region.screenshotUrl} target="_blank" rel="noreferrer">打开裁图</Button> : null}
                      {region.pageScreenshotUrl ? <Button size="small" href={region.pageScreenshotUrl} target="_blank" rel="noreferrer">查看第 {region.pageNumber} 页</Button> : null}
                    </span>
                    <small>{region.sourceTitle ?? '来源文档'} · {region.regionType} · {region.screenshotRelativePath ?? '未生成截图'}</small>
                  </span>
                ))
            ) : (
              <span>
                <strong>未加载来源区域</strong>
                <small>点击“加载数据库队列”后显示题干和答案来源。</small>
              </span>
            )}
          </div>
          <Typography.Text type="secondary">{sourceSummary}</Typography.Text>
        </div>
        <div className="real-exam-actions">
          <Button type="primary" icon={<FileSearchOutlined />} onClick={onLoadQueue} loading={queueBusy} data-action="load-real-guangzhou-2015-review-queue-primary">
            加载数据库队列
          </Button>
          <Button icon={<SearchOutlined />} onClick={onLoadSelected} disabled={!selectedReview} data-action="load-real-guangzhou-2015-review-item-primary">
            载入当前题
          </Button>
          <Button icon={<EditOutlined />} onClick={onConfirmSelected} disabled={!selectedReview} data-action="confirm-real-guangzhou-2015-review-item-primary">
            确认当前题
          </Button>
          <Typography.Text type="secondary">{queueMessage}</Typography.Text>
        </div>
      </div>

      <div className="real-exam-strip" aria-label="广州中考题目列表">
        {previewRows.slice(0, 24).map((item) => {
          const active = selectedReview
            ? Number(selectedReview.payload.questionNo) === item.questionNo
            : selectedEvidenceQuestionNo === item.questionNo
          const liveItem = queue.find((row) => row.payload.questionNo === item.questionNo)
          return (
            <button
              key={`${item.questionNo}-${item.answer}`}
              type="button"
              className={active ? 'real-exam-chip active' : 'real-exam-chip'}
              onClick={() => liveItem ? onSelectReview(liveItem) : onSelectEvidence(item)}
            >
              <strong>{item.questionNo}</strong>
              <span>{item.primaryKnowledgeLabel}</span>
              <small>答案 {item.answer || '-'}</small>
            </button>
          )
        })}
      </div>
    </div>
  )
}
