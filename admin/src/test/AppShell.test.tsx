import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { AppShell } from '../components/AppShell'

describe('AppShell', () => {
  it('renders the sidebar navigation links', () => {
    render(
      <MemoryRouter>
        <AppShell />
      </MemoryRouter>
    )
    expect(screen.getByRole('link', { name: /dashboard/i })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /leagues/i })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /sessions/i })).toBeInTheDocument()
  })
})
