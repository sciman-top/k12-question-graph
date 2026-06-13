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
    id: 'cloud_enhanced',
    label: '云 API 增强',
    summary: '管理员单独启用云 provider profile，预算、fallback 和 cache 仍走受控门禁。',
    providerProfile: 'cloud_openai_candidate',
    icon: <CloudServerOutlined />,
  },
  {
    id: 'local_enhanced',
    label: '本地增强',
    summary: '只作为本地量化模型评测入口，不默认下载权重，也不直接切生产默认。',
    providerProfile: 'local_llm_eval_gateway',
    icon: <ThunderboltOutlined />,
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
    label: '云 API 候选',
    providerType: 'openai_compatible',
    credentialRef: 'dialog_secret_local_machine',
    baseUrl: 'https://api.openai.com/v1',
    concurrency: '2',
    budget: '300 元 / 月',
    fallback: 'stub_offline_default_then_pending_review',
    status: '默认关闭',
    disabledByDefault: true,
  },
  {
    id: 'local_llm_eval_gateway',
    label: '本地模型评测网关',
    providerType: 'custom_http',
    credentialRef: 'env:KQG_AI_LOCAL_GATEWAY_TOKEN',
    baseUrl: 'http://127.0.0.1:11434/v1',
    concurrency: '1',
    budget: '0 元 / 月',
    fallback: 'stub_offline_default_then_pending_review',
    status: '默认关闭',
    disabledByDefault: true,
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
    providerProfile: 'local_llm_eval_gateway',
    fallback: 'bulk_prefilter_model',
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
    form.setFieldValue('apiKey', '')
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
    })
    setTestBusy(false)

    if (!result.ok) {
      message.error(`试跑失败：${result.error.message}`)
      return
    }

    setTestSummaryOverride(result.data.message)
    setTestOutput(result.data.outputJson)
    if (result.data.passed) {
      message.success('结构化 smoke 试跑已完成')
    } else {
      message.warning('结构化 smoke 试跑未通过，请查看阻断项')
    }
  }

  const testSummary = testSummaryOverride || settings?.teacherMessage || '尚未执行真实结构化 smoke 试跑'

  const providerSettingsCard = settings ?? {
    providerProfileId: 'cloud_openai_candidate',
    providerType: 'openai_compatible',
    baseUrl: 'https://api.openai.com/v1',
    credentialMode: 'dialog_secret_local_machine',
    maskedSecret: '',
    secretConfigured: false,
    maxConcurrency: 2,
    monthlyBudgetCny: 300,
    disabledByDefault: true,
    allowRealModelCalls: false,
    defaultSmokeTaskType: 'knowledge_tagging',
    defaultSmokeModel: 'gpt-5.4-mini',
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
            普通教师只看离线优先、云 API 增强、本地增强等简化模式；provider profile、预算、fallback 和 secret 引用仅管理员可见。
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
            <small>这里是真正录入 API 参数、保存本机密钥、并做结构化试跑的入口。</small>
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
          <span><Typography.Text type="secondary">并发</Typography.Text><strong>{providerSettingsCard.maxConcurrency}</strong></span>
          <span><Typography.Text type="secondary">预算</Typography.Text><strong>{providerSettingsCard.monthlyBudgetCny} 元 / 月</strong></span>
          <span><Typography.Text type="secondary">默认试跑</Typography.Text><code>{providerSettingsCard.defaultSmokeTaskType} / {providerSettingsCard.defaultSmokeModel}</code></span>
        </div>
        <Alert
          showIcon
          type={providerSettingsCard.secretConfigured ? 'info' : 'warning'}
          title={providerSettingsCard.secretConfigured ? '本机密钥已配置' : '尚未配置本机密钥'}
          description={testSummary}
          data-contract="ai-provider-structured-smoke-test"
        />
        {testOutput ? (
          <pre className="ai-smoke-output">{testOutput}</pre>
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
        title="密钥只保留引用，不保留明文"
        description="provider profile 只记录 env 引用、base URL、并发、预算和 fallback；任何真实 secret、token 或生产默认切换都必须走脱敏检查和人工确认。"
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
          <Form.Item label="provider profile" name="providerProfileId" rules={[{ required: true }]}>
            <Input />
          </Form.Item>
          <Form.Item label="base URL" name="baseUrl" rules={[{ required: true }]}>
            <Input />
          </Form.Item>
          <Form.Item
            label="API Key"
            name="apiKey"
            extra={`当前仅显示掩码：${providerSettingsCard.maskedSecret || '未配置'}；留空则保留现有本机密钥。`}
            data-contract="ai-provider-secret-masked-input"
          >
            <Input.Password placeholder="sk-..." />
          </Form.Item>
          <Form.Item label="最大并发" name="maxConcurrency" rules={[{ required: true }]}>
            <InputNumber min={1} max={8} style={{ width: '100%' }} />
          </Form.Item>
          <Form.Item label="月预算（元）" name="monthlyBudgetCny" rules={[{ required: true }]}>
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
          <Form.Item label="默认试跑模型" name="defaultSmokeModel" rules={[{ required: true }]}>
            <Input />
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
              测试连接并结构化试跑
            </Button>
          </Space>
        </Form>
      </Modal>
    </section>
  )
}
