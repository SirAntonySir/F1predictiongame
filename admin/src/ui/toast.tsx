import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from 'react'
import { Box, Card, Flex, Text } from '@radix-ui/themes'

export type ToastTone = 'ok' | 'error' | 'info'
type Toast = { id: number; message: string; tone: ToastTone }

type ToastApi = { show: (message: string, tone?: ToastTone) => void }
const ToastContext = createContext<ToastApi | null>(null)

const TONE_COLOR: Record<ToastTone, string> = {
  ok: 'var(--ok)',
  error: 'var(--accent)',
  info: 'var(--on-surface-muted)'
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const nextId = useRef(1)

  const show = useCallback((message: string, tone: ToastTone = 'info') => {
    const id = nextId.current++
    setToasts((t) => [...t, { id, message, tone }])
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 4000)
  }, [])

  return (
    <ToastContext.Provider value={{ show }}>
      {children}
      <Box style={{ position: 'fixed', right: 16, bottom: 16, zIndex: 1000, maxWidth: 360 }}>
        <Flex direction="column" gap="2">
          {toasts.map((t) => (
            <Card key={t.id} size="2" style={{ borderLeft: `4px solid ${TONE_COLOR[t.tone]}` }}>
              <Text size="2">{t.message}</Text>
            </Card>
          ))}
        </Flex>
      </Box>
    </ToastContext.Provider>
  )
}

export function useToast(): ToastApi {
  const ctx = useContext(ToastContext)
  if (!ctx) throw new Error('useToast must be used within a ToastProvider')
  return ctx
}
