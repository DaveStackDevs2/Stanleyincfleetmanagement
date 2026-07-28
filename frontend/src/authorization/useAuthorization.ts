import { useContext } from 'react'
import {
  AuthorizationContext,
  type AuthorizationContextValue,
} from './AuthorizationContext'

export function useAuthorization(): AuthorizationContextValue {
  const context = useContext(AuthorizationContext)

  if (!context) {
    throw new Error(
      'useAuthorization must be used within AuthorizationProvider',
    )
  }

  return context
}
