import type { ReactNode } from 'react'
import { useAuthorization } from '../authorization/useAuthorization'
import { useAuth } from './useAuth'
import { SignInPage } from './SignInPage'

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

  if (authenticationLoading) {
    return <div className="access-status">Checking your session…</div>
  }

  if (!user) {
    setPathname('/sign-in')
    return <SignInPage />
  }

  if (authorizationLoading) {
    return <div className="access-status">Checking your access…</div>
  }

  if (!isAuthorized) {
    return (
      <main className="access-page">
        <section className="access-card" aria-labelledby="denied-heading">
          <p className="access-brand">STANLEY CHEVROLET BELFAST</p>
          <h1 id="denied-heading">Access denied</h1>
          <p>{error ?? 'Your account is not currently authorized to use this application.'}</p>
          <button type="button" onClick={() => void signOut()}>Sign out</button>
        </section>
      </main>
    )
  }

  if (window.location.pathname === '/sign-in') {
    setPathname('/')
  }

  return children
}
