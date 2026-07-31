import {
  CheckOutlined,
  CloseOutlined,
  FileSearchOutlined,
  HistoryOutlined,
  PauseOutlined,
  ReloadOutlined,
  SwapOutlined,
} from '@ant-design/icons'
import { useQuery } from '@tanstack/react-query'
import { Alert, Button, Empty, Input, Pagination, Segmented, Select, Space, Spin, Tag, Typography } from 'antd'
import { useState } from 'react'
import type {
  CurriculumEvidenceReplacementOptionContract,
  CurriculumEvidenceReviewItemContract,
} from '../api/contracts'
import {
  decideCurriculumEvidence,
  getCurriculumEvidenceReplacementOptions,
  getCurriculumEvidenceReviews,
  undoCurriculumEvidenceDecision,
} from '../api/client'

const groups = [
  { label: '高影响映射', value: 'complex_mappings' },
  { label: '低置信度', value: 'low_confidence_mappings' },
  { label: '课标要求', value: 'curriculum_requirements' },
  { label: '考查目标', value: 'assessment_targets' },
  { label: '地区画像', value: 'regional_profiles' },
]

const candidateLabels: Record<string, string> = {
  requirement: '课标要求',
  target: '考查目标',
  alignment: '证据对齐',
  error_pattern: '错误模式',
  profile: '广州画像',
}

function summaryText(item: CurriculumEvidenceReviewItemContract) {
  const values = [
    item.summary.displayName,
    item.summary.DisplayName,
    item.summary.targetStatement,
    item.summary.TargetStatement,
    item.summary.semanticType,
    item.summary.SemanticType,
    item.summary.standardVersion,
    item.summary.StandardVersion,
  ]
  const first = values.find((value) => typeof value === 'string' && value.trim())
  return typeof first === 'string' ? first : item.stableKey
}

type SourceAnchor = {
  role: string
  sourceRegionId: string | null
  sourceDocumentId: string | null
  pageNumber: number | null
}

function readString(record: Record<string, unknown>, ...keys: string[]) {
  for (const key of keys) {
    const value = record[key]
    if (typeof value === 'string' && value.trim()) return value.trim()
  }
  return null
}

function sourceRoleFromContainer(key: string) {
  const normalized = key.toLowerCase()
  if (normalized.includes('answer')) return 'answer'
  if (normalized.includes('report') || normalized.includes('observeddifficulty')) return 'report'
  if (normalized.includes('paper') || normalized.includes('question')) return 'paper'
  if (normalized.includes('curriculum')) return 'curriculum'
  return ''
}

function collectSourceAnchors(value: unknown, inheritedRole = '', result: SourceAnchor[] = []) {
  if (Array.isArray(value)) {
    value.forEach((entry) => collectSourceAnchors(entry, inheritedRole, result))
    return result
  }
  if (!value || typeof value !== 'object') return result
  const record = value as Record<string, unknown>
  const role = readString(record, 'role', 'Role', 'sourceRole', 'SourceRole', 'evidenceRole', 'EvidenceRole') ?? inheritedRole
  const sourceRegionId = readString(record, 'sourceRegionId', 'SourceRegionId', 'source_region_id')
  const sourceDocumentId = readString(record, 'sourceDocumentId', 'SourceDocumentId', 'source_document_id')
  const pageValue = record.pageNumber ?? record.PageNumber ?? record.page_number
    ?? record.pdfPageNumber ?? record.PdfPageNumber ?? record.pdf_page_number
  const pageNumber = typeof pageValue === 'number' ? pageValue : null
  const duplicate = result.find((entry) => sourceRegionId
    ? entry.sourceRegionId === sourceRegionId
    : entry.sourceDocumentId === sourceDocumentId && entry.pageNumber === pageNumber)
  if (duplicate) {
    if (!duplicate.role && role) duplicate.role = role
    if (!duplicate.sourceDocumentId && sourceDocumentId) duplicate.sourceDocumentId = sourceDocumentId
    if (!duplicate.pageNumber && pageNumber) duplicate.pageNumber = pageNumber
  } else if (sourceRegionId || (sourceDocumentId && pageNumber)) {
    result.push({
      role,
      sourceRegionId,
      sourceDocumentId,
      pageNumber,
    })
  }
  Object.entries(record).forEach(([key, entry]) => {
    const nestedRole = role || sourceRoleFromContainer(key)
    collectSourceAnchors(entry, nestedRole, result)
  })
  return result
}

function sourceRoleLabel(role: string) {
  if (role.includes('answer')) return '答案原页'
  if (role.includes('report')) return '年报原页'
  if (role.includes('curriculum')) return '课标原页'
  if (role.includes('paper') || role.includes('question')) return '题目原页'
  return '证据原页'
}

function sourceAnchorHref(anchor: SourceAnchor) {
  if (anchor.sourceRegionId) {
    return `/source-regions/${encodeURIComponent(anchor.sourceRegionId)}/page-screenshot`
  }
  return `/source-documents/${encodeURIComponent(anchor.sourceDocumentId ?? '')}/pages/${anchor.pageNumber}/screenshot`
}

function readKnowledgeNames(value: unknown) {
  if (!Array.isArray(value)) return []
  return value.flatMap((entry) => {
    if (!entry || typeof entry !== 'object') return []
    const record = entry as Record<string, unknown>
    const label = readString(record, 'displayName', 'DisplayName', 'stableId', 'StableId')
    return label ? [label] : []
  })
}

function knowledgeFacts(item: CurriculumEvidenceReviewItemContract) {
  const summaryPrimary = readKnowledgeNames(item.summary.primaryKnowledge ?? item.summary.PrimaryKnowledge)
  const summarySecondary = readKnowledgeNames(item.summary.secondaryKnowledge ?? item.summary.SecondaryKnowledge)
  const evidencePrimary = readString(
    item.evidence,
    'primaryKnowledgeLabel',
    'primaryKnowledgeId',
    'primary_knowledge_label',
    'primary_knowledge_id',
  )
  const evidenceSecondary = readString(
    item.evidence,
    'secondaryKnowledgeLabel',
    'secondaryKnowledgeId',
    'secondary_knowledge_label',
    'secondary_knowledge_id',
  )
  const mappingTarget = item.stableKey.split('->').at(-1)
  return {
    primary: summaryPrimary.join('、') || evidencePrimary || (mappingTarget?.startsWith('KPHY-') ? mappingTarget : '未提炼'),
    secondary: summarySecondary.join('、') || evidenceSecondary || '未提炼',
  }
}

function formatDifficulty(value: number) {
  return value.toFixed(2).replace(/0+$/, '').replace(/\.$/, '')
}

function sampleScopeLabel(value: string) {
  if (value === 'report-defined examination cohort') return '年报统计考生群体'
  return value
}

function difficultyFacts(item: CurriculumEvidenceReviewItemContract) {
  const estimatedValue = item.summary.estimatedDifficulty
    ?? item.summary.EstimatedDifficulty
    ?? item.evidence.estimatedDifficulty
    ?? item.evidence.difficultyEstimated
  const observedValue = item.summary.observedDifficulty
    ?? item.summary.ObservedDifficulty
    ?? item.evidence.observedDifficulty
    ?? item.evidence.difficultyObserved
  const observed = (Array.isArray(observedValue) ? observedValue : [observedValue]).flatMap((entry) => {
    if (typeof entry === 'number') return [formatDifficulty(entry)]
    if (!entry || typeof entry !== 'object') return []
    const record = entry as Record<string, unknown>
    const value = record.value ?? record.Value
    if (typeof value !== 'number') return []
    const sampleScope = readString(record, 'sampleScope', 'SampleScope')
    return [`${formatDifficulty(value)}${sampleScope ? `（${sampleScopeLabel(sampleScope)}）` : ''}`]
  })
  return {
    estimated: typeof estimatedValue === 'number' ? formatDifficulty(estimatedValue) : '未提供',
    observed: observed.length > 0 ? observed.join('、') : '未提供',
  }
}

function mappingLabel(value: string | null) {
  if (value === 'broader') return '范围更宽'
  if (value === 'narrower') return '范围更窄'
  if (value === 'equivalent') return '一一对应'
  if (value === 'retrospective') return '后设映射'
  return value ?? '直接证据'
}

function evidenceLabel(item: CurriculumEvidenceReviewItemContract, anchors: SourceAnchor[]) {
  if (item.alignmentType === 'retrospective_crosswalk') return '后设对齐'
  if (item.alignmentType === 'source_cited') return '原始来源'
  if (item.alignmentType === 'contemporaneous_inferred') return '同期推断'
  return anchors.length > 0 ? '原页已关联' : '待补原页'
}

export function CurriculumEvidenceReviewPanel() {
  const [groupId, setGroupId] = useState('complex_mappings')
  const [page, setPage] = useState(1)
  const [mutationBusy, setMutationBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [reasonById, setReasonById] = useState<Record<string, string>>({})
  const [replacementById, setReplacementById] = useState<Record<string, string>>({})
  const [replacementOptionsById, setReplacementOptionsById] = useState<Record<string, CurriculumEvidenceReplacementOptionContract[]>>({})
  const [mappingEditorId, setMappingEditorId] = useState<string | null>(null)
  const [replacementLoadingId, setReplacementLoadingId] = useState<string | null>(null)
  const [lastDecisionId, setLastDecisionId] = useState<string | null>(null)
  const reviewQuery = useQuery({
    queryKey: ['curriculum-evidence-reviews', groupId, page, 12],
    queryFn: () => getCurriculumEvidenceReviews({ groupId, page, pageSize: 12 }),
    retry: false,
    staleTime: 5_000,
  })
  const reviewData = reviewQuery.data?.ok ? reviewQuery.data.data : null
  const items = reviewData?.items ?? []
  const total = reviewData?.totalCount ?? 0
  const loadFailed = reviewQuery.isError || reviewQuery.data?.ok === false
  const busy = mutationBusy || reviewQuery.isFetching
  const messageType = message.startsWith('已') ? 'success' : 'warning'

  const pendingCount = items.filter((item) => item.reviewStatus === 'pending_review').length

  async function decide(
    item: CurriculumEvidenceReviewItemContract,
    decision: 'approve' | 'return' | 'change_mapping' | 'keep_pending',
  ) {
    const reason = reasonById[item.candidateId]?.trim() ?? ''
    if (!reason) {
      setMessage('请先填写审核理由。')
      return
    }
    const replacementAssetVersionId = replacementById[item.candidateId]
    if (decision === 'change_mapping' && !replacementAssetVersionId) {
      setMessage('请先选择新的知识或课标目标。')
      return
    }
    setMutationBusy(true)
    try {
      const result = await decideCurriculumEvidence({
        candidateType: item.candidateType,
        candidateId: item.candidateId,
        decision,
        reviewer: 'teacher-ui-local',
        reason,
        actorRole: 'teacher',
        ...(decision === 'change_mapping' ? { replacementAssetVersionId } : {}),
      })
      if (result.ok) {
        setLastDecisionId(result.data.decisionId)
        setMessage(
          decision === 'approve'
            ? '已批准候选。'
            : decision === 'return'
              ? '已退回候选。'
              : decision === 'change_mapping'
                ? '已提交新的映射目标，候选保持待审。'
                : '已保持待审。',
        )
        await reviewQuery.refetch()
      } else {
        setMessage('审核决定未保存，请检查候选状态后重试。')
      }
    } finally {
      setMutationBusy(false)
    }
  }

  async function openMappingEditor(item: CurriculumEvidenceReviewItemContract) {
    if (mappingEditorId === item.candidateId) {
      setMappingEditorId(null)
      return
    }
    setMappingEditorId(item.candidateId)
    if (replacementOptionsById[item.candidateId]) return
    setReplacementLoadingId(item.candidateId)
    const result = await getCurriculumEvidenceReplacementOptions(item.candidateId)
    if (result.ok) {
      setReplacementOptionsById((current) => ({ ...current, [item.candidateId]: result.data.items }))
      if (result.data.items.length === 0) setMessage('当前候选没有同边界的可替换目标。')
    } else {
      setMessage('可替换目标暂时无法加载，审核理由仍已保留。')
    }
    setReplacementLoadingId(null)
  }

  async function undoLast() {
    if (!lastDecisionId) return
    setMutationBusy(true)
    try {
      const result = await undoCurriculumEvidenceDecision(lastDecisionId, {
        reviewer: 'teacher-ui-local',
        reason: '教师撤销上一条审核决定。',
        actorRole: 'teacher',
      })
      setMessage(result.ok ? '上一条审核决定已撤销。' : '无法撤销：候选可能已被其他审核更新。')
      if (result.ok) setLastDecisionId(null)
      await reviewQuery.refetch()
    } finally {
      setMutationBusy(false)
    }
  }

  return (
    <section className="curriculum-evidence-review" aria-label="课程与考情证据审核" data-contract="cek026-curriculum-evidence-review">
      <div className="panel-heading curriculum-review-heading">
        <div>
          <Typography.Text type="secondary">课程标准 × 中考证据</Typography.Text>
          <Typography.Title level={3}>教师证据审核</Typography.Title>
        </div>
        <Space wrap>
          <Tag color="orange">本页待审 {pendingCount}</Tag>
          <Button icon={<HistoryOutlined />} disabled={!lastDecisionId || busy} onClick={() => void undoLast()}>撤销</Button>
          <Button icon={<ReloadOutlined />} disabled={busy} onClick={() => void reviewQuery.refetch()} aria-label="刷新审核列表" />
        </Space>
      </div>

      <Segmented
        block
        options={groups}
        value={groupId}
        onChange={(value) => { setGroupId(String(value)); setPage(1) }}
      />

      {message ? <Alert showIcon type={messageType} title={message} /> : null}
      {!message && loadFailed ? <Alert showIcon type="warning" title="审核列表暂时无法加载，请重试。" /> : null}
      <Spin spinning={busy}>
        <div className="curriculum-review-list">
          {items.length === 0 && !busy && !loadFailed ? <Empty description="当前分组没有候选" /> : null}
          {items.map((item) => {
            const anchors = collectSourceAnchors([item.summary, item.evidence]).slice(0, 4)
            const knowledge = knowledgeFacts(item)
            const difficulty = difficultyFacts(item)
            return (
            <article className="curriculum-review-row" key={`${item.candidateType}-${item.candidateId}`}>
              <div className="curriculum-review-main">
                <Space size="small" wrap>
                  <Tag>{candidateLabels[item.candidateType] ?? '候选证据'}</Tag>
                  <Tag color={item.impactLevel === 'high' ? 'red' : item.impactLevel === 'medium' ? 'orange' : 'green'}>
                    {item.impactLevel === 'high' ? '高影响' : item.impactLevel === 'medium' ? '中影响' : '低影响'}
                  </Tag>
                  <Tag color={item.alignmentType === 'retrospective_crosswalk' ? 'gold' : anchors.length > 0 ? 'blue' : 'default'}>
                    {evidenceLabel(item, anchors)}
                  </Tag>
                </Space>
                <strong>{summaryText(item)}</strong>
                <small>{item.stableKey}</small>
                <div className="curriculum-review-facts">
                  <span>置信度 <b>{Math.round(item.confidence * 100)}%</b></span>
                  <span>关系 <b>{mappingLabel(item.mappingType ?? item.alignmentType)}</b></span>
                  <span>状态 <b>{item.reviewStatus === 'pending_review' ? '待审核' : item.reviewStatus}</b></span>
                  <span>主知识 <b>{knowledge.primary}</b></span>
                  <span>次知识 <b>{knowledge.secondary}</b></span>
                  <span>题目估计难度 <b>{difficulty.estimated}</b></span>
                  <span>年报实测难度 <b>{difficulty.observed}</b></span>
                </div>
                <div className="curriculum-review-sources" aria-label="来源原页">
                  {anchors.length > 0 ? anchors.map((anchor) => (
                    <Button
                      key={anchor.sourceRegionId ?? `${anchor.sourceDocumentId}:${anchor.pageNumber}`}
                      type="link"
                      size="small"
                      icon={<FileSearchOutlined />}
                      href={sourceAnchorHref(anchor)}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {sourceRoleLabel(anchor.role)}{anchor.pageNumber ? ` · 第 ${anchor.pageNumber} 页` : ''}
                    </Button>
                  )) : <Typography.Text type="secondary">暂无可回看的原页锚点</Typography.Text>}
                </div>
              </div>
              <div className="curriculum-review-actions">
                <Input.TextArea
                  autoSize={{ minRows: 2, maxRows: 3 }}
                  value={reasonById[item.candidateId] ?? ''}
                  onChange={(event) => setReasonById((current) => ({ ...current, [item.candidateId]: event.target.value }))}
                  placeholder="审核理由"
                  maxLength={300}
                />
                <Space wrap>
                  <Button type="primary" icon={<CheckOutlined />} disabled={busy} onClick={() => void decide(item, 'approve')}>批准</Button>
                  <Button danger icon={<CloseOutlined />} disabled={busy} onClick={() => void decide(item, 'return')}>退回</Button>
                  <Button icon={<PauseOutlined />} disabled={busy} onClick={() => void decide(item, 'keep_pending')}>待审</Button>
                  {item.candidateType === 'alignment' ? (
                    <Button icon={<SwapOutlined />} disabled={busy} onClick={() => void openMappingEditor(item)}>改映射</Button>
                  ) : null}
                </Space>
                {mappingEditorId === item.candidateId ? (
                  <div className="curriculum-mapping-editor">
                    <Select
                      showSearch
                      optionFilterProp="label"
                      loading={replacementLoadingId === item.candidateId}
                      value={replacementById[item.candidateId]}
                      onChange={(value) => setReplacementById((current) => ({ ...current, [item.candidateId]: value }))}
                      placeholder="选择新的知识或课标目标"
                      options={(replacementOptionsById[item.candidateId] ?? []).map((option) => ({
                        value: option.assetVersionId,
                        label: option.displayName || option.stableKey,
                      }))}
                    />
                    <Button
                      icon={<SwapOutlined />}
                      disabled={!replacementById[item.candidateId] || busy}
                      onClick={() => void decide(item, 'change_mapping')}
                    >
                      提交映射修改
                    </Button>
                  </div>
                ) : null}
              </div>
            </article>
            )
          })}
        </div>
      </Spin>
      <Pagination
        className="curriculum-review-pagination"
        current={page}
        pageSize={12}
        total={total}
        showSizeChanger={false}
        onChange={setPage}
        hideOnSinglePage
        responsive
      />
    </section>
  )
}
