import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'

type Permission = { id: string; key: string; description: string | null }
type Role = { id: string; name: string; description: string | null; permissionKeys: string[] }
type ManagedUser = {
  id: string
  email: string
  fullName: string | null
  isActive: boolean
  roleId: string | null
  grantedPermissionKeys: string[]
  deniedPermissionKeys: string[]
  effectivePermissionKeys: string[]
}
type ManagementState = { permissions: Permission[]; roles: Role[]; users: ManagedUser[] }
type View = 'users' | 'roles'

const UUID = /^[0-9a-f]{8}-[0-9a-f-]{27}$/i
const record = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value)
const strings = (value: unknown): value is string[] =>
  Array.isArray(value) && value.every((item) => typeof item === 'string')

function parseState(value: unknown): ManagementState {
  if (!record(value) || value.status !== 'user_management_ready' ||
      !Array.isArray(value.permissions) || !Array.isArray(value.roles) || !Array.isArray(value.users)) {
    throw new Error('invalid-management-state')
  }
  const permissions = value.permissions.map((item) => {
    if (!record(item) || typeof item.id !== 'string' || !UUID.test(item.id) ||
        typeof item.key !== 'string' || !(item.description === null || typeof item.description === 'string')) {
      throw new Error('invalid-permission')
    }
    return { id: item.id, key: item.key, description: item.description } as Permission
  })
  const roles = value.roles.map((item) => {
    if (!record(item) || typeof item.id !== 'string' || !UUID.test(item.id) || typeof item.name !== 'string' ||
        !(item.description === null || typeof item.description === 'string') || !strings(item.permission_keys)) {
      throw new Error('invalid-role')
    }
    return { id: item.id, name: item.name, description: item.description, permissionKeys: item.permission_keys } as Role
  })
  const users = value.users.map((item) => {
    if (!record(item) || typeof item.id !== 'string' || !UUID.test(item.id) || typeof item.email !== 'string' ||
        !(item.full_name === null || typeof item.full_name === 'string') || typeof item.is_active !== 'boolean' ||
        !(item.role_id === null || (typeof item.role_id === 'string' && UUID.test(item.role_id))) ||
        !strings(item.granted_permission_keys) || !strings(item.denied_permission_keys) || !strings(item.effective_permission_keys)) {
      throw new Error('invalid-user')
    }
    return {
      id: item.id, email: item.email, fullName: item.full_name, isActive: item.is_active,
      roleId: item.role_id, grantedPermissionKeys: item.granted_permission_keys,
      deniedPermissionKeys: item.denied_permission_keys, effectivePermissionKeys: item.effective_permission_keys,
    } as ManagedUser
  })
  return { permissions, roles, users }
}

export function UserRoleManagement({ onBack }: { onBack: () => void }) {
  const [view, setView] = useState<View>('users')
  const [state, setState] = useState<ManagementState | null>(null)
  const [selectedUserId, setSelectedUserId] = useState<string | null>(null)
  const [selectedRoleId, setSelectedRoleId] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<string | null>(null)

  const load = useCallback(async () => {
    setBusy(true); setMessage(null)
    const { data, error } = await supabase.rpc('get_user_management_state')
    try {
      if (error) throw error
      const next = parseState(data)
      setState(next)
      setSelectedUserId((id) => next.users.some((user) => user.id === id) ? id : next.users[0]?.id ?? null)
      setSelectedRoleId((id) => next.roles.some((role) => role.id === id) ? id : next.roles[0]?.id ?? null)
    } catch {
      setMessage('User administration data could not be loaded. Confirm your access and try again.')
    } finally { setBusy(false) }
  }, [])

  useEffect(() => { void load() }, [load])
  const user = state?.users.find((item) => item.id === selectedUserId) ?? null
  const role = state?.roles.find((item) => item.id === selectedRoleId) ?? null
  const roleById = useMemo(() => new Map(state?.roles.map((item) => [item.id, item]) ?? []), [state])

  const mutate = async (request: PromiseLike<{ error: unknown }>) => {
    setBusy(true); setMessage(null)
    const { error } = await request
    if (error) { setMessage('The change could not be saved. No permissions were changed.'); setBusy(false); return }
    await load()
  }

  return <main className="content management-page">
    <section className="fleet-header">
      <div><p className="eyebrow">ADMINISTRATION / ACCESS</p><h1>User &amp; Role Management</h1>
        <p>Assign one role per user, apply individual grants or denies, and review calculated effective access.</p></div>
      <div className="page-actions"><button className="secondary-action" type="button" onClick={onBack}>Back to Admin Console</button></div>
    </section>
    <div className="management-tabs" role="tablist" aria-label="Access management views">
      <button role="tab" aria-selected={view === 'users'} className={view === 'users' ? 'active' : ''} onClick={() => setView('users')}>Users</button>
      <button role="tab" aria-selected={view === 'roles'} className={view === 'roles' ? 'active' : ''} onClick={() => setView('roles')}>Roles</button>
      <button type="button" onClick={() => void load()} disabled={busy}>Refresh</button>
    </div>
    {message && <div className="data-message error-message" role="alert">{message}</div>}
    {busy && !state && <p className="access-status" role="status">Loading user administration…</p>}
    {state && view === 'users' && <section className="management-layout">
      <div className="vehicle-table-card"><div className="section-heading"><div><h2>Users</h2><p>{state.users.length} accounts</p></div></div>
        <div className="table-wrap"><table><thead><tr><th>User</th><th>Role</th><th>Status</th><th>Effective</th></tr></thead><tbody>
          {state.users.map((item) => <tr key={item.id} className={item.id === selectedUserId ? 'selected-row' : ''} onClick={() => setSelectedUserId(item.id)}>
            <td><strong>{item.fullName || item.email}</strong><br/><small>{item.email}</small></td><td>{item.roleId ? roleById.get(item.roleId)?.name ?? 'Unknown' : 'Unassigned'}</td>
            <td>{item.isActive ? 'Active' : 'Inactive'}</td><td>{item.effectivePermissionKeys.length}</td></tr>)}</tbody></table></div></div>
      <div className="details-panel access-editor"><div className="section-heading compact"><h2>{user?.fullName || user?.email}</h2><p>Role and permission overrides</p></div>
        {user && <div className="editor-body"><label>Assigned role<select value={user.roleId ?? ''} disabled={busy} onChange={(event) => void mutate(supabase.rpc('set_user_role_state', { p_user_id: user.id, p_role_id: event.target.value }))}>
          <option value="" disabled>Select a role</option>{state.roles.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
          <h3>Individual permissions</h3>{state.permissions.map((permission) => {
            const effect = user.deniedPermissionKeys.includes(permission.key) ? 'deny' : user.grantedPermissionKeys.includes(permission.key) ? 'grant' : 'inherit'
            return <label className="permission-row" key={permission.id}><span><strong>{permission.key}</strong><small>{permission.description}</small></span>
              <select aria-label={`${permission.key} override`} value={effect} disabled={busy} onChange={(event) => void mutate(supabase.rpc('set_user_permission_override_state', {
                p_user_id: user.id, p_permission_id: permission.id, p_effect: event.target.value === 'inherit' ? null : event.target.value,
              }))}><option value="inherit">Inherit</option><option value="grant">Grant</option><option value="deny">Deny</option></select></label>})}
          <h3>Effective permissions ({user.effectivePermissionKeys.length})</h3><div className="permission-chips">{user.effectivePermissionKeys.length ? user.effectivePermissionKeys.map((key) => <code key={key}>{key}</code>) : <span>None</span>}</div>
        </div>}</div>
    </section>}
    {state && view === 'roles' && <section className="management-layout">
      <div className="vehicle-table-card"><div className="section-heading"><div><h2>Roles</h2><p>Default permission sets</p></div></div>
        <div className="table-wrap"><table><thead><tr><th>Role</th><th>Default permissions</th></tr></thead><tbody>{state.roles.map((item) =>
          <tr key={item.id} className={item.id === selectedRoleId ? 'selected-row' : ''} onClick={() => setSelectedRoleId(item.id)}><td><strong>{item.name}</strong><br/><small>{item.description}</small></td><td>{item.permissionKeys.length}</td></tr>)}</tbody></table></div></div>
      <div className="details-panel access-editor"><div className="section-heading compact"><h2>{role?.name}</h2><p>Default permissions inherited by assigned users</p></div>
        {role && <div className="editor-body">{state.permissions.map((permission) => <label className="permission-row" key={permission.id}><span><strong>{permission.key}</strong><small>{permission.description}</small></span>
          <input type="checkbox" checked={role.permissionKeys.includes(permission.key)} disabled={busy} onChange={(event) => void mutate(supabase.rpc('set_role_permission_state', { p_role_id: role.id, p_permission_id: permission.id, p_enabled: event.target.checked }))}/></label>)}</div>}</div>
    </section>}
  </main>
}
