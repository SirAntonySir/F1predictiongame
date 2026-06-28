import { Heading, Text, Flex } from '@radix-ui/themes'

export function Placeholder({ title }: { title: string }) {
  return (
    <Flex direction="column" gap="2">
      <Heading size="6" className="display">{title}</Heading>
      <Text size="2" style={{ color: 'var(--on-surface-muted)' }}>Coming in a later slice.</Text>
    </Flex>
  )
}
