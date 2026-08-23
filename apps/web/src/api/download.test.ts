import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { triggerBrowserDownload } from './download'

describe('triggerBrowserDownload', () => {
  const createObjectUrl = vi.fn<(blob: Blob) => string>()
  const revokeObjectUrl = vi.fn<(url: string) => void>()

  beforeEach(() => {
    vi.useFakeTimers()
    createObjectUrl.mockReset().mockReturnValue('blob:download-url')
    revokeObjectUrl.mockReset()
    vi.stubGlobal('URL', {
      ...URL,
      createObjectURL: createObjectUrl,
      revokeObjectURL: revokeObjectUrl,
    })
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
  })

  it('starts the download synchronously and releases the object URL on the next macrotask', () => {
    const click = vi.fn()
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(click)
    const blob = new Blob(['paper'])

    triggerBrowserDownload(blob, 'paper.docx')

    expect(createObjectUrl).toHaveBeenCalledWith(blob)
    expect(click).toHaveBeenCalledTimes(1)
    expect(revokeObjectUrl).not.toHaveBeenCalled()

    vi.advanceTimersByTime(0)
    expect(revokeObjectUrl).toHaveBeenCalledWith('blob:download-url')
  })

  it('keeps the anchor download attribute bound to the requested file name', () => {
    let capturedHref = ''
    let capturedDownload = ''
    const originalSetAttribute = HTMLAnchorElement.prototype.setAttribute
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) {
      capturedHref = this.href
      capturedDownload = this.download
    })
    Object.defineProperty(HTMLAnchorElement.prototype, 'setAttribute', {
      configurable: true,
      value: originalSetAttribute,
    })

    triggerBrowserDownload(new Blob(['paper']), '试卷-导出.docx')

    expect(capturedHref).toBe('blob:download-url')
    expect(capturedDownload).toBe('试卷-导出.docx')
  })
})
