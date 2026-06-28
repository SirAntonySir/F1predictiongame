import { useMutation, useQueryClient } from '@tanstack/react-query'
import { apiFetch, ApiError } from './client'
import { useToast } from '../ui/toast'

export function useAdminAction(opts: {
  path: string
  method?: string
  invalidateKeys?: string[][]
  successMessage: string
}): { run: () => void; isPending: boolean } {
  const qc = useQueryClient()
  const { show } = useToast()

  const mutation = useMutation({
    mutationFn: () => apiFetch(opts.path, { method: opts.method ?? 'POST' }),
    onSuccess: () => {
      show(opts.successMessage, 'ok')
      for (const key of opts.invalidateKeys ?? []) {
        void qc.invalidateQueries({ queryKey: key })
      }
    },
    onError: (err) => {
      show(err instanceof ApiError ? err.message : 'Request failed', 'error')
    }
  })

  return { run: () => mutation.mutate(), isPending: mutation.isPending }
}
