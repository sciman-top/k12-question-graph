import {
  ApiOutlined,
  BranchesOutlined,
  CloudServerOutlined,
  EyeInvisibleOutlined,
  LockOutlined,
  ThunderboltOutlined,
} from '@ant-design/icons'
import { Alert, Button, Space, Tag, Typography } from 'antd'

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
    credentialRef: 'env:KQG_AI_OPENAI_KEY',
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

export function AiRoutingControlPanel() {
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
    </section>
  )
}
