import { createContext } from 'react'
import type { AdminSessionContract } from '../api/client'

// 已认证会话下发给子树;未登录/加载中不渲染 children,消费方拿到的 null
// 即"无会话"语义(如 App 据此停轮询受保护的 /health/ready)。
export const AdminSessionContext = createContext<AdminSessionContract | null>(null)
