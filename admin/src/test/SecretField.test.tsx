import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useState } from 'react'
import { SecretField } from '../ui/SecretField'

function Harness() {
  const [value, setValue] = useState('')
  return <SecretField aria-label="Set new password" secretLabel="password" value={value} onChange={(e) => setValue(e.target.value)} />
}

describe('SecretField', () => {
  it('is not a real password input, so browsers do not offer to save it', () => {
    render(<Harness />)
    const input = screen.getByLabelText(/set new password/i)
    expect(input).toHaveAttribute('type', 'text')
    expect(input).toHaveAttribute('autocomplete', 'off')
  })

  it('masks via CSS by default and reveals on toggle', async () => {
    render(<Harness />)
    const input = screen.getByLabelText(/set new password/i)
    await userEvent.type(input, 'hunter2')
    expect(input).toHaveValue('hunter2')
    expect(input.closest('.secret-hidden')).not.toBeNull()
    await userEvent.click(screen.getByRole('button', { name: /show password/i }))
    expect(input.closest('.secret-hidden')).toBeNull()
    await userEvent.click(screen.getByRole('button', { name: /hide password/i }))
    expect(input.closest('.secret-hidden')).not.toBeNull()
  })
})
