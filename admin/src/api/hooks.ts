import { useQuery } from '@tanstack/react-query'
import { apiFetch } from './client'
import type { CrawlStatus } from './types'

export function useCrawlStatus() {
  return useQuery({
    queryKey: ['crawl-status'],
    queryFn: () => apiFetch<CrawlStatus>('/admin/crawl/status')
  })
}
