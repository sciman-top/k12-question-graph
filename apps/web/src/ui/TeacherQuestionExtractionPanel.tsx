import { EditOutlined, SaveOutlined } from '@ant-design/icons'
import { Alert, Button, Input, Space, Tag, Typography } from 'antd'
import { useState } from 'react'
import type { QuestionDetailContract, QuestionSourceRegionContract } from '../api/contracts'
import { deriveTeacherQuestionExtraction } from './questionExtraction'

export type TeacherQuestionExtractionDraft = {
  stem: string
  options: Record<'A' | 'B' | 'C' | 'D', string>
  visualNeedsSeparateCrop: boolean
}

type Props = {
  question: QuestionDetailContract | null
  sourceRegions: QuestionSourceRegionContract[]
  saving?: boolean
  onSave: (draft: TeacherQuestionExtractionDraft) => void
}

const labels = ['A', 'B', 'C', 'D'] as const

function draftFor(question: QuestionDetailContract | null, sourceRegions: QuestionSourceRegionContract[]) {
  const extraction = deriveTeacherQuestionExtraction(question, sourceRegions)
  const options = Object.fromEntries(labels.map((label) => [
    label,
    extraction.options.find((option) => option.label === label)?.text ?? '',
  ])) as TeacherQuestionExtractionDraft['options']
  const visualNeedsSeparateCrop = question?.blocks.some(
    (block) => block.blockType === 'image' && block.content.status === 'needs_separate_crop',
  ) ?? false
  return { extraction, draft: { stem: extraction.stem, options, visualNeedsSeparateCrop } }
}

export function TeacherQuestionExtractionPanel({ question, sourceRegions, saving = false, onSave }: Props) {
  const initial = draftFor(question, sourceRegions)
  const [editingQuestionId, setEditingQuestionId] = useState<string | null>(null)
  const [draft, setDraft] = useState(initial.draft)

  const extraction = deriveTeacherQuestionExtraction(question, sourceRegions)
  const hasQuestion = Boolean(question)
  const editing = Boolean(question?.id && editingQuestionId === question.id)

  const startEditing = () => {
    setDraft(draftFor(question, sourceRegions).draft)
    setEditingQuestionId(question?.id ?? null)
  }

  return (
    <section className="teacher-question-extraction" aria-label="识别与校对" data-contract="teacher-question-extraction">
      <div className="teacher-question-extraction-head">
        <div>
          <Typography.Text type="secondary">完整原题为准</Typography.Text>
          <Typography.Title level={4}>识别与校对</Typography.Title>
        </div>
        <Tag color={extraction.requiresReview ? 'orange' : 'green'}>
          {extraction.requiresReview ? '待校对' : '已提取'}
        </Tag>
      </div>
      <Alert
        type={extraction.requiresReview ? 'warning' : 'success'}
        showIcon
        title={extraction.textStatus}
        description={extraction.visualStatus}
      />
      <div className="teacher-question-extraction-result">
        <div>
          <Typography.Text type="secondary">已识别题干</Typography.Text>
          <p>{extraction.stem || '暂未得到可用题干文字，请根据完整原题补录。'}</p>
        </div>
        {extraction.isChoiceQuestion ? (
          <div className="teacher-question-options" aria-label="已识别选项">
            {labels.map((label) => {
              const option = extraction.options.find((value) => value.label === label)
              return (
                <span key={label} className={option ? '' : 'missing'}>
                  <strong>{label}</strong>
                  <em>{option?.text || '未识别'}</em>
                </span>
              )
            })}
          </div>
        ) : null}
      </div>
      {editing ? (
        <div className="teacher-question-extraction-editor" aria-label="校对识别结果">
          <div>
            <Typography.Text type="secondary">题干</Typography.Text>
            <Input.TextArea
              aria-label="校对题干"
              value={draft.stem}
              onChange={(event) => setDraft((current) => ({ ...current, stem: event.target.value }))}
              autoSize={{ minRows: 2, maxRows: 6 }}
            />
          </div>
          {extraction.isChoiceQuestion ? (
            <div className="teacher-question-option-editor">
              {labels.map((label) => (
                <label key={label}>
                  <strong>{label}</strong>
                  <Input
                    aria-label={`校对选项 ${label}`}
                    value={draft.options[label]}
                    onChange={(event) => setDraft((current) => ({
                      ...current,
                      options: { ...current.options, [label]: event.target.value },
                    }))}
                    placeholder={`填写选项 ${label}`}
                  />
                </label>
              ))}
            </div>
          ) : null}
          <label className="teacher-question-visual-flag">
            <input
              type="checkbox"
              checked={draft.visualNeedsSeparateCrop}
              onChange={(event) => setDraft((current) => ({ ...current, visualNeedsSeparateCrop: event.target.checked }))}
            />
            原题中的题图或表格需要单独拆分
          </label>
          <Space wrap>
            <Button type="primary" icon={<SaveOutlined />} onClick={() => onSave(draft)} loading={saving} disabled={!hasQuestion}>
              保存为待复核
            </Button>
            <Button onClick={() => setEditingQuestionId(null)}>取消</Button>
          </Space>
          <Typography.Text type="secondary">保存只更新当前题的候选识别结果，不会自动通过本题，也不会进入正式题库。</Typography.Text>
        </div>
      ) : (
        <Button icon={<EditOutlined />} onClick={startEditing} disabled={!hasQuestion} data-action="open-teacher-question-extraction-editor">
          校对并补全识别结果
        </Button>
      )}
    </section>
  )
}
