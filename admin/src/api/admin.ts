import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch, ApiError } from './client'
import { useToast } from '../ui/toast'
import type { AdminPrediction, AdminUserRow } from './types'

function errMsg(e: unknown, fallback: string): string {
  return e instanceof ApiError ? e.message : fallback
}

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

// --- user mutations ---

export function useUpdateUser(id: string) {
  const qc = useQueryClient()
  const { show } = useToast()
  return useMutation({
    mutationFn: (body: { displayName?: string; email?: string }) =>
      apiFetch(`/admin/users/${id}`, { method: 'PATCH', body }),
    onSuccess: () => { show('User updated', 'ok'); void qc.invalidateQueries({ queryKey: ['admin-users'] }) },
    onError: (e) => show(errMsg(e, 'Update failed'), 'error')
  })
}

export function useSetUserPassword(id: string) {
  const { show } = useToast()
  return useMutation({
    mutationFn: (password: string) =>
      apiFetch(`/admin/users/${id}/set-password`, { method: 'POST', body: { password } }),
    onSuccess: () => show('Password set', 'ok'),
    onError: (e) => show(errMsg(e, 'Set password failed'), 'error')
  })
}

// --- prediction mutations (userId passed at mutate time for per-row use) ---

export function useSavePrediction(sessionId: string) {
  const qc = useQueryClient()
  const { show } = useToast()
  return useMutation({
    mutationFn: (input: { userId: string; picks: { position: number; driverCode: string }[] }) =>
      apiFetch(`/admin/predictions/${input.userId}/${sessionId}/picks`, { method: 'PUT', body: { picks: input.picks } }),
    onSuccess: () => { show('Picks saved', 'ok'); void qc.invalidateQueries({ queryKey: ['admin-predictions', sessionId] }) },
    onError: (e) => show(errMsg(e, 'Save failed'), 'error')
  })
}

export function useDeletePrediction(sessionId: string) {
  const qc = useQueryClient()
  const { show } = useToast()
  return useMutation({
    mutationFn: (userId: string) => apiFetch(`/admin/predictions/${userId}/${sessionId}`, { method: 'DELETE' }),
    onSuccess: () => { show('Prediction deleted', 'ok'); void qc.invalidateQueries({ queryKey: ['admin-predictions', sessionId] }) },
    onError: (e) => show(errMsg(e, 'Delete failed'), 'error')
  })
}

// id passed at mutate time so a list can drive per-row deletes with one hook.
export function useDeleteUser() {
  const qc = useQueryClient()
  const { show } = useToast()
  return useMutation({
    mutationFn: (id: string) => apiFetch(`/admin/users/${id}`, { method: 'DELETE' }),
    onSuccess: () => { show('User deleted', 'ok'); void qc.invalidateQueries({ queryKey: ['admin-users'] }) },
    onError: (e) => show(errMsg(e, 'Delete failed'), 'error')
  })
}
