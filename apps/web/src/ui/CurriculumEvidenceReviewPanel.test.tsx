import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import type { CurriculumEvidenceReviewItemContract } from '../api/contracts'
import { CurriculumEvidenceReviewPanel } from './CurriculumEvidenceReviewPanel'

const api = vi.hoisted(() => ({
  decideCurriculumEvidence: vi.fn(),
  getCurriculumEvidenceReplacementOptions: vi.fn(),
  getCurriculumEvidenceReviews: vi.fn(),
  undoCurriculumEvidenceDecision: vi.fn(),
}))

vi.mock('../api/client', () => api)

const sourceRegionId = '11111111-2222-4333-8444-555555555555'

function reviewItem(overrides: Partial<CurriculumEvidenceReviewItemContract> = {}): CurriculumEvidenceReviewItemContract {
  return {
    candidateType: 'target',
    candidateId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
    stableKey: 'GZ-PHY-2024-Q01-T1',
    groupId: 'assessment_targets',
    reviewStatus: 'pending_review',
    confidence: 0.82,
    impactLevel: 'high',
    mappingType: null,
    alignmentType: 'source_cited',
    originalBasis: true,
    productionEligible: false,
    reversible: true,
    batchApprovalEligible: false,
    summary: {
      targetStatement: '识别重力与质量的关系',
      primaryKnowledge: [{ displayName: '重力与质量' }],
      secondaryKnowledge: [{ displayName: '密度' }],
      estimatedDifficulty: 0.62,
      observedDifficulty: [{
        value: 0.48,
        SampleScope: 'report-defined examination cohort',
        SourceRegionId: sourceRegionId,
      }],
    },
    evidence: {},
    ...overrides,
  }
}

function listResult(items = [reviewItem()]) {
  return {
    ok: true as const,
    data: {
      items,
      page: 1,
      pageSize: 12,
      totalCount: items.length,
      totalPages: 1,
      sort: 'impact_desc,confidence_asc,stable_key_asc',
      productionEligible: false,
      completionBoundary: 'candidate review only',
    },
  }
}

function renderPanel() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })
  render(
    <QueryClientProvider client={queryClient}>
      <CurriculumEvidenceReviewPanel />
    </QueryClientProvider>,
  )
  return queryClient
}

beforeAll(() => {
  class ResizeObserverStub {
    observe() {}
    unobserve() {}
    disconnect() {}
  }
  vi.stubGlobal('ResizeObserver', ResizeObserverStub)
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation((query: string) => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    })),
  })
})

beforeEach(() => {
  api.getCurriculumEvidenceReviews.mockReset().mockResolvedValue(listResult())
  api.getCurriculumEvidenceReplacementOptions.mockReset().mockResolvedValue({
    ok: true,
    data: { items: [], productionEligible: false, completionBoundary: 'candidate only' },
  })
  api.decideCurriculumEvidence.mockReset().mockResolvedValue({
    ok: true,
    data: {
      decisionId: 'decision-1',
      candidateType: 'target',
      candidateId: reviewItem().candidateId,
      decision: 'approve',
      reviewStatus: 'approved',
      productionEligible: false,
      activeApply: false,
      audit: {},
    },
  })
  api.undoCurriculumEvidenceDecision.mockReset().mockResolvedValue({
    ok: true,
    data: {
      decisionId: 'decision-1',
      candidateType: 'target',
      candidateId: reviewItem().candidateId,
      decision: 'approve',
      reviewStatus: 'pending_review',
      productionEligible: false,
      activeApply: false,
      audit: {},
    },
  })
})

describe('CurriculumEvidenceReviewPanel', () => {
  it('does not submit a decision without a review reason', async () => {
    renderPanel()
    await screen.findByText('识别重力与质量的关系')

    fireEvent.click(screen.getByRole('button', { name: /批准/ }))

    expect(await screen.findByText('请先填写审核理由。')).toBeInTheDocument()
    expect(api.decideCurriculumEvidence).not.toHaveBeenCalled()
  })

  it('submits a reasoned decision and can undo it', async () => {
    renderPanel()
    const reason = await screen.findByPlaceholderText('审核理由')
    fireEvent.change(reason, { target: { value: '来源与知识映射一致。' } })

    fireEvent.click(screen.getByRole('button', { name: /批准/ }))
    await waitFor(() => expect(api.decideCurriculumEvidence).toHaveBeenCalledWith(expect.objectContaining({
      decision: 'approve',
      reason: '来源与知识映射一致。',
    })))

    const undo = screen.getByRole('button', { name: /撤销/ })
    await waitFor(() => expect(undo).toBeEnabled())
    fireEvent.click(undo)
    await waitFor(() => expect(api.undoCurriculumEvidenceDecision).toHaveBeenCalledWith(
      'decision-1',
      expect.objectContaining({ reason: '教师撤销上一条审核决定。' }),
    ))
  })

  it('keeps an unsaved reason when refreshing the query fails', async () => {
    api.getCurriculumEvidenceReviews
      .mockResolvedValueOnce(listResult())
      .mockRejectedValueOnce(new Error('network unavailable'))
    renderPanel()
    const reason = await screen.findByPlaceholderText('审核理由')
    fireEvent.change(reason, { target: { value: '等待补充年报原页。' } })

    fireEvent.click(screen.getByRole('button', { name: '刷新审核列表' }))

    expect(await screen.findByText('审核列表暂时无法加载，请重试。')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('审核理由')).toHaveValue('等待补充年报原页。')
  })

  it('shows source type, knowledge roles, and distinct estimated and observed difficulty', async () => {
    renderPanel()

    expect(await screen.findByText('原始来源')).toBeInTheDocument()
    expect(screen.getByText('重力与质量')).toBeInTheDocument()
    expect(screen.getByText('密度')).toBeInTheDocument()
    expect(screen.getByText('题目估计难度')).toBeInTheDocument()
    expect(screen.getByText('0.62')).toBeInTheDocument()
    expect(screen.getByText('年报实测难度')).toBeInTheDocument()
    expect(screen.getByText('0.48（年报统计考生群体）')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /年报原页/ })).toHaveAttribute(
      'href',
      `/source-regions/${sourceRegionId}/page-screenshot`,
    )
  })

  it('opens curriculum document pages when an evidence anchor has no source region', async () => {
    const sourceDocumentId = '22222222-3333-4444-8555-666666666666'
    api.getCurriculumEvidenceReviews.mockResolvedValue(listResult([reviewItem({
      candidateType: 'requirement',
      alignmentType: null,
      originalBasis: false,
      summary: { displayName: '有节约用水和保护环境的意识' },
      evidence: {
        evidenceAnchors: [{
          evidenceRole: 'curriculum_facet_source',
          sourceDocumentId,
          pdfPageNumber: 12,
        }],
      },
    })]))
    renderPanel()

    expect(await screen.findByText('原页已关联')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /课标原页/ })).toHaveAttribute(
      'href',
      `/source-documents/${sourceDocumentId}/pages/12/screenshot`,
    )
  })

  it('labels paper, answer, and report anchor containers distinctly', async () => {
    api.getCurriculumEvidenceReviews.mockResolvedValue(listResult([reviewItem({
      summary: {
        targetStatement: '区分三类来源锚点',
        SourceRegionId: '11111111-1111-4111-8111-111111111111',
      },
      evidence: {
        paperAnchors: [{ sourceRegionId: '11111111-1111-4111-8111-111111111111' }],
        answerAnchors: [{ sourceRegionId: '22222222-2222-4222-8222-222222222222' }],
        reportAnchors: [{ sourceRegionId: '33333333-3333-4333-8333-333333333333' }],
      },
    })]))
    renderPanel()

    expect(await screen.findByRole('link', { name: /题目原页/ })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /答案原页/ })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /年报原页/ })).toBeInTheDocument()
  })

  it('uses the replacement allowlist for a mapping change', async () => {
    const alignment = reviewItem({
      candidateType: 'alignment',
      candidateId: 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff',
      stableKey: 'CR-PHY-001->KPHY-001',
    })
    api.getCurriculumEvidenceReviews.mockResolvedValue(listResult([alignment]))
    api.getCurriculumEvidenceReplacementOptions.mockResolvedValue({
      ok: true,
      data: {
        items: [{
          assetVersionId: 'cccccccc-dddd-4eee-8fff-000000000000',
          stableKey: 'KPHY-002',
          displayName: '惯性与牛顿第一定律',
        }],
        productionEligible: false,
        completionBoundary: 'candidate only',
      },
    })
    renderPanel()

    fireEvent.click(await screen.findByRole('button', { name: /改映射/ }))
    await waitFor(() => expect(api.getCurriculumEvidenceReplacementOptions).toHaveBeenCalledWith(alignment.candidateId))

    fireEvent.mouseDown(await screen.findByRole('combobox'))
    fireEvent.click(await screen.findByText('惯性与牛顿第一定律'))
    fireEvent.change(screen.getByPlaceholderText('审核理由'), { target: { value: '目标范围应调整。' } })
    fireEvent.click(screen.getByRole('button', { name: /提交映射修改/ }))

    await waitFor(() => expect(api.decideCurriculumEvidence).toHaveBeenCalledWith(expect.objectContaining({
      decision: 'change_mapping',
      replacementAssetVersionId: 'cccccccc-dddd-4eee-8fff-000000000000',
      reason: '目标范围应调整。',
    })))
  })
})
