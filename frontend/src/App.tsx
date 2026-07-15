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
