import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch, ApiError } from './client'
import { useToast } from '../ui/toast'
import type { AdminLeague, AdminLeagueDetail } from './types'

export function useAdminLeagues() {
  return useQuery({
    queryKey: ['admin-leagues'],
    queryFn: async () => (await apiFetch<{ leagues: AdminLeague[] }>('/admin/leagues')).leagues
  })
}

export function useAdminLeague(id: string) {
  return useQuery({
    queryKey: ['admin-league', id],
    queryFn: () => apiFetch<AdminLeagueDetail>(`/admin/leagues/${id}`)
  })
}

function err(e: unknown, fallback: string): string {
  return e instanceof ApiError ? e.message : fallback
}

export function useUpdateLeague(id: string) {
  const qc = useQueryClient()
  const { show } = useToast()
  return useMutation({
    mutationFn: (body: { name?: string; password?: string | null }) =>
      apiFetch(`/admin/leagues/${id}`, { method: 'PATCH', body }),
    onSuccess: () => {
      show('League updated', 'ok')
      void qc.invalidateQueries({ queryKey: ['admin-league', id] })
      void qc.invalidateQueries({ queryKey: ['admin-leagues'] })
    },
    onError: (e) => show(err(e, 'Update failed'), 'error')
  })
}

export function useRegenerateCode(id: string) {
  const qc = useQueryClient()
  const { show } = useToast()
  return useMutation({
    mutationFn: () => apiFetch<{ joinCode: string }>(`/admin/leagues/${id}/regenerate-code`, { method: 'POST' }),
    onSuccess: (r) => {
      show(`New join code: ${r.joinCode}`, 'ok')
      void qc.invalidateQueries({ queryKey: ['admin-league', id] })
      void qc.invalidateQueries({ queryKey: ['admin-leagues'] })
    },
    onError: (e) => show(err(e, 'Regenerate failed'), 'error')
  })
}

export function useDeleteLeague(id: string) {
  const qc = useQueryClient()
  const { show } = useToast()
  return useMutation({
    mutationFn: () => apiFetch(`/admin/leagues/${id}`, { method: 'DELETE' }),
    onSuccess: () => {
      show('League deleted', 'ok')
      void qc.invalidateQueries({ queryKey: ['admin-leagues'] })
    },
    onError: (e) => show(err(e, 'Delete failed'), 'error')
  })
}

export function useKickMember(id: string) {
  const qc = useQueryClient()
  const { show } = useToast()
  return useMutation({
    mutationFn: (userId: string) => apiFetch(`/admin/leagues/${id}/members/${userId}`, { method: 'DELETE' }),
    onSuccess: () => {
      show('Member removed', 'ok')
      void qc.invalidateQueries({ queryKey: ['admin-league', id] })
    },
    onError: (e) => show(err(e, 'Remove failed'), 'error')
  })
}
