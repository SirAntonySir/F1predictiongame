import { useState } from 'react'
import { Button, Dialog, Flex, Text, TextField } from '@radix-ui/themes'
import { useUpdateUser, useSetUserPassword } from '../api/admin'
import { SecretField } from '../ui/SecretField'
import type { AdminUserRow } from '../api/types'

export function UserEditDialog({ user, onClose }: { user: AdminUserRow; onClose: () => void }) {
  const update = useUpdateUser(user.id)
  const setPw = useSetUserPassword(user.id)
  const [displayName, setDisplayName] = useState(user.displayName)
  const [email, setEmail] = useState(user.email)
  const [password, setPassword] = useState('')

  function onSave() {
    const body: { displayName?: string; email?: string } = {}
    if (displayName !== user.displayName) body.displayName = displayName
    if (email !== user.email) body.email = email
    const run = async () => {
      if (Object.keys(body).length) await update.mutateAsync(body)
      if (password) await setPw.mutateAsync(password)
      onClose()
    }
    // Errors are surfaced by each mutation's onError toast; swallow the
    // rejection so the dialog stays open instead of unhandled-rejecting.
    void run().catch(() => {})
  }

  return (
    <Dialog.Root open onOpenChange={(o) => { if (!o) onClose() }}>
      <Dialog.Content maxWidth="420px">
        <Dialog.Title>Edit {user.displayName}</Dialog.Title>
        <Flex direction="column" gap="3" mt="2">
          <label>
            <Text size="1" className="label">Display name</Text>
            <TextField.Root mt="1" aria-label="Display name" value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
          </label>
          <label>
            <Text size="1" className="label">Email</Text>
            <TextField.Root mt="1" aria-label="Email" value={email} onChange={(e) => setEmail(e.target.value)} />
          </label>
          <label>
            <Text size="1" className="label">Set new password</Text>
            <SecretField mt="1" aria-label="Set new password" secretLabel="password" placeholder="(leave blank to keep)" value={password} onChange={(e) => setPassword(e.target.value)} />
          </label>
          <Flex gap="2" justify="end" mt="2">
            <Button variant="soft" color="gray" onClick={onClose}>Cancel</Button>
            <Button onClick={onSave} disabled={update.isPending || setPw.isPending}>Save</Button>
          </Flex>
        </Flex>
      </Dialog.Content>
    </Dialog.Root>
  )
}
