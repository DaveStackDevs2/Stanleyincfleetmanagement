import { useState } from 'react'
import './App.css'

type AdminFeature = {
  title: string
  description: string
  status: 'Foundation' | 'Planned' | 'Coming Soon'
}

type Page = 'admin' | 'fleet'

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

const statusCards = [
  ['Total Fleet', '—'],
  ['Available', '—'],
  ['Out', '—'],
  ['CTP', '—'],
  ['Over Preferred', '—'],
  ['Over Maximum', '—'],
]

function App() {
  const [page, setPage] = useState<Page>('admin')

  const openFeature = (title: string) => {
    if (title === 'Fleet Administration') setPage('fleet')
  }

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
            <span>{page === 'fleet' ? 'Frontend shell — no backend actions connected' : 'Foundation and planned controls'}</span>
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
                <p>Vehicle management shell. Data, filters, details, and actions are placeholders until backend connections are added.</p>
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
                <input id="vehicle-search" type="search" placeholder="VIN, last 8, plate, or stock number" />
              </div>
              <div className="filter-row">
                <button type="button" className="filter active">All</button>
                <button type="button" className="filter">Active</button>
                <button type="button" className="filter">Retired</button>
                <button type="button" className="filter">CTP</button>
                <button type="button" className="filter">Loaner</button>
                <button type="button" className="filter">Rental</button>
                <button type="button" className="filter">Available</button>
                <button type="button" className="filter">Out</button>
                <button type="button" className="filter">Maintenance</button>
              </div>
            </section>

            <section className="fleet-layout">
              <div className="vehicle-table-card">
                <div className="section-heading">
                  <div>
                    <h2>Fleet Vehicles</h2>
                    <p>Vehicle records will appear here after the backend is connected.</p>
                  </div>
                  <button type="button" className="secondary-action">Columns</button>
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
                      <tr className="empty-row">
                        <td colSpan={8}>No vehicle data connected yet.</td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>

              <aside className="details-panel">
                <div className="section-heading compact">
                  <div>
                    <h2>Vehicle Details</h2>
                    <p>Select a vehicle to review its information.</p>
                  </div>
                </div>
                <div className="detail-placeholder">No vehicle selected</div>
                <div className="details-actions">
                  <button type="button" disabled>Edit Vehicle</button>
                  <button type="button" disabled>Retire Vehicle</button>
                  <button type="button" disabled>Reactivate Vehicle</button>
                  <button type="button" disabled>View History</button>
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
              <div className="history-placeholder">Select a vehicle to view history.</div>
            </section>
          </main>
        )}
      </div>
    </div>
  )
}

export default App
