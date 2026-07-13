import './App.css'

type AdminFeature = {
  title: string
  description: string
  status: 'Foundation' | 'Planned' | 'Coming Soon'
}

const adminFeatures: AdminFeature[] = [
  {
    title: 'Fleet Administration',
    description: 'View, search, add, edit, retire, reactivate, and review every fleet vehicle.',
    status: 'Foundation',
  },
  {
    title: 'GM OnTrac Sync Center',
    description: 'Upload In-Service and Expiring Plates reports, preview changes, review errors, and maintain import history.',
    status: 'Foundation',
  },
  {
    title: 'CTP Threshold Settings',
    description: 'Manage preferred and absolute day and odometer limits for CTP vehicles.',
    status: 'Foundation',
  },
  {
    title: 'Retirement Review',
    description: 'Review vehicles missing from OnTrac and approve retirement with an effective date and reason.',
    status: 'Planned',
  },
  {
    title: 'Plate Administration',
    description: 'Assign plates, track expiration dates, review plate changes, and preserve plate history.',
    status: 'Planned',
  },
  {
    title: 'Vehicle Import Review',
    description: 'Review new vehicles, unmatched VINs, manual entries, duplicate candidates, and failed rows.',
    status: 'Planned',
  },
  {
    title: 'Users & Permissions',
    description: 'Manage users, roles, access levels, account status, and Admin permissions.',
    status: 'Planned',
  },
  {
    title: 'Locations & Fleet Types',
    description: 'Manage dealership locations, vehicle classifications, and fleet-use categories.',
    status: 'Planned',
  },
  {
    title: 'Rates, Fees & Billing Rules',
    description: 'Manage rental rates, pay types, taxes, late-fee rules, and billing defaults.',
    status: 'Planned',
  },
  {
    title: 'Notifications',
    description: 'Manage alert rules, recipients, severity, delivery channels, and cooldown periods.',
    status: 'Planned',
  },
  {
    title: 'Audit & Activity History',
    description: 'Review administrative changes, vehicle history, imports, approvals, and user activity.',
    status: 'Planned',
  },
  {
    title: 'System Settings',
    description: 'Manage dealership-wide defaults, integrations, security settings, and operational rules.',
    status: 'Planned',
  },
  {
    title: 'Reports & Exports',
    description: 'Run fleet, CTP, utilization, plate, retirement, rental, and exception reports.',
    status: 'Planned',
  },
  {
    title: 'QR Code Administration',
    description: 'Create and manage vehicle and workflow QR codes.',
    status: 'Coming Soon',
  },
]

function App() {
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
          <button type="button">Fleet</button>
          <button type="button" className="active">Admin Console</button>
          <button type="button">Reports</button>
        </nav>
      </aside>

      <div className="workspace">
        <header className="topbar">
          <div>
            <strong>Admin Console</strong>
            <span>Foundation and planned controls</span>
          </div>
          <div className="topbar-actions">
            <button type="button">Search</button>
            <button type="button">Help</button>
            <button type="button">Dark Mode</button>
          </div>
        </header>

        <main className="content">
          <section className="page-heading">
            <div>
              <p className="eyebrow">ADMINISTRATION</p>
              <h1>Admin Console</h1>
              <p>
                These buttons establish the complete Admin Console foundation. Features remain visible even before their backend functionality is connected.
              </p>
            </div>
            <div className="sync-card">
              <span>GM OnTrac status</span>
              <strong>Not yet synced</strong>
              <small>In-Service List and Expiring Plates required</small>
            </div>
          </section>

          <section className="feature-grid" aria-label="Admin Console features">
            {adminFeatures.map((feature) => (
              <button className="feature-card" type="button" key={feature.title}>
                <span className={`status ${feature.status.toLowerCase().replace(' ', '-')}`}>
                  {feature.status}
                </span>
                <strong>{feature.title}</strong>
                <span className="feature-description">{feature.description}</span>
                <span className="open-label">Open section</span>
              </button>
            ))}
          </section>
        </main>
      </div>
    </div>
  )
}

export default App
