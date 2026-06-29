import { useQuery } from '@tanstack/react-query'
import { apiFetch } from './client'
import type { AdminDriver, AdminConstructor } from './types'

export function useAdminDrivers() {
  return useQuery({
    queryKey: ['admin-drivers'],
    queryFn: async () => (await apiFetch<{ drivers: AdminDriver[] }>('/admin/drivers')).drivers
  })
}

export function useAdminConstructors() {
  return useQuery({
    queryKey: ['admin-constructors'],
    queryFn: async () => (await apiFetch<{ constructors: AdminConstructor[] }>('/admin/constructors')).constructors
  })
}
