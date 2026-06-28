import { useState } from 'react'
import { Button, Dialog, Flex, Text, TextField } from '@radix-ui/themes'
import { useSavePrediction } from '../api/admin'
import type { AdminPrediction } from '../api/types'

export function PredictionEditDialog({ sessionId, prediction, onClose }: {
  sessionId: string
  prediction: AdminPrediction
  onClose: () => void
}) {
  const save = useSavePrediction(sessionId)
  const [picks, setPicks] = useState(prediction.picks.map((p) => ({ ...p })))

  function setDriver(i: number, code: string) {
    setPicks((s) => s.map((p, idx) => (idx === i ? { ...p, driverCode: code.toUpperCase() } : p)))
  }

  function onSave() {
    save.mutate({ userId: prediction.userId, picks }, { onSuccess: onClose })
  }

  return (
    <Dialog.Root open onOpenChange={(o) => { if (!o) onClose() }}>
      <Dialog.Content maxWidth="360px">
        <Dialog.Title>{prediction.displayName} · picks</Dialog.Title>
        <Flex direction="column" gap="2" mt="2">
          {picks.map((p, i) => (
            <label key={p.position}>
              <Text size="1" className="label">P{p.position}</Text>
              <TextField.Root
                mt="1"
                aria-label={`P${p.position} driver`}
                value={p.driverCode}
                onChange={(e) => setDriver(i, e.target.value)}
              />
            </label>
          ))}
          <Flex gap="2" justify="end" mt="2">
            <Button variant="soft" color="gray" onClick={onClose}>Cancel</Button>
            <Button onClick={onSave} disabled={save.isPending}>Save</Button>
          </Flex>
        </Flex>
      </Dialog.Content>
    </Dialog.Root>
  )
}
