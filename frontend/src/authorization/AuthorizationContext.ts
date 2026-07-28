import { createContext } from 'react'

export type ApplicationUser = {
  id: string
  authUserId: string
  fullName: string | null
  email: string
  isActive: boolean
}

export type AccessGateResult = {
  status: string
  userId: string
  authUserId: string
}

export type AuthorizationStatus =
  | 'signed-out'
  | 'loading'
  | 'authorized'
  | 'denied'

export type AuthorizationContextValue = {
  applicationUser: ApplicationUser | null
  accessGate: AccessGateResult | null
  roleNames: readonly string[]
  permissionKeys: readonly string[]
  loading: boolean
  error: string | null
  status: AuthorizationStatus
  isAuthorized: boolean
}

export const AuthorizationContext = createContext<
  AuthorizationContextValue | undefined
>(undefined)
