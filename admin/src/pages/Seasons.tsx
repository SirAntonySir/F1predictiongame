import { Badge, Card, Flex, Heading, Text } from '@radix-ui/themes'
import { useSeasons } from '../api/sessions'
import { ActionButton } from '../components/ActionButton'

const SEASONS_KEY: string[][] = [['seasons']]

export function Seasons() {
  const { data, isLoading, error } = useSeasons()
  return (
    <Flex direction="column" gap="4">
      <Flex align="center" justify="between" gap="3">
        <Heading size="6" className="display">Seasons</Heading>
        <ActionButton label="Bootstrap current" path="/admin/bootstrap" successMessage="Schedule bootstrapped" invalidateKeys={SEASONS_KEY} />
      </Flex>

      {isLoading && <Text size="2">Loading…</Text>}
      {error && <Text size="2" color="red">Failed to load seasons.</Text>}

      {data && data.slice().sort((a, b) => b.year - a.year).map((s) => (
        <Card key={s.year} size="2">
          <Flex direction="column" gap="3">
            <Flex gap="2" align="center">
              <Heading size="4">{s.year}</Heading>
              {s.isCurrent && <Badge color="orange">current</Badge>}
            </Flex>
            <Flex gap="2" wrap="wrap">
              <ActionButton label="Activate" path={`/admin/seasons/${s.year}/activate`} successMessage={`Season ${s.year} activated`} invalidateKeys={SEASONS_KEY} />
              <ActionButton label="Rescore season" path={`/admin/rescore-season/${s.year}`} successMessage={`Season ${s.year} rescored`} />
              <ActionButton label="Preseason rescore" path={`/admin/preseason-rescore/${s.year}`} successMessage={`Preseason ${s.year} rescored`} />
            </Flex>
          </Flex>
        </Card>
      ))}
    </Flex>
  )
}
