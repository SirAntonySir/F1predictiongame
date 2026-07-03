import { afterEach, describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { AppShell } from '../components/AppShell'
import { AuthProvider } from '../auth/AuthContext'
import { ToastProvider } from '../ui/toast'

afterEach(() => { localStorage.clear() })

function renderShell() {
  return render(
    <ToastProvider>
      <AuthProvider>
        <MemoryRouter>
          <AppShell />
        </MemoryRouter>
      </AuthProvider>
    </ToastProvider>
  )
}

describe('AppShell', () => {
  it('renders the sidebar navigation links', () => {
    renderShell()
    expect(screen.getByRole('link', { name: /dashboard/i })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /leagues/i })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /sessions/i })).toBeInTheDocument()
  })

  it('clears the stored token on log out', async () => {
    localStorage.setItem('f1pg_admin_token', 'local-dev-token')
    renderShell()
    await userEvent.click(screen.getByRole('button', { name: /log out/i }))
    expect(localStorage.getItem('f1pg_admin_token')).toBeNull()
  })
})
