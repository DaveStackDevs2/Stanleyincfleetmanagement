import { useEffect, useState, type ReactNode } from 'react'
import { useAuthorization } from '../authorization/useAuthorization'
import { useAuth } from './useAuth'
import { SignInPage } from './SignInPage'
import { MfaGate } from './MfaGate'

function setPathname(pathname: string) {
  if (window.location.pathname !== pathname) {
    window.history.replaceState(null, '', pathname)
  }
}

export function AuthGate({ children }: { children: ReactNode }) {
  const { loading: authenticationLoading, user, signOut } = useAuth()
  const {
    loading: authorizationLoading,
    isAuthorized,
    error,
  } = useAuthorization()
  const [signOutError, setSignOutError] = useState<string | null>(null)

  useEffect(() => {
    if (authenticationLoading) return

    if (!user) {
      setPathname('/sign-in')
    } else if (isAuthorized && window.location.pathname === '/sign-in') {
      setPathname('/')
    }
  }, [authenticationLoading, isAuthorized, user])

  const handleSignOut = async () => {
    setSignOutError(null)

    try {
      await signOut()
    } catch {
      setSignOutError('Unable to sign out. Please try again.')
    }
  }

  if (authenticationLoading) {
    return <div className="access-status" role="status" aria-live="polite">Checking your session…</div>
  }

  if (!user) {
    return <SignInPage />
  }

  if (authorizationLoading) {
    return <div className="access-status" role="status" aria-live="polite">Checking your access…</div>
  }

  if (!isAuthorized) {
    return (
      <main className="access-page">
        <section className="access-card" aria-labelledby="denied-heading">
          <p className="access-brand">STANLEY CHEVROLET BELFAST</p>
          <h1 id="denied-heading">Access denied</h1>
          <p>{error ?? 'Your account is not currently authorized to use this application.'}</p>
          {signOutError && <div className="access-error" role="alert">{signOutError}</div>}
          <button type="button" onClick={() => void handleSignOut()}>Sign out</button>
        </section>
      </main>
    )
  }

  return <MfaGate>{children}</MfaGate>
}
