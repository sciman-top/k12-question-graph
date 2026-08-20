import type { QuestionBlockContract, QuestionDetailContract, QuestionSourceRegionContract } from '../api/contracts'

type TeacherQuestionOption = {
  label: 'A' | 'B' | 'C' | 'D'
  text: string
  blockId?: string
}

type TeacherQuestionExtraction = {
  stem: string
  options: TeacherQuestionOption[]
  isChoiceQuestion: boolean
  textStatus: string
  visualStatus: string
  requiresReview: boolean
}

const choiceLabels = ['A', 'B', 'C', 'D'] as const
const optionMarker = /(?:^|\s)([A-D])\s*[.．、]/g

function normalizeText(value: unknown) {
  return typeof value === 'string' ? value.replace(/\s+/g, ' ').trim() : ''
}

function optionTextFromBlock(block: QuestionBlockContract): TeacherQuestionOption | null {
  const label = normalizeText(block.content.label).toUpperCase()
  const text = normalizeText(block.content.text ?? block.content.value)
  return choiceLabels.includes(label as TeacherQuestionOption['label']) && text
    ? { label: label as TeacherQuestionOption['label'], text, blockId: block.id }
    : null
}

function optionsEmbeddedInStem(text: string): { stem: string; options: TeacherQuestionOption[] } {
  const matches = [...text.matchAll(optionMarker)]
  const first = matches.findIndex((match) => match[1] === 'A')
  if (first < 0) return { stem: text, options: [] }

  const options: TeacherQuestionOption[] = []
  let previous = first
  for (const label of choiceLabels) {
    const match = matches[previous]
    if (!match || match[1] !== label) break
    const next = matches[previous + 1]
    const value = normalizeText(text.slice((match.index ?? 0) + match[0].length, next?.index))
    if (!value) break
    options.push({ label, text: value })
    previous += 1
  }

  return options.length > 0
    ? { stem: normalizeText(text.slice(0, matches[first].index)), options }
    : { stem: text, options: [] }
}

export function deriveTeacherQuestionExtraction(
  question: QuestionDetailContract | null,
  sourceRegions: QuestionSourceRegionContract[],
): TeacherQuestionExtraction {
  const blocks = question?.blocks ?? []
  const stemBlock = blocks.find((block) => block.blockType === 'stem')
  const rawStem = normalizeText(stemBlock?.content.text)
  const structuredOptions = blocks
    .filter((block) => block.blockType === 'option')
    .map(optionTextFromBlock)
    .filter((option): option is TeacherQuestionOption => option !== null)
    .sort((left, right) => choiceLabels.indexOf(left.label) - choiceLabels.indexOf(right.label))
  const embedded = optionsEmbeddedInStem(rawStem)
  const options = structuredOptions.length > 0 ? structuredOptions : embedded.options
  const isChoiceQuestion = Boolean(question?.questionType?.includes('choice'))
  const tableDetected = blocks.some((block) => block.blockType === 'table')
  const imageBlock = blocks.find((block) => block.blockType === 'image')
  const independentlyExtractedFigure = imageBlock?.content.status === 'extracted'
  const figureNeedsSeparateCrop = imageBlock?.content.status === 'needs_separate_crop'
  const questionVisualSegments = sourceRegions.filter((region) => region.regionType.includes('question'))
  const visualStatus = independentlyExtractedFigure
    ? '题图：已拆分为独立题图，仍待校对归属。'
    : figureNeedsSeparateCrop
      ? '题图或表格：已标记为需要拆分，等待后续处理。'
    : tableDetected
      ? '表格：已检测到，内容仍需结合完整原题校对。'
      : questionVisualSegments.length > 1
        ? `题图或表格：已随完整原题保留（${questionVisualSegments.length} 段），尚未单独拆分。`
        : '题图或表格：未单独提取；如原题含图，请在校对中标记。'
  const textStatus = !rawStem
    ? '题干文字尚未识别。'
    : isChoiceQuestion && options.length < 4
      ? `选择题文本不完整：目前只识别到 ${options.length}/4 个选项。`
      : isChoiceQuestion && structuredOptions.length === 4
        ? '题干与 4 个选项已提取，仍待校对。'
        : isChoiceQuestion
          ? '辅助文本中识别到 4 个选项，可能混有页眉或题图文字，需对照原题校对。'
        : '题干文字已提取，仍待校对。'

  return {
    stem: structuredOptions.length > 0 ? rawStem : embedded.stem,
    options,
    isChoiceQuestion,
    textStatus,
    visualStatus,
    requiresReview: !rawStem || (isChoiceQuestion && structuredOptions.length < 4) || !independentlyExtractedFigure,
  }
}
