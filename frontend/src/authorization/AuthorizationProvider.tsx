import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../auth/useAuth'
import {
  AuthorizationContext,
  type AccessGateResult,
  type ApplicationUser,
  type AuthorizationContextValue,
  type AuthorizationStatus,
} from './AuthorizationContext'

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

type AuthorizationState = {
  applicationUser: ApplicationUser | null
  accessGate: AccessGateResult | null
  roleNames: string[]
  permissionKeys: string[]
  loading: boolean
  error: string | null
  status: AuthorizationStatus
}

const signedOutState: AuthorizationState = {
  applicationUser: null,
  accessGate: null,
  roleNames: [],
  permissionKeys: [],
  loading: false,
  error: null,
  status: 'signed-out',
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value)

const isUuid = (value: unknown): value is string =>
  typeof value === 'string' && UUID_PATTERN.test(value)

function parseApplicationUser(value: unknown, authUserId: string): ApplicationUser {
  if (
    !isRecord(value) ||
    !isUuid(value.id) ||
    !isUuid(value.auth_user_id) ||
    value.auth_user_id !== authUserId ||
    typeof value.email !== 'string' ||
    typeof value.is_active !== 'boolean' ||
    !(value.full_name === null || typeof value.full_name === 'string')
  ) {
    throw new Error('invalid-application-user')
  }

  return {
    id: value.id,
    authUserId: value.auth_user_id,
    fullName: value.full_name,
    email: value.email,
    isActive: value.is_active,
  }
}

function parseGate(value: unknown, user: ApplicationUser): AccessGateResult {
  if (
    !isRecord(value) ||
    typeof value.status !== 'string' ||
    !isUuid(value.user_id) ||
    !isUuid(value.auth_user_id) ||
    value.user_id !== user.id ||
    value.auth_user_id !== user.authUserId
  ) {
    throw new Error('invalid-access-gate')
  }

  return {
    status: value.status,
    userId: value.user_id,
    authUserId: value.auth_user_id,
  }
}

function parseRoles(value: unknown, userId: string): string[] {
  if (
    !isRecord(value) ||
    value.status !== 'user_roles_ready' ||
    value.user_id !== userId ||
    !Array.isArray(value.roles) ||
    !value.roles.every(
      (role) =>
        typeof role === 'string' &&
        role.length > 0 &&
        role.trim() === role,
    )
  ) {
    throw new Error('invalid-role-names')
  }

  return [...new Set(value.roles)]
}

function parsePermissions(value: unknown, userId: string): string[] {
  if (
    !Array.isArray(value) ||
    !value.every(
      (row) =>
        isRecord(row) &&
        row.user_id === userId &&
        isUuid(row.user_id) &&
        typeof row.permission_key === 'string' &&
        row.permission_key.length > 0 &&
        row.permission_key.trim() === row.permission_key,
    )
  ) {
    throw new Error('invalid-permissions')
  }

  return [
    ...new Set(value.map((row) => (row as Record<string, unknown>).permission_key as string)),
  ]
}

export function AuthorizationProvider({ children }: { children: ReactNode }) {
  const { user, loading: authenticationLoading } = useAuth()
  const [state, setState] = useState<AuthorizationState>(signedOutState)
  const requestId = useRef(0)

  useEffect(() => {
    const currentRequest = ++requestId.current

    if (authenticationLoading) {
      setState({ ...signedOutState, loading: true, status: 'loading' })
      return
    }

    if (!user) {
      setState(signedOutState)
      return
    }

    setState({ ...signedOutState, loading: true, status: 'loading' })

    const loadAuthorization = async () => {
      try {
        if (!isUuid(user.id)) {
          throw new Error('invalid-auth-user')
        }

        const { data: appUserData, error: appUserError } = await supabase
          .from('app_users')
          .select('id, auth_user_id, full_name, email, is_active')
          .eq('auth_user_id', user.id)
          .maybeSingle()

        if (appUserError || !appUserData) {
          throw new Error('application-user-unavailable')
        }

        const applicationUser = parseApplicationUser(appUserData, user.id)
        const [gateResponse, rolesResponse, permissionsResponse] =
          await Promise.all([
            supabase.rpc('get_user_auth_access_gate_state', {
              p_user_id: applicationUser.id,
            }),
            supabase.rpc('get_user_role_names_state', {
              p_user_id: applicationUser.id,
            }),
            supabase
              .from('v_user_effective_permissions')
              .select('user_id, permission_key')
              .eq('user_id', applicationUser.id),
          ])

        if (gateResponse.error || rolesResponse.error || permissionsResponse.error) {
          throw new Error('authorization-contract-unavailable')
        }

        const accessGate = parseGate(gateResponse.data, applicationUser)
        const roleNames = parseRoles(rolesResponse.data, applicationUser.id)
        const permissionKeys = parsePermissions(
          permissionsResponse.data,
          applicationUser.id,
        )
        const isAuthorized = accessGate.status === 'auth_access_ready'

        if (currentRequest !== requestId.current) return

        setState({
          applicationUser,
          accessGate,
          roleNames,
          permissionKeys,
          loading: false,
          error: isAuthorized
            ? null
            : 'Your account is not currently authorized to use this application.',
          status: isAuthorized ? 'authorized' : 'denied',
        })
      } catch {
        if (currentRequest !== requestId.current) return

        setState({
          ...signedOutState,
          error: 'Access could not be verified. Please contact an administrator.',
          status: 'denied',
        })
      }
    }

    void loadAuthorization()
  }, [authenticationLoading, user])

  const value = useMemo<AuthorizationContextValue>(
    () => ({
      ...state,
      isAuthorized:
        state.status === 'authorized' &&
        state.accessGate?.status === 'auth_access_ready',
    }),
    [state],
  )

  return (
    <AuthorizationContext.Provider value={value}>
      {children}
    </AuthorizationContext.Provider>
  )
}
