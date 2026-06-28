import { useQuery } from '@tanstack/react-query'
import { apiFetch } from './client'
import type { AdminPrediction, AdminUserRow } from './types'

export function useAdminUsers(query: string) {
  return useQuery({
    queryKey: ['admin-users', query],
    queryFn: () =>
      apiFetch<{ users: AdminUserRow[]; total: number }>(
        `/admin/users${query ? `?query=${encodeURIComponent(query)}` : ''}`
      )
  })
}

export function useAdminPredictions(sessionId: string) {
  return useQuery({
    queryKey: ['admin-predictions', sessionId],
    queryFn: () =>
      apiFetch<{ predictions: AdminPrediction[] }>(
        `/admin/predictions?sessionId=${encodeURIComponent(sessionId)}`
      ),
    enabled: sessionId.trim() !== ''
  })
}
