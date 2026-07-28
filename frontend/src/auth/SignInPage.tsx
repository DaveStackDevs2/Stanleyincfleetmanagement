import { useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'

export function SignInPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const signIn = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setSubmitting(true)
    setError(null)

    const { error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password,
    })

    if (signInError) {
      setError('Unable to sign in. Check your credentials and try again.')
      setSubmitting(false)
    }
  }

  return (
    <main className="access-page">
      <section className="access-card" aria-labelledby="sign-in-heading">
        <p className="access-brand">STANLEY CHEVROLET BELFAST</p>
        <h1 id="sign-in-heading">Sign in</h1>
        <p>Use your Transportation Management System account.</p>
        <form className="sign-in-form" onSubmit={signIn}>
          <label htmlFor="email">Email</label>
          <input
            id="email"
            type="email"
            autoComplete="email"
            required
            value={email}
            onChange={(event) => setEmail(event.target.value)}
          />
          <label htmlFor="password">Password</label>
          <input
            id="password"
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />
          {error && <div className="access-error" role="alert">{error}</div>}
          <button type="submit" disabled={submitting}>
            {submitting ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      </section>
    </main>
  )
}
