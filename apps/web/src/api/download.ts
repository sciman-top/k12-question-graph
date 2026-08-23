export function triggerBrowserDownload(blob: Blob, fileName: string): void {
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = fileName
  anchor.click()
  // 部分浏览器在同步 revoke 下会中断下载,延迟到下一个宏任务再释放 Object URL。
  setTimeout(() => URL.revokeObjectURL(url), 0)
}
