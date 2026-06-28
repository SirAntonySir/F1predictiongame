import { Button } from '@radix-ui/themes'
import { useAdminAction } from '../api/actions'

export function ActionButton(props: {
  label: string
  path: string
  method?: string
  invalidateKeys?: unknown[][]
  successMessage: string
}) {
  const { run, isPending } = useAdminAction({
    path: props.path,
    method: props.method,
    invalidateKeys: props.invalidateKeys,
    successMessage: props.successMessage
  })
  return (
    <Button onClick={run} disabled={isPending} variant="surface">
      {isPending ? '…' : props.label}
    </Button>
  )
}
