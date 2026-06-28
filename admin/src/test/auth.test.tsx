import { afterEach, describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ToastProvider } from '../ui/toast'
import { AuthProvider, useAuth } from '../auth/AuthContext'
import { setUnauthorizedHandler } from '../api/client'

afterEach(() => { localStorage.clear(); setUnauthorizedHandler(null); vi.restoreAllMocks() })

function Probe() {
  const { token, signIn, signOut } = useAuth()
  return (
    <div>
      <span data-testid="token">{token ?? 'none'}</span>
      <button onClick={() => signIn('abc')}>in</button>
      <button onClick={() => signOut()}>out</button>
    </div>
  )
}

function wrap(ui: React.ReactNode) {
  return <ToastProvider><AuthProvider>{ui}</AuthProvider></ToastProvider>
}

describe('AuthProvider', () => {
  it('signIn stores the token and signOut clears it', async () => {
    render(wrap(<Probe />))
    expect(screen.getByTestId('token')).toHaveTextContent('none')
    await userEvent.click(screen.getByRole('button', { name: 'in' }))
    expect(screen.getByTestId('token')).toHaveTextContent('abc')
    expect(localStorage.getItem('f1pg_admin_token')).toBe('abc')
    await userEvent.click(screen.getByRole('button', { name: 'out' }))
    expect(screen.getByTestId('token')).toHaveTextContent('none')
    expect(localStorage.getItem('f1pg_admin_token')).toBeNull()
  })
})
