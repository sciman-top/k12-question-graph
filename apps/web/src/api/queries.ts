import { useQuery } from '@tanstack/react-query'
import { getReadyHealth } from './client'

export const serverStateQueryKeys = {
  readyHealth: ['server-state', 'ready-health'] as const,
} as const

export function useReadyHealthQuery() {
  return useQuery({
    queryKey: serverStateQueryKeys.readyHealth,
    queryFn: getReadyHealth,
    retry: false,
    staleTime: 30_000,
  })
}
