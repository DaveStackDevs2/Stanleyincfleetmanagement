import { useCallback, useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react'
import type { Factor } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { useAuth } from './useAuth'

type GateState =
  | { kind: 'checking' }
  | { kind: 'error' }
  | { kind: 'verify'; factorId: string }
  | { kind: 'enroll'; factorId: string; qrCode: string; secret: string }
  | { kind: 'ready' }

const genericError = 'Security verification could not be completed. Please try again.'

function compareFactors(left: Factor, right: Factor) {
  return left.created_at.localeCompare(right.created_at) || left.id.localeCompare(right.id)
}

export function MfaGate({ children }: { children: ReactNode }) {
  const { session, signOut } = useAuth()
  const [gateState, setGateState] = useState<GateState>({ kind: 'checking' })
  const [code, setCode] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [signOutError, setSignOutError] = useState<string | null>(null)
  const enrollmentRef = useRef<Promise<GateState> | null>(null)

  const determineGateState = useCallback(async (): Promise<GateState> => {
    const { data: assurance, error: assuranceError } =
      await supabase.auth.mfa.getAuthenticatorAssuranceLevel()

    if (assuranceError || !assurance.currentLevel) {
      throw new Error('MFA assurance check failed')
    }

    if (assurance.currentLevel === 'aal2') {
      return { kind: 'ready' }
    }

    const { data: factors, error: factorsError } = await supabase.auth.mfa.listFactors()

    if (factorsError) {
      throw new Error('MFA factor check failed')
    }

    const verifiedTotpFactor = [...factors.totp].sort(compareFactors)[0]

    if (verifiedTotpFactor) {
      return { kind: 'verify', factorId: verifiedTotpFactor.id }
    }

    if (!enrollmentRef.current) {
      enrollmentRef.current = (async () => {
        const { data, error: enrollmentError } = await supabase.auth.mfa.enroll({
          factorType: 'totp',
          friendlyName: 'Stanley TMS',
        })

        if (enrollmentError) {
          throw new Error('MFA enrollment failed')
        }

        return {
          kind: 'enroll' as const,
          factorId: data.id,
          qrCode: data.totp.qr_code,
          secret: data.totp.secret,
        }
      })()
    }

    return enrollmentRef.current
  }, [])

  const checkMfa = useCallback(async () => {
    setGateState({ kind: 'checking' })
    setError(null)

    try {
      setGateState(await determineGateState())
    } catch {
      enrollmentRef.current = null
      setGateState({ kind: 'error' })
      setError(genericError)
    }
  }, [determineGateState])

  useEffect(() => {
    let active = true

    setGateState({ kind: 'checking' })
    setError(null)

    void determineGateState()
      .then((nextState) => {
        if (active) setGateState(nextState)
      })
      .catch(() => {
        if (active) {
          enrollmentRef.current = null
          setGateState({ kind: 'error' })
          setError(genericError)
        }
      })

    return () => {
      active = false
    }
  }, [determineGateState, session?.access_token])

  const verifyCode = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (submitting || (gateState.kind !== 'verify' && gateState.kind !== 'enroll')) return

    if (!/^\d{6}$/.test(code)) {
      setError('Enter the six-digit code from your authenticator app.')
      return
    }

    setSubmitting(true)
    setError(null)

    try {
      const { data: challenge, error: challengeError } = await supabase.auth.mfa.challenge({
        factorId: gateState.factorId,
      })

      if (challengeError) throw new Error('MFA challenge failed')

      const { error: verificationError } = await supabase.auth.mfa.verify({
        factorId: gateState.factorId,
        challengeId: challenge.id,
        code,
      })

      if (verificationError) throw new Error('MFA verification failed')

      const { error: refreshError } = await supabase.auth.refreshSession()
      if (refreshError) throw new Error('Session refresh failed')

      const { data: assurance, error: assuranceError } =
        await supabase.auth.mfa.getAuthenticatorAssuranceLevel()

      if (assuranceError || assurance.currentLevel !== 'aal2') {
        throw new Error('Session was not promoted')
      }

      setGateState({ kind: 'ready' })
      setCode('')
    } catch {
      setError(genericError)
    } finally {
      setSubmitting(false)
    }
  }

  const handleSignOut = async () => {
    setSignOutError(null)
    try {
      await signOut()
    } catch {
      setSignOutError('Unable to sign out. Please try again.')
    }
  }

  if (gateState.kind === 'ready') return children

  if (gateState.kind === 'checking') {
    return <div className="access-status" role="status" aria-live="polite">Checking security verification…</div>
  }

  if (gateState.kind === 'error') {
    return (
      <main className="access-page">
        <section className="access-card" aria-labelledby="mfa-error-heading">
          <p className="access-brand">STANLEY CHEVROLET BELFAST</p>
          <h1 id="mfa-error-heading">Security verification unavailable</h1>
          {error && <div className="access-error" role="alert">{error}</div>}
          {signOutError && <div className="access-error" role="alert">{signOutError}</div>}
          <div className="access-actions">
            <button type="button" onClick={() => void checkMfa()}>Retry</button>
            <button type="button" className="secondary-button" onClick={() => void handleSignOut()}>Sign out</button>
          </div>
        </section>
      </main>
    )
  }

  const enrolling = gateState.kind === 'enroll'

  return (
    <main className="access-page">
      <section className="access-card" aria-labelledby="mfa-heading">
        <p className="access-brand">STANLEY CHEVROLET BELFAST</p>
        <h1 id="mfa-heading">{enrolling ? 'Set up security verification' : 'Security verification'}</h1>
        {enrolling ? (
          <>
            <p>Scan this QR code with your authenticator app, then enter the six-digit code it generates.</p>
            <img className="mfa-qr-code" src={gateState.qrCode} alt="QR code for Stanley TMS authenticator setup" />
            <p className="mfa-secret-label">Can’t scan the code? Enter this setup key manually:</p>
            <code className="mfa-secret">{gateState.secret}</code>
          </>
        ) : (
          <p>Enter the six-digit code from your authenticator app.</p>
        )}
        <form className="sign-in-form" onSubmit={(event) => void verifyCode(event)}>
          <label htmlFor="mfa-code">Six-digit code</label>
          <input
            id="mfa-code"
            type="text"
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={6}
            pattern="[0-9]{6}"
            required
            value={code}
            onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 6))}
          />
          {error && <div className="access-error" role="alert">{error}</div>}
          {signOutError && <div className="access-error" role="alert">{signOutError}</div>}
          <button type="submit" disabled={submitting}>
            {submitting ? 'Verifying…' : enrolling ? 'Complete setup' : 'Verify'}
          </button>
          <button type="button" className="secondary-button" disabled={submitting} onClick={() => void handleSignOut()}>
            Sign out
          </button>
        </form>
      </section>
    </main>
  )
}
