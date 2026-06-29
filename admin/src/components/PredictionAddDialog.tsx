import { useMemo, useState } from 'react'
import { Button, Dialog, Flex, Select, Text, TextField } from '@radix-ui/themes'
import { useSavePrediction } from '../api/admin'
import { useAdminLeagues, useAdminLeague } from '../api/leagues'

export function PredictionAddDialog({ sessionId, picksRequired, existingUserIds, onClose }: {
  sessionId: string
  picksRequired: number
  existingUserIds: Set<string>
  onClose: () => void
}) {
  const save = useSavePrediction(sessionId)
  const leaguesQ = useAdminLeagues()
  const [leagueId, setLeagueId] = useState('')
  const leagueQ = useAdminLeague(leagueId)
  const [userId, setUserId] = useState('')
  const [picks, setPicks] = useState(() =>
    Array.from({ length: picksRequired }, (_, i) => ({ position: i + 1, driverCode: '' }))
  )

  // Only members who don't already have a prediction for this session — editing
  // existing picks is the row's Edit button, not Add.
  const candidates = useMemo(
    () => (leagueQ.data?.members ?? []).filter((m) => !existingUserIds.has(m.userId)),
    [leagueQ.data, existingUserIds]
  )

  function setDriver(i: number, code: string) {
    setPicks((s) => s.map((p, idx) => (idx === i ? { ...p, driverCode: code.toUpperCase() } : p)))
  }

  function onLeagueChange(id: string) {
    setLeagueId(id)
    setUserId('') // members differ per league
  }

  const allFilled = picks.every((p) => p.driverCode.trim() !== '')
  const canSave = userId !== '' && allFilled && !save.isPending

  function onSave() {
    save.mutate({ userId, picks }, { onSuccess: onClose })
  }

  return (
    <Dialog.Root open onOpenChange={(o) => { if (!o) onClose() }}>
      <Dialog.Content maxWidth="360px">
        <Dialog.Title>Add prediction</Dialog.Title>
        <Flex direction="column" gap="3" mt="2">
          <label>
            <Text size="1" className="label">League</Text>
            <Select.Root value={leagueId} onValueChange={onLeagueChange}>
              <Select.Trigger mt="1" placeholder="Pick a league" aria-label="League" style={{ width: '100%' }} />
              <Select.Content>
                {(leaguesQ.data ?? []).map((l) => (
                  <Select.Item key={l.id} value={l.id}>{l.name}</Select.Item>
                ))}
              </Select.Content>
            </Select.Root>
          </label>

          <label>
            <Text size="1" className="label">Player</Text>
            <Select.Root value={userId} onValueChange={setUserId} disabled={!leagueId}>
              <Select.Trigger mt="1" placeholder="Pick a player" aria-label="Player" style={{ width: '100%' }} />
              <Select.Content>
                {candidates.map((m) => (
                  <Select.Item key={m.userId} value={m.userId}>{m.displayName}</Select.Item>
                ))}
              </Select.Content>
            </Select.Root>
            {leagueId && candidates.length === 0 && !leagueQ.isLoading && (
              <Text size="1" color="gray" mt="1">Every member already has a prediction.</Text>
            )}
          </label>

          {picks.map((p, i) => (
            <label key={p.position}>
              <Text size="1" className="label">P{p.position}</Text>
              <TextField.Root
                mt="1"
                aria-label={`P${p.position} driver`}
                placeholder="e.g. VER"
                value={p.driverCode}
                onChange={(e) => setDriver(i, e.target.value)}
              />
            </label>
          ))}

          <Flex gap="2" justify="end" mt="2">
            <Button variant="soft" color="gray" onClick={onClose}>Cancel</Button>
            <Button onClick={onSave} disabled={!canSave}>Add</Button>
          </Flex>
        </Flex>
      </Dialog.Content>
    </Dialog.Root>
  )
}
