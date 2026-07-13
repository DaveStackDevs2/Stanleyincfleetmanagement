import { useEffect, useMemo, useState } from 'react'
import './App.css'

type AdminFeature = {
  title: string
  description: string
  status: 'Foundation' | 'Planned' | 'Coming Soon'
}

type Page = 'admin' | 'fleet'
type FleetFilter = 'All' | 'Active' | 'Retired' | 'CTP' | 'Loaner' | 'Rental' | 'Available' | 'Out' | 'Maintenance'

type Vehicle = {
  vehicle_id: string
  vin: string | null
  vin_last8: string
  stock_number: string | null
  model_year: number | null
  model: string | null
  trim: string | null
  fleet_type: string | null
  vehicle_status: string | null
  odometer: number | null
  qualified_miles: number | null
  ontrac_days_in_service: number | null
  license_plate: string | null
  plate_expiration_date: string | null
  record_source: string | null
  ontrac_first_seen_at: string | null
  ontrac_last_seen_at: string | null
  plate_sync_required: boolean
  ctp_program_active: boolean
  ctp_program_entered_at: string | null
  ctp_entry_mileage: number | null
  is_retired: boolean
  retired_at: string | null
  retirement_reason: string | null
  location: string | null
  notes: string | null
}

const adminFeatures: AdminFeature[] = [
  { title: 'Fleet Administration', description: 'View, search, add, edit, retire, reactivate, and review every fleet vehicle.', status: 'Foundation' },
  { title: 'GM OnTrac Sync Center', description: 'Upload In-Service and Expiring Plates reports, preview changes, review errors, and maintain import history.', status: 'Foundation' },
  { title: 'CTP Threshold Settings', description: 'Manage preferred and absolute day and odometer limits for CTP vehicles.', status: 'Foundation' },
  { title: 'Retirement Review', description: 'Review vehicles missing from OnTrac and approve retirement with an effective date and reason.', status: 'Planned' },
  { title: 'Plate Administration', description: 'Assign plates, track expiration dates, review plate changes, and preserve plate history.', status: 'Planned' },
  { title: 'Vehicle Import Review', description: 'Review new vehicles, unmatched VINs, manual entries, duplicate candidates, and failed rows.', status: 'Planned' },
  { title: 'Users & Permissions', description: 'Manage users, roles, access levels, account status, and Admin permissions.', status: 'Planned' },
  { title: 'Locations & Fleet Types', description: 'Manage dealership locations, vehicle classifications, and fleet-use categories.', status: 'Planned' },
  { title: 'Rates, Fees & Billing Rules', description: 'Manage rental rates, pay types, taxes, late-fee rules, and billing defaults.', status: 'Planned' },
  { title: 'Notifications', description: 'Manage alert rules, recipients, severity, delivery channels, and cooldown periods.', status: 'Planned' },
  { title: 'Audit & Activity History', description: 'Review administrative changes, vehicle history, imports, approvals, and user activity.', status: 'Planned' },
  { title: 'System Settings', description: 'Manage dealership-wide defaults, integrations, security settings, and operational rules.', status: 'Planned' },
  { title: 'Reports & Exports', description: 'Run fleet, CTP, utilization, plate, retirement, rental, and exception reports.', status: 'Planned' },
  { title: 'QR Code Administration', description: 'Create and manage vehicle and workflow QR codes.', status: 'Coming Soon' },
]

const fleetFilters: FleetFilter[] = ['All', 'Active', 'Retired', 'CTP', 'Loaner', 'Rental', 'Available', 'Out', 'Maintenance']

const formatNumber = (value: number | null) => value == null ? '—' : value.toLocaleString()
const formatDate = (value: string | null) => value ? new Date(value).toLocaleDateString() : '—'

function App() {
  const [page, setPage] = useState<Page>('admin')
  const [vehicles, setVehicles] = useState<Vehicle[]>([])
  const [selectedVehicleId, setSelectedVehicleId] = useState<string | null>(null)
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState<FleetFilter>('All')
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)

  const openFeature = (title: string) => {
    if (title === 'Fleet Administration') setPage('fleet')
  }

  useEffect(() => {
    if (page !== 'fleet') return

    const loadVehicles = async () => {
      const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined
      const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

      if (!supabaseUrl || !anonKey) {
        setLoadError('Supabase environment variables are not configured.')
        return
      }

      setLoading(true)
      setLoadError(null)

      try {
        const response = await fetch(`${supabaseUrl}/rest/v1/v_admin_vehicle_master_state?select=*&order=model_year.desc,model.asc`, {
          headers: {
            apikey: anonKey,
            Authorization: `Bearer ${anonKey}`,
          },
        })

        if (!response.ok) {
          const message = await response.text()
          throw new Error(message || `Supabase returned ${response.status}`)
        }

        const data = await response.json() as Vehicle[]
        setVehicles(data)
        setSelectedVehicleId((current) => current && data.some((vehicle) => vehicle.vehicle_id === current) ? current : data[0]?.vehicle_id ?? null)
      } catch (error) {
        setLoadError(error instanceof Error ? error.message : 'Unable to load fleet vehicles.')
      } finally {
        setLoading(false)
      }
    }

    void loadVehicles()
  }, [page])

  const filteredVehicles = useMemo(() => {
    const term = search.trim().toLowerCase()

    return vehicles.filter((vehicle) => {
      const matchesSearch = !term || [
        vehicle.vin,
        vehicle.vin_last8,
        vehicle.license_plate,
        vehicle.stock_number,
        vehicle.model,
        vehicle.trim,
      ].some((value) => value?.toLowerCase().includes(term))

      const status = vehicle.vehicle_status?.toLowerCase() ?? ''
      const fleetType = vehicle.fleet_type?.toLowerCase() ?? ''
      const matchesFilter =
        filter === 'All' ||
        (filter === 'Active' && !vehicle.is_retired) ||
        (filter === 'Retired' && vehicle.is_retired) ||
        (filter === 'CTP' && vehicle.ctp_program_active) ||
        (filter === 'Loaner' && fleetType.includes('loaner')) ||
        (filter === 'Rental' && fleetType.includes('rental')) ||
        (filter === 'Available' && status === 'available') ||
        (filter === 'Out' && status.includes('out')) ||
        (filter === 'Maintenance' && status.includes('maintenance'))

      return matchesSearch && matchesFilter
    })
  }, [vehicles, search, filter])

  const selectedVehicle = vehicles.find((vehicle) => vehicle.vehicle_id === selectedVehicleId) ?? null
  const statusCards = [
    ['Total Fleet', vehicles.length],
    ['Available', vehicles.filter((vehicle) => vehicle.vehicle_status?.toLowerCase() === 'available').length],
    ['Out', vehicles.filter((vehicle) => vehicle.vehicle_status?.toLowerCase().includes('out')).length],
    ['CTP', vehicles.filter((vehicle) => vehicle.ctp_program_active).length],
    ['Retired', vehicles.filter((vehicle) => vehicle.is_retired).length],
    ['Plate Sync Required', vehicles.filter((vehicle) => vehicle.plate_sync_required).length],
  ]

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand-block">
          <div className="brand-mark">STANLEY</div>
          <div className="brand-name">Chevrolet Belfast</div>
          <div className="brand-subtitle">Transportation Management System</div>
        </div>

        <nav className="sidebar-nav" aria-label="Primary navigation">
          <button type="button">Dashboard</button>
          <button type="button">Reservations</button>
          <button type="button">Active Transportation</button>
          <button type="button" className={page === 'fleet' ? 'active' : ''} onClick={() => setPage('fleet')}>Fleet</button>
          <button type="button" className={page === 'admin' ? 'active' : ''} onClick={() => setPage('admin')}>Admin Console</button>
          <button type="button">Reports</button>
        </nav>
      </aside>

      <div className="workspace">
        <header className="topbar">
          <div>
            <strong>{page === 'fleet' ? 'Fleet Administration' : 'Admin Console'}</strong>
            <span>{page === 'fleet' ? 'Connected to the vehicle master view' : 'Foundation and planned controls'}</span>
          </div>
          <div className="topbar-actions">
            <button type="button">Search</button>
            <button type="button">Help</button>
            <button type="button">Dark Mode</button>
          </div>
        </header>

        {page === 'admin' ? (
          <main className="content">
            <section className="page-heading">
              <div>
                <p className="eyebrow">ADMINISTRATION</p>
                <h1>Admin Console</h1>
                <p>These buttons establish the complete Admin Console foundation. Features remain visible even before their backend functionality is connected.</p>
              </div>
              <div className="sync-card">
                <span>GM OnTrac status</span>
                <strong>Not yet synced</strong>
                <small>In-Service List and Expiring Plates required</small>
              </div>
            </section>

            <section className="feature-grid" aria-label="Admin Console features">
              {adminFeatures.map((feature) => (
                <button className="feature-card" type="button" key={feature.title} onClick={() => openFeature(feature.title)}>
                  <span className={`status ${feature.status.toLowerCase().replace(' ', '-')}`}>{feature.status}</span>
                  <strong>{feature.title}</strong>
                  <span className="feature-description">{feature.description}</span>
                  <span className="open-label">Open section</span>
                </button>
              ))}
            </section>
          </main>
        ) : (
          <main className="content fleet-page">
            <section className="fleet-header">
              <div>
                <p className="eyebrow">ADMINISTRATION / FLEET</p>
                <h1>Fleet Administration</h1>
                <p>Live vehicle records from the Admin vehicle master view.</p>
              </div>
              <div className="page-actions">
                <button type="button" className="secondary-action" onClick={() => setPage('admin')}>Back to Admin Console</button>
                <button type="button" className="primary-action">Add Vehicle</button>
              </div>
            </section>

            <section className="status-grid" aria-label="Fleet status summary">
              {statusCards.map(([label, value]) => (
                <div className="metric-card" key={label}>
                  <span>{label}</span>
                  <strong>{value}</strong>
                </div>
              ))}
            </section>

            <section className="filter-panel">
              <div className="search-field">
                <label htmlFor="vehicle-search">Search fleet</label>
                <input id="vehicle-search" type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="VIN, last 8, plate, stock number, model, or trim" />
              </div>
              <div className="filter-row">
                {fleetFilters.map((item) => (
                  <button type="button" className={`filter ${filter === item ? 'active' : ''}`} onClick={() => setFilter(item)} key={item}>{item}</button>
                ))}
              </div>
            </section>

            {loadError && <div className="data-message error-message"><strong>Fleet data could not load.</strong><span>{loadError}</span></div>}

            <section className="fleet-layout">
              <div className="vehicle-table-card">
                <div className="section-heading">
                  <div>
                    <h2>Fleet Vehicles</h2>
                    <p>{loading ? 'Loading vehicles…' : `${filteredVehicles.length} of ${vehicles.length} vehicles shown`}</p>
                  </div>
                </div>
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Vehicle</th>
                        <th>VIN Last 8</th>
                        <th>Plate</th>
                        <th>Fleet Type</th>
                        <th>Status</th>
                        <th>Odometer</th>
                        <th>Days In Service</th>
                        <th>Source</th>
                      </tr>
                    </thead>
                    <tbody>
                      {!loading && filteredVehicles.map((vehicle) => (
                        <tr className={selectedVehicleId === vehicle.vehicle_id ? 'selected-row' : ''} onClick={() => setSelectedVehicleId(vehicle.vehicle_id)} key={vehicle.vehicle_id}>
                          <td>{[vehicle.model_year, vehicle.model, vehicle.trim].filter(Boolean).join(' ') || 'Unnamed vehicle'}</td>
                          <td>{vehicle.vin_last8}</td>
                          <td>{vehicle.license_plate || '—'}</td>
                          <td>{vehicle.fleet_type || '—'}</td>
                          <td>{vehicle.is_retired ? 'Retired' : vehicle.vehicle_status || '—'}</td>
                          <td>{formatNumber(vehicle.odometer)}</td>
                          <td>{formatNumber(vehicle.ontrac_days_in_service)}</td>
                          <td>{vehicle.record_source || '—'}</td>
                        </tr>
                      ))}
                      {!loading && !loadError && filteredVehicles.length === 0 && (
                        <tr className="empty-row"><td colSpan={8}>No vehicles match the current search and filter.</td></tr>
                      )}
                      {loading && <tr className="empty-row"><td colSpan={8}>Loading fleet vehicles…</td></tr>}
                    </tbody>
                  </table>
                </div>
              </div>

              <aside className="details-panel">
                <div className="section-heading compact">
                  <div>
                    <h2>Vehicle Details</h2>
                    <p>{selectedVehicle ? selectedVehicle.vin_last8 : 'Select a vehicle to review its information.'}</p>
                  </div>
                </div>
                {selectedVehicle ? (
                  <dl className="vehicle-details-list">
                    <div><dt>Vehicle</dt><dd>{[selectedVehicle.model_year, selectedVehicle.model, selectedVehicle.trim].filter(Boolean).join(' ') || '—'}</dd></div>
                    <div><dt>VIN</dt><dd>{selectedVehicle.vin || `Last 8: ${selectedVehicle.vin_last8}`}</dd></div>
                    <div><dt>Stock Number</dt><dd>{selectedVehicle.stock_number || '—'}</dd></div>
                    <div><dt>Plate</dt><dd>{selectedVehicle.license_plate || '—'}</dd></div>
                    <div><dt>Plate Expiration</dt><dd>{formatDate(selectedVehicle.plate_expiration_date)}</dd></div>
                    <div><dt>Fleet Type</dt><dd>{selectedVehicle.fleet_type || '—'}</dd></div>
                    <div><dt>Status</dt><dd>{selectedVehicle.is_retired ? 'Retired' : selectedVehicle.vehicle_status || '—'}</dd></div>
                    <div><dt>Odometer</dt><dd>{formatNumber(selectedVehicle.odometer)}</dd></div>
                    <div><dt>Qualified Miles</dt><dd>{formatNumber(selectedVehicle.qualified_miles)}</dd></div>
                    <div><dt>Days In Service</dt><dd>{formatNumber(selectedVehicle.ontrac_days_in_service)}</dd></div>
                    <div><dt>CTP</dt><dd>{selectedVehicle.ctp_program_active ? 'Active' : 'Inactive'}</dd></div>
                    <div><dt>Record Source</dt><dd>{selectedVehicle.record_source || '—'}</dd></div>
                    <div><dt>Last OnTrac Seen</dt><dd>{formatDate(selectedVehicle.ontrac_last_seen_at)}</dd></div>
                    <div><dt>Location</dt><dd>{selectedVehicle.location || '—'}</dd></div>
                  </dl>
                ) : <div className="detail-placeholder">No vehicle selected</div>}
                <div className="details-actions">
                  <button type="button" disabled={!selectedVehicle}>Edit Vehicle</button>
                  <button type="button" disabled={!selectedVehicle || selectedVehicle.is_retired}>Retire Vehicle</button>
                  <button type="button" disabled={!selectedVehicle || !selectedVehicle.is_retired}>Reactivate Vehicle</button>
                  <button type="button" disabled={!selectedVehicle}>View History</button>
                </div>
              </aside>
            </section>

            <section className="history-card">
              <div className="section-heading compact">
                <div>
                  <h2>Vehicle History</h2>
                  <p>Plate, stock number, status, retirement, import, and administrative history will appear here.</p>
                </div>
              </div>
              <div className="history-placeholder">{selectedVehicle ? `History connection pending for VIN ${selectedVehicle.vin_last8}.` : 'Select a vehicle to view history.'}</div>
            </section>
          </main>
        )}
      </div>
    </div>
  )
}

export default App
