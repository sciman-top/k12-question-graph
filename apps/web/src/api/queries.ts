import { useQuery } from '@tanstack/react-query'
import {
  getAdminAiProviderSettings,
  getCutCandidates,
  getImportJob,
  getReadyHealth,
  searchQuestions,
  getSourceDocumentPreview,
  getSourceMaterials,
} from './client'

export const serverStateQueryKeys = {
  readyHealth: ['server-state', 'ready-health'] as const,
  adminAiProviderSettings: ['server-state', 'admin-ai-provider-settings'] as const,
  sourceMaterials: (sourceType?: string) => ['server-state', 'source-materials', sourceType ?? 'all'] as const,
  importJob: (id: string) => ['server-state', 'import-job', id] as const,
  sourcePreview: (sourceDocumentId: string) =>
    ['server-state', 'source-preview', sourceDocumentId] as const,
  cutCandidates: (sourceDocumentId: string) =>
    ['server-state', 'cut-candidates', sourceDocumentId] as const,
  questionSearch: (page: number, limit: number) =>
    ['server-state', 'question-search', page, limit] as const,
} as const

export function useReadyHealthQuery() {
  return useQuery({
    queryKey: serverStateQueryKeys.readyHealth,
    queryFn: getReadyHealth,
    retry: false,
    staleTime: 30_000,
  })
}

export function useAdminAiProviderSettingsQuery() {
  return useQuery({
    queryKey: serverStateQueryKeys.adminAiProviderSettings,
    queryFn: getAdminAiProviderSettings,
    retry: false,
    staleTime: 10_000,
  })
}

export function useSourceMaterialsQuery(sourceType?: string) {
  return useQuery({
    queryKey: serverStateQueryKeys.sourceMaterials(sourceType),
    queryFn: () => getSourceMaterials(sourceType),
    retry: false,
    staleTime: 30_000,
  })
}

export function useImportJobQuery(id: string, enabled = true) {
  return useQuery({
    queryKey: serverStateQueryKeys.importJob(id),
    queryFn: () => getImportJob(id),
    retry: false,
    staleTime: 15_000,
    enabled: enabled && id.length > 0,
  })
}

export function useSourcePreviewQuery(sourceDocumentId: string, enabled = true) {
  return useQuery({
    queryKey: serverStateQueryKeys.sourcePreview(sourceDocumentId),
    queryFn: () => getSourceDocumentPreview(sourceDocumentId),
    retry: false,
    staleTime: 15_000,
    enabled: enabled && sourceDocumentId.length > 0,
  })
}

export function useCutCandidatesQuery(sourceDocumentId: string, enabled = true) {
  return useQuery({
    queryKey: serverStateQueryKeys.cutCandidates(sourceDocumentId),
    queryFn: () => getCutCandidates(sourceDocumentId),
    retry: false,
    staleTime: 10_000,
    enabled: enabled && sourceDocumentId.length > 0,
  })
}

export function useQuestionSearchQuery(page = 1, limit = 10) {
  return useQuery({
    queryKey: serverStateQueryKeys.questionSearch(page, limit),
    queryFn: () => searchQuestions({ page, limit, sortBy: 'question_no', order: 'asc' }),
    retry: false,
    staleTime: 15_000,
  })
}
