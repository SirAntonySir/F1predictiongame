import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ToastProvider, useToast } from '../ui/toast'

function Trigger() {
  const { show } = useToast()
  return <button onClick={() => show('Saved!', 'ok')}>fire</button>
}

describe('toast', () => {
  it('shows a toast message when triggered', async () => {
    render(
      <ToastProvider>
        <Trigger />
      </ToastProvider>
    )
    expect(screen.queryByText('Saved!')).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'fire' }))
    expect(await screen.findByText('Saved!')).toBeInTheDocument()
  })

  it('throws if useToast is used outside the provider', () => {
    function Bad() { useToast(); return null }
    // React logs the error; assert the render throws.
    expect(() => render(<Bad />)).toThrow(/ToastProvider/)
  })
})
