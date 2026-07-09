# Dashboard Payload Structures

Date: 2026-07-09

## get_dashboard_payload_state

```json
{
  "status": "...",
  "dashboard_access": {
    "view_dashboard_warning_center": "...",
    "view_dashboard_upcoming_rentals": "...",
    "view_dashboard_lost_rentals": "...",
    "view_dashboard_utilization": "...",
    "view_dashboard_warranty": "...",
    "view_dashboard_conflicts": "...",
    "view_dashboard_ai": "..."
  },
  "payload": {
    "warning_center_counts": {
      "status": "...",
      "critical_count": "...",
      "warning_count": "...",
      "review_count": "..."
    },
    "warning_center_detail": {
      "status": "...",
      "critical": [
        {
          "item_type": "...",
          "source_id": "...",
          "reservation_id": "...",
          "vehicle_id": "...",
          "risk_level": "...",
          "source_status": "...",
          "expected_return_snapshot": "...",
          "contract_period_id": "...",
          "reminder_state": "...",
          "message": "..."
        }
      ],
      "warning": [
        {
          "item_type": "...",
          "source_id": "...",
          "reservation_id": "...",
          "vehicle_id": "...",
          "risk_level": "...",
          "source_status": "...",
          "expected_return_snapshot": "...",
          "contract_period_id": "...",
          "reminder_state": "...",
          "message": "..."
        }
      ],
      "review_needed": [
        {
          "item_type": "...",
          "source_id": "...",
          "reservation_id": "...",
          "vehicle_id": "...",
          "risk_level": "...",
          "source_status": "...",
          "expected_return_snapshot": "...",
          "contract_period_id": "...",
          "reminder_state": "...",
          "message": "..."
        }
      ]
    },
    "upcoming_rental_dependencies": {
      "status": "...",
      "items": [
        {
          "dependency_id": "...",
          "reservation_id": "...",
          "reservation_start_at": "...",
          "reservation_end_at": "...",
          "requested_model": "...",
          "reservation_type": "...",
          "reservation_status": "...",
          "reservation_notes": "...",
          "vehicle_id": "...",
          "source_transportation_event_id": "...",
          "dependency_type": "...",
          "dependency_status": "...",
          "risk_level": "...",
          "expected_return_snapshot": "...",
          "conflict_id": "...",
          "conflict_type": "...",
          "conflict_severity": "...",
          "conflict_message": "..."
        }
      ]
    },
    "lost_rentals_summary": {
      "status": "...",
      "lost_rental_count": "...",
      "total_requested_days": "...",
      "total_estimated_revenue": "..."
    },
    "utilization_snapshot": {
      "status": "...",
      "total_vehicles": "...",
      "vehicles_out": "...",
      "vehicles_available": "..."
    },
    "warranty_section": {
      "status": "..."
    },
    "conflict_section": {
      "status": "..."
    },
    "ai_section": {
      "status": "..."
    }
  }
}
```

## get_master_operational_dashboard_state

```json
{
  "status": "...",
  "counts": {
    "status": "...",
    "customer_count": "...",
    "vehicle_count": "...",
    "reservation_count": "...",
    "transportation_event_count": "...",
    "open_vehicle_event_count": "...",
    "open_contract_period_count": "...",
    "open_billing_line_count": "...",
    "unresolved_dependency_count": "...",
    "unresolved_conflict_count": "...",
    "transportation_event_note_count": "..."
  },
  "customers": {
    "status": "...",
    "items": [
      {
        "customer_id": "...",
        "created_at": "...",
        "tekion_customer_number": "...",
        "name": "...",
        "phone": "...",
        "email": "...",
        "flags": "...",
        "internal_notes": "...",
        "reservation_count": "...",
        "non_cancelled_reservation_count": "...",
        "transportation_event_count": "...",
        "active_transportation_event_count": "...",
        "open_vehicle_continuity_count": "...",
        "latest_expected_return_at": "..."
      }
    ]
  },
  "vehicles": {
    "status": "...",
    "items": [
      {
        "vehicle_id": "...",
        "created_at": "...",
        "vin": "...",
        "stock_number": "...",
        "model": "...",
        "fleet_type": "...",
        "vehicle_status": "...",
        "mileage": "...",
        "recon_status": "...",
        "current_tag": "...",
        "fleet_conversion_type": "...",
        "location": "...",
        "notes": "...",
        "active_transportation_event_id": "...",
        "vehicle_event_id": "...",
        "contract_period_id": "...",
        "actual_out_at": "...",
        "contract_out_at": "...",
        "renewal_sequence": "...",
        "vehicle_event_is_open": "...",
        "contract_period_is_open": "...",
        "latest_expected_return_at": "...",
        "assigned_reservation_count": "...",
        "candidate_reservation_count": "...",
        "unresolved_dependency_count": "...",
        "unresolved_conflict_count": "..."
      }
    ]
  },
  "reservations": {
    "status": "...",
    "items": [
      {
        "reservation_id": "...",
        "transportation_event_id": "...",
        "vehicle_id": "...",
        "start_date": "...",
        "expected_return_datetime": "...",
        "reservation_status": "...",
        "reservation_type": "...",
        "reservation_notes": "...",
        "cancellation_reason": "...",
        "start_mileage": "...",
        "end_mileage": "...",
        "condition_flag": "...",
        "requested_model": "...",
        "service_advisor": "...",
        "ro_number": "...",
        "pay_type": "...",
        "actual_return_datetime": "...",
        "billed_through_datetime": "...",
        "customer_id": "...",
        "source_type": "...",
        "source_id": "...",
        "transportation_event_status": "...",
        "transportation_event_notes": "...",
        "expected_return_at": "...",
        "closed_at": "...",
        "closed_by": "...",
        "vin_lock_lead_days": "...",
        "lock_window_starts_at": "...",
        "is_in_lock_window": "...",
        "vehicle_is_assigned": "...",
        "current_dependency_id": "...",
        "current_dependency_type": "...",
        "current_dependency_status": "...",
        "current_dependency_risk_level": "...",
        "current_dependency_expected_return_snapshot": "...",
        "current_conflict_id": "...",
        "current_conflict_severity": "...",
        "current_conflict_message": "..."
      }
    ]
  },
  "transportation_events": {
    "status": "...",
    "items": [
      {
        "transportation_event_id": "...",
        "source_type": "...",
        "source_id": "...",
        "transportation_event_status": "...",
        "transportation_event_notes": "...",
        "customer_id": "...",
        "updated_at": "...",
        "closed_at": "...",
        "closed_by": "...",
        "expected_return_at": "...",
        "vehicle_event_id": "...",
        "vehicle_id": "...",
        "contract_period_id": "...",
        "actual_out_at": "...",
        "actual_in_at": "...",
        "vehicle_event_is_open": "...",
        "ended_reason": "...",
        "contract_out_at": "...",
        "contract_in_at": "...",
        "renewal_sequence": "...",
        "contract_period_is_open": "...",
        "current_parent_billing_line_id": "...",
        "current_billing_reservation_id": "...",
        "current_billing_vehicle_id": "...",
        "current_billing_pay_type": "...",
        "current_billing_parent_amount": "...",
        "current_billing_parent_tax_amount": "...",
        "current_billing_start_time": "...",
        "current_billing_end_time": "...",
        "current_billing_line_type": "...",
        "current_billing_paid_through_at": "...",
        "current_billing_is_open": "...",
        "current_dependency_id": "...",
        "current_dependency_reservation_id": "...",
        "current_dependency_vehicle_id": "...",
        "current_dependency_source_transportation_event_id": "...",
        "current_dependency_type": "...",
        "current_dependency_status": "...",
        "current_dependency_risk_level": "...",
        "current_dependency_expected_return_snapshot": "...",
        "current_conflict_id": "...",
        "current_conflict_type": "...",
        "current_conflict_severity": "...",
        "current_conflict_message": "...",
        "current_conflict_is_resolved": "...",
        "extension_candidate_parent_billing_line_id": "...",
        "extension_candidate_reservation_id": "...",
        "extension_candidate_billing_vehicle_id": "...",
        "extension_candidate_pay_type": "...",
        "extension_candidate_amount": "...",
        "extension_candidate_tax_amount": "...",
        "extension_candidate_start_time": "...",
        "extension_candidate_paid_through_at": "...",
        "extension_candidate_is_open": "...",
        "extension_candidate_current_expected_return_at": "..."
      }
    ]
  },
  "case_candidates": {
    "status": "...",
    "activation": {
      "status": "...",
      "items": [
        {
          "reservation_id": "...",
          "transportation_event_id": "...",
          "reservation_vehicle_id": "...",
          "start_date": "...",
          "expected_return_datetime": "...",
          "reservation_status": "...",
          "reservation_type": "...",
          "requested_model": "...",
          "reservation_pay_type": "...",
          "customer_id": "...",
          "current_vehicle_event_id": "...",
          "current_continuity_vehicle_id": "...",
          "current_contract_period_id": "...",
          "actual_out_at": "...",
          "contract_out_at": "...",
          "vehicle_event_is_open": "...",
          "contract_period_is_open": "...",
          "parent_billing_line_id": "...",
          "billing_pay_type": "...",
          "parent_amount": "...",
          "parent_tax_amount": "...",
          "billing_start_time": "...",
          "billing_end_time": "...",
          "paid_through_at": "...",
          "billing_is_open": "...",
          "has_active_continuity": "...",
          "has_open_billing_line": "..."
        }
      ]
    },
    "continuation": {
      "status": "...",
      "items": [
        {
          "reservation_id": "...",
          "transportation_event_id": "...",
          "reservation_vehicle_id": "...",
          "start_date": "...",
          "expected_return_datetime": "...",
          "reservation_status": "...",
          "reservation_type": "...",
          "requested_model": "...",
          "customer_id": "...",
          "actual_return_datetime": "...",
          "billed_through_datetime": "...",
          "current_vehicle_event_id": "...",
          "current_continuity_vehicle_id": "...",
          "current_contract_period_id": "...",
          "actual_out_at": "...",
          "actual_in_at": "...",
          "contract_out_at": "...",
          "contract_in_at": "...",
          "renewal_sequence": "...",
          "vehicle_event_is_open": "...",
          "contract_period_is_open": "...",
          "reservation_has_assigned_vehicle": "...",
          "has_active_continuity": "..."
        }
      ]
    },
    "reassignment": {
      "status": "...",
      "items": [
        {
          "reservation_id": "...",
          "transportation_event_id": "...",
          "reservation_vehicle_id": "...",
          "start_date": "...",
          "expected_return_datetime": "...",
          "reservation_status": "...",
          "reservation_type": "...",
          "requested_model": "...",
          "customer_id": "...",
          "current_vehicle_event_id": "...",
          "current_continuity_vehicle_id": "...",
          "current_contract_period_id": "...",
          "actual_out_at": "...",
          "contract_out_at": "...",
          "vehicle_event_is_open": "...",
          "contract_period_is_open": "...",
          "current_dependency_id": "...",
          "current_dependency_type": "...",
          "current_dependency_status": "...",
          "current_dependency_risk_level": "...",
          "current_dependency_expected_return_snapshot": "...",
          "has_active_continuity": "...",
          "reservation_has_assigned_vehicle": "..."
        }
      ]
    },
    "completion": {
      "status": "...",
      "items": [
        {
          "reservation_id": "...",
          "transportation_event_id": "...",
          "reservation_vehicle_id": "...",
          "start_date": "...",
          "expected_return_datetime": "...",
          "reservation_status": "...",
          "reservation_type": "...",
          "reservation_notes": "...",
          "actual_return_datetime": "...",
          "billed_through_datetime": "...",
          "customer_id": "...",
          "transportation_event_status": "...",
          "expected_return_at": "...",
          "closed_at": "...",
          "closed_by": "...",
          "vehicle_event_id": "...",
          "contract_period_id": "...",
          "actual_out_at": "...",
          "actual_in_at": "...",
          "vehicle_event_is_open": "...",
          "contract_period_is_open": "...",
          "parent_billing_line_id": "...",
          "billing_start_time": "...",
          "billing_end_time": "...",
          "paid_through_at": "...",
          "billing_is_open": "...",
          "has_active_continuity": "...",
          "has_open_billing_line": "..."
        }
      ]
    }
  }
}
```
