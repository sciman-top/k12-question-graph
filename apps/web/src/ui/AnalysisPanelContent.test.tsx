import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import type { ScoreEvidenceAnalysisContract } from '../api/contracts'
import { AnalysisPanelContent } from './AnalysisPanelContent'

function analysis(overrides: Partial<ScoreEvidenceAnalysisContract> = {}): ScoreEvidenceAnalysisContract {
  return {
    status: 'ready',
    mode: 'draft_test',
    productionEligible: false,
    realStudentDataUsed: false,
    writesProductionHistory: false,
    assessmentId: 'assessment-1',
    assessmentTitle: '八年级物理',
    scoreDerivedPerformance: [{
      questionNo: 'Q1',
      assessmentTargetStableKey: 'AT-1',
      targetStatement: '根据实验数据进行解释',
      scoreRecordCount: 20,
      averageScoreRate: 0.62,
      abilityDimensions: ['科学推理'],
      cognitiveDemands: ['分析'],
      evidenceRole: 'score_derived_performance',
    }],
    knowledgeMastery: [{
      stableId: 'KN-1',
      displayName: '力与运动',
      scoreRate: 0.62,
      scoreRecordCount: 20,
      questionNos: ['Q1'],
      version: 3,
      evidenceRole: 'score_derived_knowledge_mastery',
    }],
    abilityPerformance: [{
      stableId: '科学推理',
      displayName: '科学推理',
      scoreRate: 0.62,
      scoreRecordCount: 20,
      questionNos: ['Q1'],
      version: null,
      evidenceRole: 'score_derived_ability_performance',
    }],
    cognitivePerformance: [],
    observedContexts: [{
      evidenceId: 'observed-1',
      difficultyObserved: 0.52,
      scoreRate: 0.48,
      sampleScope: 'guangzhou_2024',
      sourceRegionId: 'region-1',
      contextRole: 'historical_year_report_context_not_current_cohort_measurement',
    }],
    errorPatternAssociations: [{
      evidenceId: 'error-1',
      kind: 'summary_candidate',
      content: '变量控制不完整',
      sourceRegionId: 'region-1',
      relation: 'reviewed_association_not_cause',
      diagnosisStatus: 'pending_teacher_confirmation',
    }],
    teachingRecommendations: [{
      recommendationId: 'recommendation-1',
      content: '先复核变量控制，再比较实验数据。',
      authorKind: 'report_author',
      generationMethod: 'verbatim',
      sourceRegionId: 'region-1',
      factRole: 'source_authored_recommendation_not_curriculum_fact',
    }],
    teacherConfirmedDiagnoses: [],
    diagnosisStatus: 'pending_teacher_confirmation',
    blockingIssues: [],
    teacherMessage: '证据分析预览已生成。',
    auditTrail: [],
    ...overrides,
  }
}

describe('AnalysisPanelContent', () => {
  it('keeps score, report context, error association, and authorship visibly distinct', () => {
    render(<AnalysisPanelContent analysisMessage="证据分析预览已生成。" analysis={analysis()} onOpenAnalysisSummary={vi.fn()} />)

    expect(screen.getByText('根据实验数据进行解释')).toBeInTheDocument()
    expect(screen.getByText('历史样本，不等同本班表现')).toBeInTheDocument()
    expect(screen.getByText('变量控制不完整')).toBeInTheDocument()
    expect(screen.getByText('待教师确认')).toBeInTheDocument()
    expect(screen.getByText('report_author')).toBeInTheDocument()
    expect(screen.getByText('先复核变量控制，再比较实验数据。')).toBeInTheDocument()
  })

  it('shows teacher-readable fail-closed blockers instead of a formal diagnosis', () => {
    render(<AnalysisPanelContent
      analysisMessage="分析被阻断。"
      analysis={analysis({
        status: 'blocked',
        scoreDerivedPerformance: [],
        blockingIssues: [{ scope: 'Q1', codes: ['assessment_target_not_reviewed'] }],
      })}
      onOpenAnalysisSummary={vi.fn()}
    />)

    expect(screen.getByText('分析暂未生成')).toBeInTheDocument()
    expect(screen.getByText(/Q1：考查目标尚未审核/)).toBeInTheDocument()
    expect(screen.queryByText(/assessment_target_not_reviewed/)).not.toBeInTheDocument()
    expect(screen.getByText('暂无可用数据')).toBeInTheDocument()
  })
})
