import React from 'react'
import ReactDOM from 'react-dom/client'
import { Theme } from '@radix-ui/themes'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from 'react-router-dom'
import '@radix-ui/themes/styles.css'
import './theme/tokens.css'
import { TokenGate } from './auth/TokenGate'
import { router } from './router'

const queryClient = new QueryClient()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Theme appearance="dark" accentColor="red" grayColor="gray" radius="medium">
      <QueryClientProvider client={queryClient}>
        <TokenGate>
          <RouterProvider router={router} />
        </TokenGate>
      </QueryClientProvider>
    </Theme>
  </React.StrictMode>
)
