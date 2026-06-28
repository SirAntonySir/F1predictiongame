import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ToastProvider } from '../ui/toast'
import { FetchControls } from '../components/FetchControls'

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient()
  return <QueryClientProvider client={qc}><ToastProvider>{ui}</ToastProvider></QueryClientProvider>
}

describe('FetchControls', () => {
  it('renders all five trigger buttons', () => {
    render(wrap(<FetchControls />))
    for (const label of ['Bootstrap schedule', 'Crawl tick', 'Refresh images', 'Refresh OpenF1 metadata', 'Sync circuits']) {
      expect(screen.getByRole('button', { name: label })).toBeInTheDocument()
    }
  })
})
