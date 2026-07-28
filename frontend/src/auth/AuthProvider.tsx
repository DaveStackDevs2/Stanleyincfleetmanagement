import { useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { AuthContext, type AuthContextValue } from './AuthContext'

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let active = true
    let authEventReceived = false

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      if (active) {
        authEventReceived = true
        setSession(nextSession)
        setLoading(false)
      }
    })

    const initializeSession = async () => {
      try {
        const { data } = await supabase.auth.getSession()

        if (active && !authEventReceived) {
          setSession(data.session)
        }
      } catch {
        if (active && !authEventReceived) {
          setSession(null)
        }
      } finally {
        if (active && !authEventReceived) {
          setLoading(false)
        }
      }
    }

    void initializeSession()

    return () => {
      active = false
      subscription.unsubscribe()
    }
  }, [])

  const value = useMemo<AuthContextValue>(
    () => ({
      session,
      user: session?.user ?? null,
      loading,
      signOut: async () => {
        const { error } = await supabase.auth.signOut()

        if (error) {
          throw new Error('Unable to sign out. Please try again.')
        }
      },
    }),
    [loading, session],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
