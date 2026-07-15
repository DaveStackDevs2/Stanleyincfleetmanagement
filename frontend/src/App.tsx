import { useEffect, useMemo, useState } from 'react'
import './App.css'

type AdminFeature = {
  title: string
  description: string
  status: 'Foundation' | 'Planned' | 'Coming Soon'
}

type Page = 'admin' | 'fleet'
type FleetFilter = 'All' | 'Active' | 'Retired' | 'Loaner' | 'Rental' | 'Available' | 'Out' | 'Maintenance'

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
  ontrac_last_seen_at: string