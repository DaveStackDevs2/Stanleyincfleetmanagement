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
  { title: 'Vehicle Import Review', description: 'Review new vehicles, unmatched VINs, manual entries, duplicate candidates, and failed rows