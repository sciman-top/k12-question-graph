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
    const scrollIntoView = vi.fn()
    vi.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => {
      callback(0)
      return 1
    })
    Object.defineProperty(Element.prototype, 'scrollIntoView', {
      configurable: true,
      value: scrollIntoView,
    })

    render(
      <QueryClientProvider client={createAppQueryClient()}>
        <App />
      </QueryClientProvider>,
    )

    const appHeading = screen.getByRole('heading', { name: '校本题谱' })
    const homeEntries = within(screen.getByRole('region', { name: '普通教师入口' }))
    const expectedViewByEntry = new Map([
      ['打开导入', 'import'],
      ['导入试卷', 'import'],
      ['找题组卷', 'paper'],
      ['导入成绩', 'scores'],
      ['查看分析', 'analysis'],
    ])
    const workspace = document.querySelector('main.workspace')
    expect(workspace).not.toBeNull()

    for (const [name, view] of expectedViewByEntry) {
      fireEvent.click(homeEntries.getByRole('button', { name: new RegExp(name) }))
      expect(appHeading).toBeInTheDocument()
      expect(workspace).toHaveClass(`teacher-view-${view}`)
    }

    expect(scrollIntoView).toHaveBeenCalledWith({ behavior: 'smooth', block: 'start' })
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

  it('keeps admin governance outside the teacher workspace until explicitly opened', () => {
    vi.stubGlobal('ResizeObserver', class {
      observe() {}
      unobserve() {}
      disconnect() {}
    })

    const { container } = render(
      <QueryClientProvider client={createAppQueryClient()}>
        <App />
      </QueryClientProvider>,
    )

    const teacherWorkspace = container.querySelector<HTMLElement>('main.workspace')
    const adminWorkspace = container.querySelector<HTMLElement>('aside[data-shell="admin-governance-staging"]')
    const adminEntry = screen.getByRole('button', { name: '管理员调试入口' })

    expect(teacherWorkspace).not.toContainElement(adminWorkspace)
    expect(adminWorkspace).toHaveAttribute('aria-hidden', 'true')
    expect(adminEntry).toHaveAttribute('aria-expanded', 'false')
  })
})
