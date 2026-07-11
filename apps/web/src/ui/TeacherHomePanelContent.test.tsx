import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { TeacherHomePanelContent } from './TeacherHomePanelContent'
import { starterDemoSteps } from './workbenchData'

describe('TeacherHomePanelContent', () => {
  it('renders teacher-first actions and starter demo triggers', () => {
    const openTeacherView = vi.fn()
    const runStarterDemo = vi.fn()

    render(
      <TeacherHomePanelContent
        activeTeacherView="import"
        onOpenTeacherView={openTeacherView}
        onRunStarterDemo={runStarterDemo}
      />,
    )

    expect(screen.getByText('今天要做什么')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /打开导入/ })).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: /打开导入/ }))
    expect(openTeacherView).toHaveBeenCalledWith('import')

    fireEvent.click(screen.getByRole('button', { name: /导入样卷/i }))
    expect(runStarterDemo).toHaveBeenCalledWith(starterDemoSteps[0])
  })
})
