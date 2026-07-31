import { QueryClientProvider } from '@tanstack/react-query'
import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import App from './App'
import { createAppQueryClient } from './state/queryClient'

describe('App navigation smoke', () => {
  it('keeps the application rendered after each home entry is opened', () => {
    vi.stubGlobal('ResizeObserver', class {
      observe() {}
      unobserve() {}
      disconnect() {}
    })
    Object.defineProperty(Element.prototype, 'scrollIntoView', {
      configurable: true,
      value: vi.fn(),
    })

    render(
      <QueryClientProvider client={createAppQueryClient()}>
        <App />
      </QueryClientProvider>,
    )

    const appHeading = screen.getByRole('heading', { name: '校本题谱' })
    const homeEntries = within(screen.getByRole('region', { name: '普通教师入口' }))
    for (const name of ['打开导入', '导入试卷', '找题组卷', '导入成绩', '查看分析']) {
      fireEvent.click(homeEntries.getByRole('button', { name: new RegExp(name) }))
      expect(appHeading).toBeInTheDocument()
    }
  }, 15_000)

  it('keeps exam navigation teacher-facing and hides internal diagnostics by default', () => {
    vi.stubGlobal('ResizeObserver', class {
      observe() {}
      unobserve() {}
      disconnect() {}
    })

    render(
      <QueryClientProvider client={createAppQueryClient()}>
        <App />
      </QueryClientProvider>,
    )

    expect(screen.getByLabelText('真卷年份')).toBeInTheDocument()
    expect(screen.getByLabelText('真卷试卷')).toBeInTheDocument()
    expect(screen.getByLabelText('真卷题号')).toBeInTheDocument()
    expect(screen.queryByText('证据摘要（S003D）')).not.toBeInTheDocument()
    expect(screen.queryByText('B004')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('重裁 x')).not.toBeInTheDocument()
  })
})
