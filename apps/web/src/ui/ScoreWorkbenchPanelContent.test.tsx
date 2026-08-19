import { render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { ScoreWorkbenchPanelContent } from './ScoreWorkbenchPanelContent'
import { initialCommentaryReportPreview, initialItemScoreMappingPreview } from './workbenchData'

function renderPanel(scoreImportPreview: Parameters<typeof ScoreWorkbenchPanelContent>[0]['scoreImportPreview']) {
  return render(
    <ScoreWorkbenchPanelContent
      scoreWorkflowBusy={false}
      scoreMappingAssessmentId="assessment-1"
      onScoreMappingAssessmentIdChange={vi.fn()}
      scoreMappingMessage="成绩已导入"
      itemScoreMappingPreview={initialItemScoreMappingPreview}
      commentaryReportPreview={initialCommentaryReportPreview}
      scoreImportPreview={scoreImportPreview}
      scoreQuestionMappings={{}}
      scoreQuestionOptions={[]}
      onScoreQuestionMappingChange={vi.fn()}
      onUploadScoreSheet={vi.fn()}
      onHandleScoreWorkbenchAction={vi.fn()}
      onPreviewScoreMappings={vi.fn()}
    />,
  )
}

describe('ScoreWorkbenchPanelContent', () => {
  it('renders the uploaded workbook mapping and actual row errors', () => {
    renderPanel({
      fieldMapping: {
        studentKey: 'student_code',
        totalScore: 'total_score',
        itemScores: { Q1: 'Q1(5分)', Q2: 'Q2(5分)' },
      },
      errors: [{ rowNumber: 4, code: 'item_score_out_of_range', message: '小题 Q2 分数超出范围。', fields: ['Q2(5分)'] }],
      rowCount: 3,
      importedCount: 2,
      errorCount: 1,
    })

    const mapping = screen.getByText('字段映射预览').parentElement
    expect(mapping).not.toBeNull()
    expect(within(mapping!).getByText('student_code')).toBeInTheDocument()
    expect(within(mapping!).getByText('Q1(5分)')).toBeInTheDocument()
    expect(screen.getByText('小题 Q2 分数超出范围。（Q2(5分)）')).toBeInTheDocument()
    expect(screen.queryByText('q2_score 超过满分，暂不导入')).not.toBeInTheDocument()
  })

  it('does not invent mapping rows or exception rows before a file is uploaded', () => {
    renderPanel(null)

    expect(screen.getByText('选择真实 Excel 文件后，这里会显示实际异常行。')).toBeInTheDocument()
    expect(screen.queryByText('student_key')).not.toBeInTheDocument()
    expect(screen.queryByText('第 3 行')).not.toBeInTheDocument()
  })
})
