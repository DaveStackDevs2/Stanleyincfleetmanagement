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
  sessionToken: string | null
  applicationUser: ApplicationUser | null
  accessGate: AccessGateResult | null
  roleNames: string[]
  permissionKeys: string[]
  loading: boolean
  error: string | null
  status: AuthorizationStatus
}

const signedOutState: AuthorizationState = {
  sessionToken: null,
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
    !isRecord(value) || value.status !== 'effective_permissions_ready' ||
    value.user_id !== userId || !isUuid(value.user_id) ||
    !Array.isArray(value.permission_keys) ||
    !value.permission_keys.every((key) => typeof key === 'string' && key.length > 0 && key.trim() === key)
  ) {
    throw new Error('invalid-permissions')
  }

  return [
    ...new Set(value.permission_keys as string[]),
  ]
}

function authorizationErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : 'unknown-authorization-error'
  return `Access could not be verified (${message}). Please contact an administrator.`
}

export function AuthorizationProvider({ children }: { children: ReactNode }) {
  const { session, user, loading: authenticationLoading } = useAuth()
  const [state, setState] = useState<AuthorizationState>(signedOutState)
  const requestId = useRef(0)

  useEffect(() => {
    const currentRequest = ++requestId.current
    const currentSessionToken = session?.access_token ?? null

    if (authenticationLoading) {
      setState({ ...signedOutState, loading: true, status: 'loading' })
      return
    }

    if (!user) {
      setState(signedOutState)
      return
    }

    setState({
      ...signedOutState,
      sessionToken: currentSessionToken,
      loading: true,
      status: 'loading',
    })

    const loadAuthorization = async () => {
      try {
        if (!session || session.user.id !== user.id || !isUuid(user.id)) {
          throw new Error('invalid-auth-user')
        }

        const { data: appUserData, error: appUserError } = await supabase
          .from('app_users')
          .select('id, auth_user_id, full_name, email, is_active')
          .eq('auth_user_id', user.id)
          .maybeSingle()

        if (appUserError) {
          throw new Error(`application-user-query: ${appUserError.message}`)
        }
        if (!appUserData) {
          throw new Error('application-user-not-found')
        }

        const applicationUser = parseApplicationUser(appUserData, user.id)

        const gateResponse = await supabase.rpc('get_user_auth_access_gate_state', {
          p_user_id: applicationUser.id,
        })
        if (gateResponse.error) {
          throw new Error(`access-gate-rpc: ${gateResponse.error.message}`)
        }

        const rolesResponse = await supabase.rpc('get_user_role_names_state', {
          p_user_id: applicationUser.id,
        })
        if (rolesResponse.error) {
          throw new Error(`roles-rpc: ${rolesResponse.error.message}`)
        }

        const permissionsResponse = await supabase.rpc(
          'get_current_user_effective_permissions_state',
        )
        if (permissionsResponse.error) {
          throw new Error(`permissions-rpc: ${permissionsResponse.error.message}`)
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
          sessionToken: currentSessionToken,
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
      } catch (error) {
        if (currentRequest !== requestId.current) return

        setState({
          ...signedOutState,
          sessionToken: currentSessionToken,
          error: authorizationErrorMessage(error),
          status: 'denied',
        })
      }
    }

    void loadAuthorization()
  }, [authenticationLoading, session, user])

  const value = useMemo<AuthorizationContextValue>(() => {
    const isCurrentSession =
      state.sessionToken === (session?.access_token ?? null)

    return {
      applicationUser: isCurrentSession ? state.applicationUser : null,
      accessGate: isCurrentSession ? state.accessGate : null,
      roleNames: isCurrentSession ? state.roleNames : [],
      permissionKeys: isCurrentSession ? state.permissionKeys : [],
      loading: state.loading || (!!session && !isCurrentSession),
      error: isCurrentSession ? state.error : null,
      status: isCurrentSession ? state.status : 'loading',
      isAuthorized:
        isCurrentSession &&
        state.status === 'authorized' &&
        state.accessGate?.status === 'auth_access_ready',
    }
  }, [session, state])

  return (
    <AuthorizationContext.Provider value={value}>
      {children}
    </AuthorizationContext.Provider>
  )
}
