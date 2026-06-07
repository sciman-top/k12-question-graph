import type { ReactNode } from 'react'
import katex from 'katex'
import {
  BarChartOutlined,
  CloudUploadOutlined,
  FileSearchOutlined,
  FileTextOutlined,
} from '@ant-design/icons'
import type { QuestionSourceRegionContract } from '../api/contracts'
import {
  teacherDifficultyRangeLabelFor,
  teacherLabelFor,
} from './teacherLabels'

export type TeacherView = 'import' | 'paper' | 'scores' | 'analysis'

export type RealExamRevisionState = {
  textPreview: string
  answer: string
  primaryKnowledgeLabel: string
  knowledgeTagsText: string
}

export type RealExamPreviewRow = {
  questionNo: number
  textPreview: string
  answer: string
  primaryKnowledgeLabel: string
  knowledgeTags: string[]
  sourceLabel: string
}

export const inlineMathPattern = /(\\\[[\s\S]+?\\\]|\\\([\s\S]+?\\\)|\$\$[\s\S]+?\$\$|\$[^$\n]+?\$)/g

export function renderMathAwareText(value: string): ReactNode[] {
  const nodes: ReactNode[] = []
  let lastIndex = 0

  for (const match of value.matchAll(inlineMathPattern)) {
    const raw = match[0]
    const index = match.index ?? 0
    if (index > lastIndex) {
      nodes.push(value.slice(lastIndex, index))
    }

    const displayMode = raw.startsWith('$$') || raw.startsWith('\\[')
    const latex = raw.startsWith('$$')
      ? raw.slice(2, -2)
      : raw.startsWith('$')
        ? raw.slice(1, -1)
        : raw.slice(2, -2)
    nodes.push(
      <span
        key={`math-${index}`}
        className={displayMode ? 'math-block' : 'math-inline'}
        dangerouslySetInnerHTML={{
          __html: katex.renderToString(latex, {
            throwOnError: false,
            displayMode,
            strict: false,
          }),
        }}
      />,
    )
    lastIndex = index + raw.length
  }

  if (lastIndex < value.length) {
    nodes.push(value.slice(lastIndex))
  }

  return nodes
}

export function splitQuestionText(value: string): string[] {
  return value
    .replace(/\s+([A-D])[.．、]/g, '\n$1.')
    .replace(/\s+(图\s*\d+)/g, '\n$1')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
}

export function formatRegionKind(regionType: string) {
  if (regionType.includes('answer')) {
    return '答案来源'
  }
  if (regionType.includes('asset') || regionType.includes('visual')) {
    return '题图来源'
  }
  return '题干来源'
}

export function sourceRegionRank(regionType: string) {
  if (regionType.includes('question')) {
    return 0
  }
  if (regionType.includes('asset') || regionType.includes('visual')) {
    return 1
  }
  if (regionType.includes('answer')) {
    return 2
  }
  return 3
}

export function hasRenderableImage(region: {
  screenshotRelativePath: string | null
  screenshotUrl: string | null
}) {
  return Boolean(
    region.screenshotUrl &&
      region.screenshotRelativePath &&
      /\.(png|jpe?g|webp|gif|svg)$/i.test(region.screenshotRelativePath),
  )
}

export function isQuestionAssetRegion(region: QuestionSourceRegionContract) {
  return hasRenderableImage(region) && region.regionType.includes('asset')
}

export const teacherActions = [
  {
    title: '导入试卷',
    description: '上传文件，只处理异常项',
    icon: <CloudUploadOutlined />,
    view: 'import' as TeacherView,
    status: '常用',
  },
  {
    title: '找题组卷',
    description: '找题、换题、导出样卷',
    icon: <FileSearchOutlined />,
    view: 'paper' as TeacherView,
    status: '10 分钟目标',
  },
  {
    title: '导入成绩',
    description: '上传 Excel，复用字段映射',
    icon: <FileTextOutlined />,
    view: 'scores' as TeacherView,
    status: '模板复用',
  },
  {
    title: '查看分析',
    description: '查看薄弱点和讲评摘要',
    icon: <BarChartOutlined />,
    view: 'analysis' as TeacherView,
    status: '讲评',
  },
]

export type TeacherAction = (typeof teacherActions)[number]

export const jobStates = [
  { state: 'queued', label: '排队中', value: 0 },
  { state: 'running', label: '处理中', value: 0 },
  { state: 'failed', label: '失败', value: 0 },
  { state: 'retry_waiting', label: '等待重试', value: 0 },
]

export const initialSegments = [
  {
    id: 'q-01',
    title: '第 1 题',
    page: '第 1 页',
    region: 'x10 y12 w62 h18',
    asset: '',
    confidence: 0.9,
    failureReason: '',
    takeoverAction: 'skip',
    status: 'pending_review',
  },
  {
    id: 'q-02',
    title: '第 2 题上半部分',
    page: '第 1-2 页',
    region: 'x8 y76 w70 h20',
    asset: '',
    confidence: 0.78,
    failureReason: 'cross_page_split_required',
    takeoverAction: 'split',
    status: 'pending_review',
  },
  {
    id: 'q-03',
    title: '第 2 题下半部分',
    page: '第 2 页',
    region: 'x8 y6 w70 h24',
    asset: '',
    confidence: 0.82,
    failureReason: 'cross_page_merge_required',
    takeoverAction: 'merge',
    status: 'pending_review',
  },
]

export type ReviewSegment = (typeof initialSegments)[number]

export const sharedAssets = ['图 A：滑轮组示意图', '图 B：电路图', '表 1：实验数据']
export const defaultDifficultyFilterLabel =
  teacherDifficultyRangeLabelFor('0.4-0.7')

export const starterDemoSteps = [
  {
    title: '导入样卷',
    detail: '使用示例试卷，不需要先准备真实资料',
    view: 'import' as TeacherView,
    contract: 'starter-step-1',
  },
  {
    title: '生成样卷',
    detail: '默认初中物理、力学基础、30 分',
    view: 'paper' as TeacherView,
    contract: 'starter-step-2',
  },
  {
    title: '导入样例成绩',
    detail: '字段映射自动匹配，异常行集中处理',
    view: 'scores' as TeacherView,
    contract: 'starter-step-3',
  },
  {
    title: '查看讲评摘要',
    detail: '直接看到薄弱知识点和导出入口',
    view: 'analysis' as TeacherView,
    contract: 'starter-step-4',
  },
]

export type StarterDemoStep = (typeof starterDemoSteps)[number]

export const importWizardSteps = [
  ['上传文件', 'Word、PDF、图片'],
  ['查看状态', '排队、处理中、失败、等待重试'],
  ['确认异常', '只处理跨页、误切、共用题图'],
  ['回看来源', '页码、区域和原文件可追溯'],
]

export const scoreWorkbenchSteps = [
  ['选择成绩表', '支持总分和小题分'],
  ['确认字段', '系统记住本次映射'],
  ['处理异常行', '只集中处理缺失和超分记录'],
  ['生成分析', '导入后直接进入讲评摘要'],
]

export const paperWorkbenchSteps = [
  ['找题', '按知识点、题型、难度筛选'],
  ['题篮', '已选 2 题，8 分'],
  ['细目表', '单选 1 题，填空 1 题'],
  ['换题', '保持知识点、题型、分值一致'],
  ['导出', 'Word/PDF 草稿可打印'],
]

export const scoreFieldMappings = [
  ['student_key', '学生编号'],
  ['total_score', '总分'],
  ['q1_score', '第 1 题'],
  ['q2_score', '第 2 题'],
]

export const scoreAnalysisHighlights = [
  ['87.5%', '班级得分率'],
  ['运动快慢与速度', '薄弱点 1 个'],
  ['区分度可用', '讲评参考报告'],
]

export const initialItemScoreMappingPreview = {
  teacherMessage: '输入成绩批次后，可集中预览小题到题目和知识点的映射。',
  itemCount: 2,
  mappedCount: 1,
  unclearCount: 1,
  rows: [
    {
      questionNo: 'Q1',
      scoreRecordCount: 2,
      averageScoreRate: 0.8,
      questionPreview: '关于惯性的选择题',
      primaryKnowledge: {
        title: '牛顿第一定律与惯性',
        status: 'active',
        version: 1,
      },
      status: 'mapped',
      issueCodes: [] as string[],
    },
    {
      questionNo: 'Q2',
      scoreRecordCount: 2,
      averageScoreRate: 0.77,
      questionPreview: null as string | null,
      primaryKnowledge: null as null | {
        title: string
        status: string
        version: number
      },
      status: 'needs_review',
      issueCodes: ['question_mapping_missing'],
    },
  ],
}

export const initialCommentaryReportPreview = {
  teacherMessage: '小题映射确认后，可导出讲评报告草稿。',
  status: 'draft',
  artifactPath: '',
  manifestSha256: '',
  sections: [
    { sectionId: 'class_summary', title: '班级概览', summary: '等待生成' },
    { sectionId: 'weak_points', title: '优先讲评', summary: '等待生成' },
    { sectionId: 'practice_plan', title: '巩固练习', summary: '等待生成' },
  ],
}

export const scoreWorkbenchActions = [
  {
    action: 'upload-score-sheet',
    label: '上传 Excel',
    icon: <FileTextOutlined />,
    kind: 'primary',
  },
  {
    action: 'generate-score-analysis',
    label: '生成分析',
    icon: <BarChartOutlined />,
  },
  {
    action: 'export-score-report',
    label: '导出报告',
    icon: <FileTextOutlined />,
  },
]

export const teacherAnalysisHighlights = [
  ['班级得分率', '87.5%', '示例基线'],
  ['优先讲评', '运动快慢与速度', '薄弱点 1 个'],
  ['下一步', '加入巩固题', '按当前知识版本选题'],
]

export const analysisActions = [
  {
    action: 'open-analysis-summary',
    label: '查看摘要',
    icon: <BarChartOutlined />,
  },
]

export const paperWorkbenchSummaryCards = [
  ['question-basket', '题篮', '2 题 · 8 分', '从检索结果直接加入'],
  ['blueprint-table-entry', '细目表', '力学基础', '难度中等到略高'],
  ['replacement-entry', '换题入口', '保持约束', '可撤销草稿'],
  ['export-entry', '导出入口', 'Word / PDF', '先验证工件'],
]

export const replacementAuditTags = [
  '同知识点',
  '同题型',
  '难度相近',
  '分值一致',
  '避开近期练过',
  '示例约束',
]

export const questionSearchFilterChips = [
  { filter: 'knowledge', label: '惯性' },
  { filter: 'question-type', label: '单选题' },
  { filter: 'difficulty', label: defaultDifficultyFilterLabel },
  { filter: 'source', label: '示例来源' },
]

export const guangzhou2015EvidencePreview: RealExamPreviewRow[] = [
  {
    questionNo: 1,
    textPreview:
      '1. 咸鱼放在冰箱冷冻室里一晚，冷冻室内有咸鱼味。这表明 A. 分子间存在引力 B. 分子不停地运动 C. 分子间存在斥力 D. 温度越低，分子运动越慢',
    answer: 'B',
    primaryKnowledgeLabel: '分子热运动',
    knowledgeTags: ['分子运动', '扩散现象'],
    sourceLabel: '2015广州中考.pdf / 2015广州中考答案.pdf',
  },
  {
    questionNo: 2,
    textPreview:
      '2. 图 1 所示电路，L1 的电阻比 L2 的大。开关闭合，灯均发光，则 A. V 示数等于 V1 示数 B. V1 示数大于 V2 示数 C. A 示数大于 A1 示数 D. A2 示数大于 A1 示数',
    answer: 'A',
    primaryKnowledgeLabel: '串并联电路电压电流',
    knowledgeTags: ['电路识图', '电压表', '电流表'],
    sourceLabel: 'REAL001 入库证据',
  },
  {
    questionNo: 3,
    textPreview:
      '3. 把餐巾纸摩擦过的塑料吸管放在支架上，吸管能在水平面自由转动。手持带负电的橡胶棒靠近吸管 A 端，A 端会远离橡胶棒。',
    answer: 'C',
    primaryKnowledgeLabel: '摩擦起电与电荷相互作用',
    knowledgeTags: ['静电', '电子转移'],
    sourceLabel: 'REAL001 入库证据',
  },
  {
    questionNo: 4,
    textPreview:
      '4. 图 3 是电磁波家族，真空中各种电磁波的传播速度相同。某类恒星温度较低呈暗红色；另一类恒星温度极高呈蓝色。',
    answer: 'B',
    primaryKnowledgeLabel: '电磁波谱',
    knowledgeTags: ['电磁波', '频率', '波长'],
    sourceLabel: 'REAL001 入库证据',
  },
  {
    questionNo: 5,
    textPreview:
      '5. 相同的水下录音装置 A、B 录下同一段鲸声。A 录到高、低音，B 录到只有低音。可推测海洋中能传播较远距离的声音是？',
    answer: 'A',
    primaryKnowledgeLabel: '声音传播与频率',
    knowledgeTags: ['音调', '频率', '海洋声传播'],
    sourceLabel: 'REAL001 入库证据',
  },
  {
    questionNo: 6,
    textPreview:
      '6. 在配有活塞的厚玻璃筒内放一小团硝化棉，迅速下压活塞，硝化棉燃烧。下列说法正确的是？',
    answer: 'D',
    primaryKnowledgeLabel: '做功改变内能',
    knowledgeTags: ['内能', '压缩空气', '温度升高'],
    sourceLabel: 'REAL001 入库证据',
  },
  {
    questionNo: 13,
    textPreview:
      '13. 如图 13 所示，墙壁上的平面镜前立有一硬杆。画出杆顶 A 点在平面镜中的像；若杆在 2s 内右移 1m，求速度并判断像的移动方向和大小变化。',
    answer: '（1）A 点像；（2）0.5；向左移；不变',
    primaryKnowledgeLabel: '平面镜成像',
    knowledgeTags: ['作图', '像的运动', '速度'],
    sourceLabel: 'REAL001 入库证据',
  },
  {
    questionNo: 18,
    textPreview:
      '18. 图 19 中质量为 10kg 的物体 A 静止在水平地面，与地面接触面积为 0.2m2。求 A 所受重力和 A 对地面的压强。',
    answer: '100；500',
    primaryKnowledgeLabel: '重力与固体压强',
    knowledgeTags: ['重力计算', '压强公式'],
    sourceLabel: 'REAL001 入库证据',
  },
]

export const labelFor = teacherLabelFor

export const reviewRiskColorFor = (riskLevel: string) => {
  if (riskLevel === 'high') {
    return 'red'
  }
  if (riskLevel === 'medium') {
    return 'orange'
  }
  return 'green'
}

export const initialPaperRequest =
  '八年级物理，牛顿第一定律与惯性，单选 5 题、计算 2 题、实验 1 题，总分 30 分，难度中等'

export const initialPaperUnderstanding = {
  mode: 'draft_test',
  productionEligible: false,
  allowRealModelCalls: false,
  systemUnderstanding:
    '按初中物理要求生成组卷理解：八年级物理，牛顿第一定律与惯性，单选 5 题、计算 2 题、实验 1 题，总分 30 分，难度中等',
  paperType: 'unit_practice',
  subject: 'physics',
  grade: 'grade_8',
  totalScore: 30,
  difficultyTarget: 'medium',
  scope: ['牛顿第一定律与惯性'],
  blueprint: [
    {
      questionType: 'single_choice',
      count: 5,
      score: 15,
      assetStatus: 'draft_dynamic_asset',
      reviewStatus: 'pending_review',
    },
    {
      questionType: 'calculation',
      count: 2,
      score: 10,
      assetStatus: 'draft_dynamic_asset',
      reviewStatus: 'pending_review',
    },
    {
      questionType: 'experiment',
      count: 1,
      score: 5,
      assetStatus: 'draft_dynamic_asset',
      reviewStatus: 'pending_review',
    },
  ],
  reviewQuestions: [
    '是否需要限定教材版本或章节范围？',
    '是否需要排除最近已练过的题目？',
    '是否确认使用草稿测试细目表继续生成试卷草稿？',
  ],
}

export const initialPaperDraft = {
  mode: 'draft_test',
  productionEligible: false,
  allowRealModelCalls: false,
  currentQuestion: {
    id: 'paper-q-01',
    stemPreview: '关于惯性的说法，下列哪项正确？',
    questionType: 'single_choice',
    score: 3,
    difficultyEstimated: 0.62,
    primaryKnowledgeId: 'PHY-JH-MECH-FORCE-NEWTON1',
    primaryKnowledgeTitle: '牛顿第一定律与惯性',
    sourceType: 'synthetic',
    recentUseStatus: 'not_recently_used',
  },
  replacementQuestion: null as null | {
    id: string
    stemPreview: string
    questionType: string
    score: number
    difficultyEstimated: number
    primaryKnowledgeId: string
    primaryKnowledgeTitle: string
    sourceType: string
    recentUseStatus: string
  },
  undoSnapshot: null as null | {
    undoToken: string
    revertAction: string
  },
  auditTrail: [] as string[],
}
