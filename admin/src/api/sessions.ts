import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { apiFetch, ApiError } from './client'
import { useToast } from '../ui/toast'
import type { AdminSessionRow, Season, SessionMeta, SessionResultRow } from './types'

export function useSeasons() {
  return useQuery({
    queryKey: ['seasons'],
    queryFn: () => apiFetch<Season[]>('/api/seasons')
  })
}

// Sessions for one season. Disabled until a season is known (the page derives
// the default from the current season), so we never fetch the unfiltered
// all-seasons list.
export function useAdminSessions(season: number | undefined) {
  return useQuery({
    queryKey: ['admin-sessions', season ?? null],
    queryFn: async () =>
      (await apiFetch<{ sessions: AdminSessionRow[] }>(`/admin/sessions?season=${season}`)).sessions,
    enabled: season !== undefined
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

type ResultInput = Partial<SessionResultRow> & { position: number }

export function useSaveResult(id: number) {
  const qc = useQueryClient()
  const { show } = useToast()
  return useMutation({
    mutationFn: (input: { mode: 'edit' | 'add'; row: ResultInput }) => {
      if (input.mode === 'edit') {
        const { position, ...fields } = input.row
        return apiFetch(`/admin/sessions/${id}/results/${position}`, { method: 'PATCH', body: fields })
      }
      return apiFetch(`/admin/sessions/${id}/results`, { method: 'POST', body: input.row })
    },
    onSuccess: () => { show('Saved', 'ok'); void qc.invalidateQueries({ queryKey: ['session-results', String(id)] }) },
    onError: (err) => show(err instanceof ApiError ? err.message : 'Save failed', 'error')
  })
}

export function useDeleteResult(id: number) {
  const qc = useQueryClient()
  const { show } = useToast()
  return useMutation({
    mutationFn: (position: number) => apiFetch(`/admin/sessions/${id}/results/${position}`, { method: 'DELETE' }),
    onSuccess: () => { show('Deleted', 'ok'); void qc.invalidateQueries({ queryKey: ['session-results', String(id)] }) },
    onError: (err) => show(err instanceof ApiError ? err.message : 'Delete failed', 'error')
  })
}
