import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import { getToken, setToken, clearToken, setUnauthorizedHandler } from '../api/client'
import { useToast } from '../ui/toast'

type AuthApi = {
  token: string | null
  signIn: (token: string) => void
  signOut: () => void
}
const AuthContext = createContext<AuthApi | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setTokenState] = useState<string | null>(() => getToken())
  const { show } = useToast()

  const signIn = useCallback((t: string) => {
    setToken(t)
    setTokenState(t)
  }, [])

  const signOut = useCallback(() => {
    clearToken()
    setTokenState(null)
  }, [])

  useEffect(() => {
    setUnauthorizedHandler(() => {
      signOut()
      show('Session expired — re-enter your token', 'error')
    })
    return () => setUnauthorizedHandler(null)
  }, [signOut, show])

  return <AuthContext.Provider value={{ token, signIn, signOut }}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthApi {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within an AuthProvider')
  return ctx
}
