import { useState } from 'react'
import { Button, Dialog, Flex, Text, TextField } from '@radix-ui/themes'
import { useSaveResult } from '../api/sessions'
import type { SessionResultRow } from '../api/types'

type Props = {
  sessionId: number
  mode: 'edit' | 'add'
  initial?: SessionResultRow
  onClose: () => void
}

export function ResultEditDialog({ sessionId, mode, initial, onClose }: Props) {
  const save = useSaveResult(sessionId)
  const [f, setF] = useState({
    position: initial?.position ?? 1,
    driverCode: initial?.driverCode ?? '',
    driverName: initial?.driverName ?? '',
    constructorId: initial?.constructorId ?? '',
    constructorName: initial?.constructorName ?? '',
    points: initial?.points ?? null as number | null,
    status: initial?.status ?? ''
  })

  function field(label: string, key: keyof typeof f, type: 'text' | 'number' = 'text') {
    return (
      <label>
        <Text size="1" className="label">{label}</Text>
        <TextField.Root
          mt="1"
          type={type}
          aria-label={label}
          value={f[key] === null ? '' : String(f[key])}
          onChange={(e) => setF((s) => ({ ...s, [key]: type === 'number' ? (e.target.value === '' ? null : Number(e.target.value)) : e.target.value }))}
        />
      </label>
    )
  }

  function onSave() {
    save.mutate(
      { mode, row: { position: Number(f.position), driverCode: f.driverCode, driverName: f.driverName, constructorId: f.constructorId, constructorName: f.constructorName, points: f.points, status: f.status || null } },
      { onSuccess: onClose }
    )
  }

  return (
    <Dialog.Root open onOpenChange={(o) => { if (!o) onClose() }}>
      <Dialog.Content maxWidth="420px">
        <Dialog.Title>{mode === 'add' ? 'Add result' : `Edit P${initial?.position}`}</Dialog.Title>
        <Flex direction="column" gap="3" mt="2">
          {mode === 'add' && field('Position', 'position', 'number')}
          {field('Driver code', 'driverCode')}
          {field('Driver name', 'driverName')}
          {field('Constructor id', 'constructorId')}
          {field('Constructor name', 'constructorName')}
          {field('Points', 'points', 'number')}
          {field('Status', 'status')}
          <Flex gap="2" justify="end" mt="2">
            <Button variant="soft" color="gray" onClick={onClose}>Cancel</Button>
            <Button onClick={onSave} disabled={save.isPending}>{save.isPending ? '…' : 'Save'}</Button>
          </Flex>
        </Flex>
      </Dialog.Content>
    </Dialog.Root>
  )
}
