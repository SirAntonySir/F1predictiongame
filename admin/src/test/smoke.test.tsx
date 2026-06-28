import { render, screen } from '@testing-library/react'
import { App } from '../App'

it('renders the admin scaffold heading', () => {
  render(<App />)
  expect(screen.getByRole('heading', { name: /f1pg admin/i })).toBeInTheDocument()
})
