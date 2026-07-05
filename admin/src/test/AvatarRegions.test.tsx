import { describe, it, expect } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Theme } from '@radix-ui/themes'
import { AvatarRegions } from '../pages/AvatarRegions'
import { hexToHsv, normalizeHex } from '../utils/avatarRegions'

const FIXTURE = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 200">
<path fill="#13cadc" d="M 0 0 L 10 0 L 10 10 Z"/>
<path fill="#13cadc" d="M 20 0 L 30 0 L 30 10 Z"/>
<path fill="#2b9c38" d="M 0 100 L 10 100 L 10 110 Z"/>
</svg>`

function renderPage() {
  return render(
    <Theme>
      <AvatarRegions />
    </Theme>
  )
}

async function loadFixture() {
  const file = new File([FIXTURE], 'pose9.svg', { type: 'image/svg+xml' })
  // jsdom's File lacks .text() in some versions — polyfill on the instance.
  if (typeof file.text !== 'function') {
    Object.defineProperty(file, 'text', { value: () => Promise.resolve(FIXTURE) })
  }
  await userEvent.upload(screen.getByLabelText('Load pose SVG'), file)
  await waitFor(() => expect(screen.getByText(/3 segments/)).toBeInTheDocument())
}

describe('AvatarRegions page', () => {
  it('loads an SVG and lists its color groups with regions', async () => {
    renderPage()
    await loadFixture()
    expect(screen.getByText('#13cadc')).toBeInTheDocument()
    expect(screen.getByText('#2b9c38')).toBeInTheDocument()
    // Helmet badge counts the 2 teal segments; legs the 1 green one.
    expect(screen.getByText('Helmet · 2')).toBeInTheDocument()
    expect(screen.getByText('Legs · 1')).toBeInTheDocument()
  })

  it('preset mode recolors the canvas and Copy Dart exports the preset literal', async () => {
    const user = userEvent.setup()
    renderPage()
    await loadFixture()

    // Default seed is Undercut (brand-red helmet). Switching the canvas to
    // Preset mode must recolor the teal helmet paths.
    await user.click(screen.getByRole('radio', { name: 'Preset' }))
    const canvas = document.querySelector('[data-idx="0"]')!
    expect(canvas.getAttribute('fill')).not.toBe('#13cadc')

    // Change the legs color via the picker → ops update (swatch follows).
    const legsInput = screen.getByLabelText('Legs color') as HTMLInputElement
    expect(legsInput.value).toBeTruthy()

    await user.click(screen.getByRole('button', { name: /Copy Dart/ }))
    const dart = await navigator.clipboard.readText()
    expect(dart).toContain(`AvatarPreset('undercut', 'Undercut', {`)
    expect(dart).toContain('AvatarRegion.helmet:')
  })

  it('selecting a color group and assigning a region updates counts and enables download', async () => {
    renderPage()
    await loadFixture()
    expect(screen.getByRole('button', { name: /Download corrected SVG/ })).toBeDisabled()

    // Select the teal group from the table, reassign to Legs.
    await userEvent.click(screen.getByText('#13cadc'))
    expect(screen.getByText(/2 segments selected/)).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Legs' }))

    await waitFor(() => expect(screen.getByText('Legs · 3')).toBeInTheDocument())
    expect(screen.getByText('Helmet · 0')).toBeInTheDocument()
    expect(screen.getByText('edited')).toBeInTheDocument()
    expect(
      screen.getByRole('button', { name: /Download corrected SVG \(2\)/ })
    ).toBeEnabled()
  })

  it('splitting a sub-selection creates a new color group that can take its own region', async () => {
    const user = userEvent.setup()
    renderPage()
    await loadFixture()

    // Segment mode: select ONE of the two teal segments via the canvas.
    await user.click(screen.getByRole('radio', { name: 'Pick segment' }))
    const seg = document.querySelector('[data-idx="1"]')!
    await user.pointer([{ keys: '[MouseLeft]', target: seg as Element }])
    await waitFor(() => expect(screen.getByText(/1 segment selected/)).toBeInTheDocument())

    // A proper subset of the teal group → splittable.
    const split = screen.getByRole('button', { name: 'Split into new group' })
    expect(split).toBeEnabled()
    await user.click(split)

    // Groups table now shows a third group (the nudged teal twin)…
    await waitFor(() =>
      expect(document.querySelectorAll('table tr').length).toBeGreaterThanOrEqual(3)
    )
    // …and the still-selected split segments can take their own region.
    await user.click(screen.getByRole('button', { name: 'Boots' }))
    await waitFor(() => expect(screen.getByText('Boots · 1')).toBeInTheDocument())
    expect(screen.getByText('Helmet · 1')).toBeInTheDocument()
  })

  it('custom regions can be added, assigned, and exported as Dart', async () => {
    const user = userEvent.setup()
    renderPage()
    await loadFixture()

    await user.type(screen.getByLabelText('New region name'), 'Visor Trim')
    await user.click(screen.getByRole('button', { name: 'Add region' }))
    await waitFor(() => expect(screen.getByText('Visor Trim · 0')).toBeInTheDocument())

    // Assign the green legs group to the new region.
    await user.click(screen.getByText('#2b9c38'))
    await user.click(screen.getByRole('button', { name: 'Visor Trim' }))
    await waitFor(() => expect(screen.getByText('Visor Trim · 1')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: /Copy Dart \(regions\)/ }))
    const dart = await navigator.clipboard.readText()
    expect(dart).toContain(`visorTrim('Visor Trim',`)
    expect(dart).toContain('return AvatarRegion.visorTrim;')
  })

  it('Remove (background) deletes the group from the canvas; Line art reclassifies', async () => {
    const user = userEvent.setup()
    renderPage()
    await loadFixture()

    // Remove the green group — a background-removal action.
    await user.click(screen.getByText('#2b9c38'))
    await user.click(screen.getByRole('button', { name: 'Remove (background)' }))
    await waitFor(() => expect(screen.getByText('Removed · 1')).toBeInTheDocument())
    expect(document.querySelector('[data-idx="2"]')).toBeNull()
    expect(screen.getByRole('button', { name: /Download corrected SVG \(1\)/ })).toBeEnabled()

    // Line art: the whole teal group (2 elements) joins the ink bucket.
    await user.click(screen.getByText('#13cadc'))
    await user.click(screen.getByRole('button', { name: 'Line art' }))
    await waitFor(() => expect(screen.getByText('Line art · 2')).toBeInTheDocument())
    expect(screen.getByText('Helmet · 0')).toBeInTheDocument()
  })

  it('typing a hex code recolors a preset region like the picker does', async () => {
    const user = userEvent.setup()
    renderPage()
    await loadFixture()
    await user.click(screen.getByRole('radio', { name: 'Preset' }))

    const hexField = screen.getByLabelText('Helmet color hex') as HTMLInputElement
    await user.clear(hexField)
    await user.type(hexField, '00d2be')

    // The swatch input tracks the derived op for the typed color.
    const swatch = screen.getByLabelText('Helmet color') as HTMLInputElement
    await waitFor(() => expect(hexToHsv(swatch.value).h).toBeCloseTo(hexToHsv('#00d2be').h, 0))

    // Draft text stays as typed until blur, even though the swatch normalizes.
    expect(hexField.value).toBe('00d2be')
    await user.tab()
    expect(normalizeHex(hexField.value)).toBe(hexField.value)

    // Invalid input never commits.
    const before = swatch.value
    await user.clear(hexField)
    await user.type(hexField, 'zz')
    expect(swatch.value).toBe(before)
  })

  it('zoom controls change the canvas scale readout', async () => {
    const user = userEvent.setup()
    renderPage()
    await loadFixture()
    expect(screen.getByText('100%')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Zoom in' }))
    expect(screen.getByText('140%')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Fit' }))
    expect(screen.getByText('100%')).toBeInTheDocument()
  })
})
