import { type FormEvent, type ReactNode, useEffect, useState } from 'react'
import { Alert, Button, Card, Input, Space, Spin, Typography } from 'antd'
import {
  createAdminSession,
  deleteAdminSession,
  getAdminSession,
  type AdminSessionContract,
} from '../api/client'

type AdminSessionGateProps = {
  children: ReactNode
}

export function AdminSessionGate({ children }: AdminSessionGateProps) {
  const [session, setSession] = useState<AdminSessionContract | null>(null)
  const [apiKey, setApiKey] = useState('')
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    void getAdminSession().then((result) => {
      if (!active) return
      if (result.ok) {
        setSession(result.data)
      } else {
        setError(`无法检查登录状态（${result.error.status ?? result.error.code}）`)
      }
      setLoading(false)
    })
    return () => {
      active = false
    }
  }, [])

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!apiKey.trim()) {
      setError('请输入管理员访问密钥')
      return
    }

    setSubmitting(true)
    setError('')
    const result = await createAdminSession(apiKey.trim())
    setSubmitting(false)
    if (!result.ok) {
      setError(result.error.status === 426
        ? '远程登录必须使用 HTTPS，请通过已配置 TLS 的校内入口访问。'
        : '访问密钥无效或服务端尚未配置认证。')
      return
    }

    setApiKey('')
    setSession(result.data)
  }

  async function signOut() {
    setSubmitting(true)
    await deleteAdminSession()
    globalThis.location.reload()
  }

  if (loading) {
    return <div className="auth-gate-loading"><Spin size="large" tip="正在检查安全会话" /></div>
  }

  if (!session?.authenticated) {
    return (
      <main className="auth-gate-shell">
        <Card className="auth-gate-card">
          <Space direction="vertical" size="large" style={{ width: '100%' }}>
            <div>
              <Typography.Title level={2}>校本题谱安全登录</Typography.Title>
              <Typography.Paragraph type="secondary">
                访问密钥只用于建立服务端 HttpOnly 会话，不会写入浏览器存储或前端构建产物。
              </Typography.Paragraph>
            </div>
            {error ? <Alert type="error" showIcon message={error} /> : null}
            <form onSubmit={submit}>
              <Space direction="vertical" size="middle" style={{ width: '100%' }}>
                <Input.Password
                  autoFocus
                  autoComplete="current-password"
                  value={apiKey}
                  onChange={(event) => setApiKey(event.target.value)}
                  placeholder="管理员访问密钥"
                  size="large"
                />
                <Button type="primary" htmlType="submit" loading={submitting} block size="large">
                  建立安全会话
                </Button>
              </Space>
            </form>
          </Space>
        </Card>
      </main>
    )
  }

  return (
    <>
      <div className="auth-session-strip">
        <span>已认证：{session.operatorId ?? 'local-operator'}（{session.role ?? 'admin'}）</span>
        <Button type="link" size="small" loading={submitting} onClick={signOut}>退出</Button>
      </div>
      {children}
    </>
  )
}
