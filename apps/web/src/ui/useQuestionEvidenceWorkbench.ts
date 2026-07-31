import { useState } from 'react'
import { getQuestionSources } from '../api/client'
import type { QuestionEvidenceCardContract, QuestionEvidenceMode } from '../api/contracts'
import { useQuestionEvidenceSearchQuery } from '../api/queries'
import { questionEvidenceParamsFor, resolveSourcePreviewUrl } from './workbenchData'

export function useQuestionEvidenceWorkbench(appendLog: (message: string) => void) {
  const [questionEvidenceMode, setQuestionEvidenceMode] = useState<QuestionEvidenceMode>('active')
  const [activeEvidenceFilter, setActiveEvidenceFilter] = useState('all')
  const [questionEvidenceSearchParams, setQuestionEvidenceSearchParams] = useState(
    () => questionEvidenceParamsFor('all', 'active'),
  )
  const [selectedEvidenceQuestionId, setSelectedEvidenceQuestionId] = useState('')
  const [questionInteractionMessage, setQuestionInteractionMessage] = useState(
    '选择题目后，可用于组卷、换题或来源回看。',
  )
  const questionEvidenceSearchQuery = useQuestionEvidenceSearchQuery(questionEvidenceSearchParams)
  const questionEvidenceSearch = questionEvidenceSearchQuery.data?.ok
    ? questionEvidenceSearchQuery.data.data
    : undefined

  const applyEvidenceFilter = (filter: string, label: string) => {
    setActiveEvidenceFilter(filter)
    setQuestionEvidenceSearchParams(questionEvidenceParamsFor(filter, questionEvidenceMode))
    setQuestionInteractionMessage('已应用筛选：' + label)
    appendLog('已应用证据题库筛选：' + label)
  }

  const changeQuestionEvidenceMode = (mode: QuestionEvidenceMode) => {
    setQuestionEvidenceMode(mode)
    setSelectedEvidenceQuestionId('')
    setQuestionEvidenceSearchParams(questionEvidenceParamsFor(activeEvidenceFilter, mode))
    setQuestionInteractionMessage(
      mode === 'active' ? '已切换到正式题库。' : mode === 'reviewed' ? '已切换到已审核预览。' : '已切换到候选预览。',
    )
  }

  const clearEvidenceFilters = () => {
    setActiveEvidenceFilter('all')
    setQuestionEvidenceSearchParams(questionEvidenceParamsFor('all', questionEvidenceMode))
    setQuestionInteractionMessage('已清空证据筛选。')
  }

  const openQuestionEvidenceSource = async (
    card: QuestionEvidenceCardContract,
    sourceKind: 'question' | 'answer',
  ) => {
    const sourceWindow = window.open('about:blank', '_blank')
    if (sourceWindow) sourceWindow.opener = null
    const result = await getQuestionSources(card.questionId)
    if (!result.ok) {
      sourceWindow?.close()
      setQuestionInteractionMessage('来源回看失败：' + result.error.message)
      return
    }

    const isAnswer = (regionType: string) => regionType.toLowerCase().includes('answer')
    const source = result.data.sourceRegions.find((region) =>
      sourceKind === 'answer' ? isAnswer(region.regionType) : !isAnswer(region.regionType),
    )
    const sourceUrl = source?.pageScreenshotUrl ?? source?.screenshotUrl
    if (!sourceUrl) {
      sourceWindow?.close()
      setQuestionInteractionMessage(sourceKind === 'answer' ? '答案原页暂不可用。' : '试卷原页暂不可用。')
      return
    }

    if (sourceWindow) sourceWindow.location.replace(resolveSourcePreviewUrl(sourceUrl, window.location.origin))
    setQuestionInteractionMessage(sourceKind === 'answer' ? '已打开答案原页。' : '已打开试卷原页。')
  }

  const selectQuestionEvidenceCard = (
    card: QuestionEvidenceCardContract,
    addToPaperDraft: (card: QuestionEvidenceCardContract) => void,
  ) => {
    if (questionEvidenceMode !== 'active' || !card.productionEligible) {
      setQuestionInteractionMessage('预览题目不能加入正式题篮。')
      return
    }

    setSelectedEvidenceQuestionId(card.questionId)
    addToPaperDraft(card)
    setQuestionInteractionMessage('已加入题篮：第 ' + (card.questionNo ?? '-') + ' 题')
    appendLog('已从证据题库加入正式题目')
  }

  const returnToQuestionBasket = (hasSavedPaperBasket: boolean) => {
    document.querySelector('[data-contract="question-basket"]')?.scrollIntoView({
      behavior: 'smooth',
      block: 'center',
    })
    setQuestionInteractionMessage(hasSavedPaperBasket ? '已返回已保存题篮。' : '题篮尚未保存。')
  }

  return {
    activeEvidenceFilter,
    applyEvidenceFilter,
    changeQuestionEvidenceMode,
    clearEvidenceFilters,
    openQuestionEvidenceSource,
    questionEvidenceMode,
    questionEvidenceSearch,
    questionEvidenceSearchQuery,
    questionInteractionMessage,
    returnToQuestionBasket,
    selectQuestionEvidenceCard,
    selectedEvidenceQuestionId,
    setQuestionInteractionMessage,
    setSelectedEvidenceQuestionId,
  }
}
