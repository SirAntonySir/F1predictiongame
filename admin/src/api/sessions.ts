import { useQuery } from '@tanstack/react-query'
import { apiFetch } from './client'
import type { AdminSessionRow, SessionMeta, SessionResultRow } from './types'

export function useAdminSessions() {
  return useQuery({
    queryKey: ['admin-sessions'],
    queryFn: async () => (await apiFetch<{ sessions: AdminSessionRow[] }>('/admin/sessions')).sessions
  })
}

export function useSession(id: number) {
  return useQuery({
    queryKey: ['session', id],
    queryFn: () => apiFetch<SessionMeta>(`/api/sessions/${id}`)
  })
}

export function useSessionResults(id: number) {
  return useQuery({
    queryKey: ['session-results', String(id)],
    queryFn: () => apiFetch<SessionResultRow[]>(`/api/sessions/${id}/results`)
  })
}
