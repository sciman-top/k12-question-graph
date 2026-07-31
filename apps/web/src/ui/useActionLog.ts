import { useCallback, useRef, useState } from 'react'

export function useActionLog() {
  const sequence = useRef(0)
  const [actionLog, setActionLog] = useState<Array<{ id: number; message: string }>>([])

  const appendLog = useCallback((message: string) => {
    sequence.current += 1
    const entry = { id: sequence.current, message }
    setActionLog((current) => [entry, ...current].slice(0, 5))
  }, [])

  const replaceLatestWithUndoLog = useCallback(() => {
    setActionLog((current) => {
      sequence.current += 1
      return [
        { id: sequence.current, message: `已撤销：${current[0]?.message ?? '最近操作'}` },
        ...current.slice(1),
      ]
    })
  }, [])

  return { actionLog, appendLog, replaceLatestWithUndoLog }
}
