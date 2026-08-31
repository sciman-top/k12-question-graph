import {
  ApiOutlined,
  BranchesOutlined,
  CloudServerOutlined,
  EyeInvisibleOutlined,
  LockOutlined,
  SettingOutlined,
  ThunderboltOutlined,
} from '@ant-design/icons'
import { Alert, Button, Form, Input, InputNumber, Modal, Space, Switch, Tag, Typography, message } from 'antd'
import { useEffect, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import type { AdminAiProviderSettingsTestContract } from '../api/contracts'
import {
  saveAdminAiProviderSettings,
  testAdminAiProviderSettings,
} from '../api/client'
import { serverStateQueryKeys, useAdminAiProviderSettingsQuery } from '../api/queries'

const teacherSimpleModes = [
  {
    id: 'offline_first',
    label: '离线优先',
    summary: '默认只走规则、本地解析和 stub_llm 候选；教师只看到推荐模式和连接状态。',
    providerProfile: 'stub_offline_default',
    icon: <LockOutlined />,
  },
  {
    id: 'cockpit_enhanced',
    label: 'Cockpit 本地 API 增强',
    summary: '管理员单独启用 Cockpit 本地 API 网关，模型可用性按 Sol、Terra、Luna 受控切换。',
    providerProfile: 'cloud_openai_candidate',
    icon: <CloudServerOutlined />,
  },
]

const providerProfiles = [
  {
    id: 'stub_offline_default',
    label: '离线默认 / stub',
    providerType: 'stub_llm',
    credentialRef: 'not_required:stub_llm',
    baseUrl: 'internal://stub_llm',
    concurrency: '1',
    budget: '0 元 / 月',
    fallback: 'pending_review_manual_takeover',
    status: '默认启用',
    disabledByDefault: false,
  },
  {
    id: 'cloud_openai_candidate',
    label: 'Cockpit 本地 API 网关',
    providerType: 'openai_compatible',
    credentialRef: 'dialog_secret_local_machine',
    baseUrl: 'http://127.0.0.1:45335/v1',
    concurrency: '2',
    budget: '0 元 / 月',
    fallback: 'Sol -> Terra -> Luna -> pending_review',
    status: '默认关闭',
    disabledByDefault: true,
  },
]

const modelPresets = [
  {
    id: 'sol',
    model: 'Sol-only · gpt-5.6-sol',
    reasoningEfforts: 'quality=sol·high / balanced=sol·medium / economy=sol·low',
    fallback: '首选；故障后 Terra -> Luna',
  },
  {
    id: 'terra',
    model: 'Terra-only · gpt-5.6-terra',
    reasoningEfforts: 'quality=terra·max / balanced=terra·xhigh / economy=terra·high',
    fallback: '次选；故障后 Sol -> Luna',
  },
  {
    id: 'luna',
    model: 'Luna-only · gpt-5.6-luna',
    reasoningEfforts: 'quality=luna·max / balanced=luna·xhigh / economy=luna·high',
    fallback: '末选；故障后 Sol -> Terra',
  },
]

const executionSlots = [
  {
    id: 'mechanical_cleanup',
    purpose: '文件格式、去重和确定性转换；默认不调用外部模型。',
    grades: '默认档位：economy；模型由当前完整 preset 统一决定。',
  },
  {
    id: 'bulk_prefilter',
    purpose: '批量结构化、候选预筛和低风险异常分类。',
    grades: '默认档位：balanced；模型由当前完整 preset 统一决定。',
  },
  {
    id: 'engineering_review',
    purpose: '来源锚点、结构化候选、一般语义和工程变更复核。',
    grades: '默认档位：balanced；模型由当前完整 preset 统一决定。',
  },
  {
    id: 'visual_review',
    purpose: '跨页、图表、公式、共享题图和导出视觉复核。',
    grades: '默认档位：quality；模型由当前完整 preset 统一决定。',
  },
  {
    id: 'high_risk_adjudication',
    purpose: '正式激活、冲突裁决、长期口径和难回滚事项。',
    grades: '默认档位：quality；模型由当前完整 preset 统一决定。',
  },
]

const roleRoutingPolicies = [
  {
    role: 'bulk_prefilter_model',
    purpose: '低成本候选预筛 / 批量异常分类',
    providerProfile: 'cloud_openai_candidate',
    fallback: 'engineering_review_model',
  },
  {
    role: 'mechanical_cleanup_model',
    purpose: '机械清洗 / 格式整理 / 非语义任务',
    providerProfile: 'local_deterministic',
    fallback: '异常才转入 bulk_prefilter',
  },
  {
    role: 'engineering_review_model',
    purpose: '结构化候选提炼 / 来源锚点审查',
    providerProfile: 'cloud_openai_candidate',
    fallback: 'high_risk_review_model',
  },
  {
    role: 'high_risk_review_model',
    purpose: '高风险映射 / 激活前复核',
    providerProfile: 'cloud_openai_candidate',
    fallback: 'highest_risk_decision_model',
  },
  {
    role: 'highest_risk_decision_model',
    purpose: '长期口径争议 / 难回滚裁决',
    providerProfile: 'cloud_openai_candidate',
    fallback: 'manual_architecture_review',
  },
]

const smokeTaskOptions = [
  { value: 'knowledge_tagging', label: 'knowledge_tagging' },
  { value: 'question_extraction', label: 'question_extraction' },
  { value: 'natural_language_paper_request', label: 'natural_language_paper_request' },
  { value: 'question_solving', label: 'question_solving' },
  { value: 'answer_verification', label: 'answer_verification' },
]

const adminAiActions = [
  { label: '查看 provider 目录', action: 'open-provider-profile-catalog', icon: <ApiOutlined /> },
  { label: '查看角色路由证据', action: 'open-role-routing-evidence', icon: <BranchesOutlined /> },
  { label: '查看预算与缓存门禁', action: 'open-budget-cache-guard', icon: <CloudServerOutlined /> },
  { label: '查看密钥脱敏检查', action: 'open-secret-redaction-check', icon: <EyeInvisibleOutlined /> },
]

const aiGuardrails = [
  '所有输出默认 candidate / draft / pending_review，不直接进入正式 active。',
  'provider profile 切换、base URL 改动、云 token 启用和本地模型默认切换都必须人工确认。',
  '预算超限、schema 缺失、secret 风险或 no-active-write 失败时统一 fail-closed。',
]

type SettingsFormValues = {
  providerProfileId: string
  baseUrl: string
  apiKey: string
  imageBaseUrl: string
  imageApiKey: string
  maxConcurrency: number
  monthlyBudgetCny: number
  disabledByDefault: boolean
  allowRealModelCalls: boolean
  defaultSmokeTaskType: string
  defaultSmokeModel: string
  operatorNote: string
}

export function AiRoutingControlPanel() {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [saveBusy, setSaveBusy] = useState(false)
  const [testBusy, setTestBusy] = useState(false)
  const [testOutput, setTestOutput] = useState('')
  const [testSummaryOverride, setTestSummaryOverride] = useState('')
  const [lastTestResult, setLastTestResult] = useState<AdminAiProviderSettingsTestContract | null>(null)
  const [form] = Form.useForm<SettingsFormValues>()
  const queryClient = useQueryClient()
  const settingsQuery = useAdminAiProviderSettingsQuery()
  const settings = settingsQuery.data?.ok ? settingsQuery.data.data : undefined

  useEffect(() => {
    if (!settings) {
      return
    }

    form.setFieldsValue({
      providerProfileId: settings.providerProfileId,
      baseUrl: settings.baseUrl,
      apiKey: '',
      imageBaseUrl: settings.imageBaseUrl,
      imageApiKey: '',
      maxConcurrency: settings.maxConcurrency,
      monthlyBudgetCny: settings.monthlyBudgetCny,
      disabledByDefault: settings.disabledByDefault,
      allowRealModelCalls: settings.allowRealModelCalls,
      defaultSmokeTaskType: settings.defaultSmokeTaskType,
      defaultSmokeModel: settings.defaultSmokeModel,
      operatorNote: '',
    })
  }, [form, settings])

  const handleSave = async () => {
    const values = await form.validateFields()
    setSaveBusy(true)
    const result = await saveAdminAiProviderSettings({
      providerProfileId: values.providerProfileId,
      baseUrl: values.baseUrl,
      apiKey: values.apiKey,
      imageBaseUrl: values.imageBaseUrl,
      imageApiKey: values.imageApiKey,
      maxConcurrency: values.maxConcurrency,
      monthlyBudgetCny: values.monthlyBudgetCny,
      disabledByDefault: values.disabledByDefault,
      allowRealModelCalls: values.allowRealModelCalls,
      defaultSmokeTaskType: values.defaultSmokeTaskType,
      defaultSmokeModel: values.defaultSmokeModel,
      operatorNote: values.operatorNote,
    })
    setSaveBusy(false)

    if (!result.ok) {
      message.error(`保存失败：${result.error.message}`)
      return
    }

    message.success('管理员 AI 设置已保存')
    setTestSummaryOverride(result.data.teacherMessage)
    setLastTestResult(null)
    setTestOutput('')
    form.setFieldValue('apiKey', '')
    form.setFieldValue('imageApiKey', '')
    await queryClient.invalidateQueries({ queryKey: serverStateQueryKeys.adminAiProviderSettings })
  }

  const handleTest = async () => {
    const values = await form.validateFields()
    setTestBusy(true)
    const result = await testAdminAiProviderSettings({
      taskType: values.defaultSmokeTaskType,
      model: values.defaultSmokeModel,
      inputJson: '',
      baseUrlOverride: values.baseUrl,
      imageBaseUrlOverride: values.imageBaseUrl,
      routingMode: 'balanced',
      useModelRouting: true,
    })
    setTestBusy(false)

    if (!result.ok) {
      message.error(`试跑失败：${result.error.message}`)
      return
    }

    setLastTestResult(result.data)
    setTestSummaryOverride(result.data.message)
    setTestOutput(result.data.outputJson)
    if (result.data.combinedPassed) {
      message.success('主 smoke 与图片链路探针均已通过')
    } else if (result.data.passed || result.data.imageProbe.passed) {
      message.warning('双探针仅部分通过，请查看主 smoke 与图片链路结果')
    } else {
      message.warning('主 smoke 与图片链路探针均未通过，请查看阻断项')
    }
  }

  const testSummary =
    lastTestResult?.message ||
    testSummaryOverride ||
    settings?.teacherMessage ||
    '尚未执行真实结构化 smoke 试跑'
  const imageProbe = lastTestResult?.imageProbe ?? null
  const imageProbeAttemptsSummary = imageProbe?.attempts
    .map(
      (attempt) =>
        `${attempt.providerEndpointId} | ${attempt.baseUrl} | ${attempt.routeKind} | ${attempt.endpointPath} | ${attempt.model} | HTTP ${attempt.httpStatusCode} | ${attempt.latencyMs}ms | ${attempt.passed ? 'passed' : 'failed'} | ${attempt.message}`,
    )
    .join('\n')
  const structuredProbeAttemptsSummary = lastTestResult?.attempts
    .map(
      (attempt) =>
        `${attempt.providerEndpointId} | ${attempt.baseUrl} | ${attempt.routeKind} | ${attempt.endpointPath} | ${attempt.model} | ${attempt.reasoningEffort} | HTTP ${attempt.httpStatusCode} | ${attempt.latencyMs}ms | ${attempt.passed ? 'passed' : 'failed'} | ${attempt.message}`,
    )
    .join('\n')

  const providerSettingsCard = settings ?? {
    providerProfileId: 'cloud_openai_candidate',
    providerType: 'openai_compatible',
    baseUrl: 'http://127.0.0.1:45335/v1',
    imageBaseUrl: 'http://127.0.0.1:45335/v1',
    credentialMode: 'dialog_secret_local_machine',
    maskedSecret: '',
    secretConfigured: false,
    maskedImageSecret: '',
    imageSecretConfigured: false,
    imageUsesPrimarySecret: true,
    maxConcurrency: 2,
    monthlyBudgetCny: 300,
    disabledByDefault: true,
    allowRealModelCalls: false,
    defaultSmokeTaskType: 'knowledge_tagging',
    defaultSmokeModel: 'gpt-5.6-sol',
    fallbackBaseUrl: '',
    fallbackImageBaseUrl: '',
    maskedFallbackSecret: '',
    fallbackSecretConfigured: false,
    maskedFallbackImageSecret: '',
    fallbackImageSecretConfigured: false,
    fallbackImageUsesPrimarySecret: true,
    endpoints: [],
    lastUpdatedAt: '',
    status: 'unknown',
    mode: 'draft_test',
    productionEligible: false,
    teacherMessage: '尚未读取管理员设置',
    auditTrail: [],
  }

  return (
    <section
      className="ai-routing-panel"
      aria-label="AI 路由配置"
      data-flow="ns1305-role-routed-ai"
      data-contract="admin-ai-routing-config"
    >
      <div className="panel-heading">
        <div>
          <Typography.Title level={2}>AI 路由配置</Typography.Title>
          <Typography.Text type="secondary">
            普通教师只看离线优先与 Cockpit 本地 API 增强等简化模式；管理员只能使用固定本地网关，模型故障由 Sol/Terra/Luna preset 切换处理。
          </Typography.Text>
        </div>
        <Space size="small" wrap>
          <Tag color="green">NS1305</Tag>
          <Tag data-contract="no-active-write">默认 pending_review</Tag>
        </Space>
      </div>

      <div className="ai-routing-mode-grid" data-contract="teacher-simple-ai-modes">
        {teacherSimpleModes.map((mode) => (
          <div className="ai-routing-mode-card" key={mode.id} data-mode={mode.id}>
            <span className="ai-routing-icon">{mode.icon}</span>
            <span>
              <strong>{mode.label}</strong>
              <small>{mode.summary}</small>
              <code>{mode.providerProfile}</code>
            </span>
          </div>
        ))}
      </div>

      <div className="ai-provider-grid" data-contract="provider-profiles-admin-only">
        {providerProfiles.map((profile) => (
          <div className="ai-provider-card" key={profile.id} data-provider-profile={profile.id}>
            <div className="ai-provider-head">
              <span>
                <strong>{profile.label}</strong>
                <small>{profile.providerType}</small>
              </span>
              <Tag color={profile.disabledByDefault ? 'orange' : 'green'}>{profile.status}</Tag>
            </div>
            <div className="ai-provider-meta">
              <span><Typography.Text type="secondary">credentialRef</Typography.Text><code>{profile.credentialRef}</code></span>
              <span><Typography.Text type="secondary">baseUrl</Typography.Text><code>{profile.baseUrl}</code></span>
              <span><Typography.Text type="secondary">并发</Typography.Text><strong>{profile.concurrency}</strong></span>
              <span><Typography.Text type="secondary">预算</Typography.Text><strong>{profile.budget}</strong></span>
              <span><Typography.Text type="secondary">fallback</Typography.Text><code>{profile.fallback}</code></span>
            </div>
          </div>
        ))}
      </div>

      <div className="ai-role-grid" data-contract="model-presets-and-failover">
        {modelPresets.map((preset) => (
          <div className="ai-role-card" key={preset.id} data-model-preset={preset.id}>
            <span className="ai-routing-icon"><ThunderboltOutlined /></span>
            <span>
              <strong>{preset.model}</strong>
              <small>思考等级：{preset.reasoningEfforts}</small>
              <code>{preset.fallback}</code>
            </span>
          </div>
        ))}
      </div>

      <div className="ai-role-grid" data-contract="execution-slots-and-grades">
        {executionSlots.map((slot) => (
          <div className="ai-role-card" key={slot.id} data-execution-slot={slot.id}>
            <span className="ai-routing-icon"><BranchesOutlined /></span>
            <span>
              <strong>{slot.id}</strong>
              <small>{slot.purpose}</small>
              <code>{slot.grades}</code>
            </span>
          </div>
        ))}
      </div>

      <div className="ai-role-grid" data-contract="role-routed-policy">
        {roleRoutingPolicies.map((policy) => (
          <div className="ai-role-card" key={policy.role} data-route-role={policy.role}>
            <span className="ai-routing-icon"><BranchesOutlined /></span>
            <span>
              <strong>{policy.role}</strong>
              <small>{policy.purpose}</small>
              <code>{policy.providerProfile}</code>
            </span>
            <Tag>{policy.fallback}</Tag>
          </div>
        ))}
      </div>

      <div
        className="ai-provider-settings-card"
        data-contract="admin-ai-settings-dialog"
      >
        <div className="ai-provider-head">
          <span>
            <strong>管理员 AI 设置</strong>
            <small>这里保存 Cockpit 本机密钥，并通过固定本地网关做 preset 级 responses smoke 与图片链路探针。</small>
          </span>
          <Button
            icon={<SettingOutlined />}
            data-action="open-ai-provider-settings"
            onClick={() => setDialogOpen(true)}
          >
            打开设置
          </Button>
        </div>
        <div className="ai-provider-meta">
          <span><Typography.Text type="secondary">providerProfile</Typography.Text><code>{providerSettingsCard.providerProfileId}</code></span>
          <span><Typography.Text type="secondary">baseUrl</Typography.Text><code>{providerSettingsCard.baseUrl}</code></span>
          <span><Typography.Text type="secondary">secret</Typography.Text><code>{providerSettingsCard.maskedSecret || '未配置'}</code></span>
          <span><Typography.Text type="secondary">imageBaseUrl</Typography.Text><code>{providerSettingsCard.imageBaseUrl || providerSettingsCard.baseUrl}</code></span>
          <span><Typography.Text type="secondary">imageSecret</Typography.Text><code>{providerSettingsCard.maskedImageSecret || (providerSettingsCard.imageUsesPrimarySecret ? '复用主 key' : '未配置')}</code></span>
          <span><Typography.Text type="secondary">并发</Typography.Text><strong>{providerSettingsCard.maxConcurrency}</strong></span>
          <span><Typography.Text type="secondary">预算</Typography.Text><strong>{providerSettingsCard.monthlyBudgetCny} 元 / 月</strong></span>
          <span><Typography.Text type="secondary">默认试跑</Typography.Text><code>{providerSettingsCard.defaultSmokeTaskType} / {providerSettingsCard.defaultSmokeModel}</code></span>
          {lastTestResult ? (
            <span data-contract="ai-effective-route">
              <Typography.Text type="secondary">生效路由</Typography.Text>
              <code>{lastTestResult.taskType} / {lastTestResult.effectiveExecutionSlot} / {lastTestResult.effectiveExecutionGrade} / {lastTestResult.effectivePreset} / {lastTestResult.model} / {lastTestResult.effectiveReasoningEffort} / {lastTestResult.routingMode}</code>
            </span>
          ) : null}
        </div>
        {providerSettingsCard.endpoints.length > 0 ? (
          <div className="ai-provider-meta" data-contract="ai-provider-endpoint-order">
            {providerSettingsCard.endpoints.map((endpoint) => (
              <span key={endpoint.endpointId}>
                <Typography.Text type="secondary">{endpoint.label}</Typography.Text>
                <code>
                  {endpoint.endpointId} / {endpoint.baseUrl || '无文本路由'} / {endpoint.secretConfigured ? 'key 已配置' : 'key 未配置'}
                </code>
              </span>
            ))}
          </div>
        ) : null}
        <Alert
          showIcon
          type={providerSettingsCard.secretConfigured ? 'info' : 'warning'}
          title={providerSettingsCard.secretConfigured ? 'Cockpit 本地文本 key 已配置' : '尚未配置 Cockpit 本地文本 key'}
          description={testSummary}
          data-contract="ai-provider-structured-smoke-test"
        />
        {testOutput ? (
          <pre className="ai-smoke-output">{testOutput}</pre>
        ) : null}
        {structuredProbeAttemptsSummary ? (
          <pre className="ai-smoke-output">{structuredProbeAttemptsSummary}</pre>
        ) : null}
        {imageProbe ? (
          <Alert
            showIcon
            type={imageProbe.passed ? 'success' : imageProbe.attempted ? 'warning' : 'info'}
            title={
              imageProbe.passed
                ? '图片链路探针已通过'
                : imageProbe.attempted
                  ? '图片链路探针未通过'
                  : '图片链路探针未执行'
            }
            description={imageProbe.message}
            data-contract="ai-provider-image-probe-test"
          />
        ) : null}
        {imageProbeAttemptsSummary ? (
          <pre className="ai-smoke-output">{imageProbeAttemptsSummary}</pre>
        ) : null}
      </div>

      <div className="ai-routing-guardrails">
        {aiGuardrails.map((item) => (
          <div className="ai-routing-guardrail" key={item}>
            <LockOutlined />
            <span>{item}</span>
          </div>
        ))}
      </div>

      <div className="ai-routing-actions" data-contract="admin-ai-actions">
        {adminAiActions.map((action) => (
          <Button key={action.action} icon={action.icon} data-action={action.action}>
            {action.label}
          </Button>
        ))}
      </div>

      <Alert
        showIcon
        type="info"
        title="默认单 key，图片覆盖可选"
        description="管理员设置默认只要求一把主 key；图片专用 base URL / key 可留空并自动复用主配置。所有真实 secret 仍只保留本机加密副本，不在前端明文显示。"
        data-contract="ai-secret-redaction-no-active-write"
      />

      <Modal
        title="管理员 AI 设置"
        open={dialogOpen}
        onCancel={() => setDialogOpen(false)}
        footer={null}
        forceRender
        destroyOnHidden={false}
      >
        <Form form={form} layout="vertical">
          <Form.Item label="provider profile" name="providerProfileId" rules={[{ required: true }]} extra="固定为 Cockpit 本地 API 网关 profile。">
            <Input readOnly />
          </Form.Item>
          <Form.Item label="Cockpit 本地 base URL" name="baseUrl" rules={[{ required: true }]} extra="固定为 http://127.0.0.1:45335/v1；不得将本机 Cockpit key 发送到外部网关。">
            <Input readOnly />
          </Form.Item>
          <Form.Item
            label="主 API Key"
            name="apiKey"
            extra={`当前仅显示掩码：${providerSettingsCard.maskedSecret || '未配置'}；留空则保留现有本机密钥。`}
            data-contract="ai-provider-secret-masked-input"
          >
            <Input.Password placeholder="sk-..." />
          </Form.Item>
          <Form.Item
            label="图片 base URL（可选）"
            name="imageBaseUrl"
            extra="留空时默认复用主 base URL；只有中继网关把生图单独挂到另一路径时才需要单独填写。"
          >
            <Input placeholder="http://127.0.0.1:45335/v1" />
          </Form.Item>
          <Form.Item
            label="图片专用 API Key（可选）"
            name="imageApiKey"
            extra={`当前仅显示掩码：${providerSettingsCard.maskedImageSecret || (providerSettingsCard.imageUsesPrimarySecret ? '复用主 key' : '未配置')}；留空则复用主 key。`}
          >
            <Input.Password placeholder="留空则复用主 key" />
          </Form.Item>
          <Form.Item label="最大并发" name="maxConcurrency" rules={[{ required: true }]}>
            <InputNumber min={1} max={8} style={{ width: '100%' }} />
          </Form.Item>
          <Form.Item label="月预算上限（元）" name="monthlyBudgetCny" rules={[{ required: true }]} extra="当前用于运营规划；实际 CNY 扣减需以 Cockpit 账单/计价真源接入后才可强制。">
            <InputNumber min={0} max={100000} style={{ width: '100%' }} />
          </Form.Item>
          <Form.Item label="默认试跑任务" name="defaultSmokeTaskType" rules={[{ required: true }]}>
            <Input list="smoke-task-options" />
          </Form.Item>
          <datalist id="smoke-task-options">
            {smokeTaskOptions.map((option) => (
              <option value={option.value} key={option.value}>
                {option.label}
              </option>
            ))}
          </datalist>
          <Form.Item label="默认试跑 preset" name="defaultSmokeModel" rules={[{ required: true }]} extra="固定为 Sol-only 的 gpt-5.6-sol；实际故障切换由当前完整 preset 决定。">
            <Input readOnly />
          </Form.Item>
          <Form.Item label="操作说明" name="operatorNote">
            <Input.TextArea autoSize={{ minRows: 2, maxRows: 4 }} />
          </Form.Item>
          <Form.Item label="默认关闭">
            <Form.Item name="disabledByDefault" valuePropName="checked" noStyle>
              <Switch />
            </Form.Item>
          </Form.Item>
          <Form.Item label="允许 draft/test 真实试跑">
            <Form.Item name="allowRealModelCalls" valuePropName="checked" noStyle>
              <Switch />
            </Form.Item>
          </Form.Item>

          <Space wrap>
            <Button
              type="primary"
              loading={saveBusy}
              onClick={() => void handleSave()}
              data-action="save-ai-provider-settings"
            >
              保存设置
            </Button>
            <Button
              loading={testBusy}
              onClick={() => void handleTest()}
              data-action="test-ai-provider-settings"
            >
              测试主路由与图片链路
            </Button>
          </Space>
        </Form>
      </Modal>
    </section>
  )
}
