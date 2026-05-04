export const uiStateBoundary = {
  teacherDraftState: 'component-local-state',
  highRiskOperationState: 'api-contract-source-of-truth',
  serverState: 'tanstack-query-only',
} as const
