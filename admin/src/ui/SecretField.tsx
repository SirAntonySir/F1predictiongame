import { useState } from 'react'
import { IconButton, TextField } from '@radix-ui/themes'
import { EyeIcon, EyeOffIcon } from './icons'

type Props = Omit<React.ComponentProps<typeof TextField.Root>, 'type'> & {
  /** Subject used in the toggle's aria-label, e.g. "password" → "Show password". */
  secretLabel?: string
}

/**
 * Masked input for secrets the browser must NOT offer to save (admin-set user
 * passwords, tokens). Deliberately type="text" — password managers hook their
 * save prompt on type="password" — with CSS text-security doing the masking
 * (see .secret-hidden in theme/tokens.css) and vendor data-attributes telling
 * 1Password/LastPass to stay away.
 */
export function SecretField({ secretLabel = 'value', className, ...props }: Props) {
  const [reveal, setReveal] = useState(false)
  return (
    <TextField.Root
      {...props}
      type="text"
      autoComplete="off"
      data-1p-ignore=""
      data-lpignore="true"
      data-form-type="other"
      className={[className, reveal ? undefined : 'secret-hidden'].filter(Boolean).join(' ') || undefined}
    >
      <TextField.Slot side="right">
        <IconButton
          type="button"
          variant="ghost"
          color="gray"
          size="1"
          aria-label={reveal ? `Hide ${secretLabel}` : `Show ${secretLabel}`}
          onClick={() => setReveal((r) => !r)}
        >
          {reveal ? <EyeOffIcon /> : <EyeIcon />}
        </IconButton>
      </TextField.Slot>
    </TextField.Root>
  )
}
