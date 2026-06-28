import { Card, Flex, Text } from '@radix-ui/themes'
import { ActionButton } from './ActionButton'

const CRAWL_KEY: string[][] = [['crawl-status']]

export function FetchControls() {
  return (
    <Card size="3">
      <Flex direction="column" gap="3">
        <Text size="1" className="label">Fetch controls</Text>
        <Flex gap="2" wrap="wrap">
          <ActionButton label="Bootstrap schedule" path="/admin/bootstrap" successMessage="Schedule bootstrapped" invalidateKeys={CRAWL_KEY} />
          <ActionButton label="Crawl tick" path="/admin/crawl" successMessage="Crawl tick triggered" invalidateKeys={CRAWL_KEY} />
          <ActionButton label="Refresh images" path="/admin/refresh-images" successMessage="Images refreshed" />
          <ActionButton label="Refresh OpenF1 metadata" path="/admin/refresh-openf1-metadata" successMessage="OpenF1 metadata refreshed" />
          <ActionButton label="Sync circuits" path="/admin/circuits/sync" successMessage="Circuits synced" />
        </Flex>
      </Flex>
    </Card>
  )
}
