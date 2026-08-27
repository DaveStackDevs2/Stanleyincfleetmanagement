from pathlib import Path


def test_billing_workspace_accepts_rental_block_pricing_preview_field():
    source = Path("frontend/src/billing/BillingWorkspace.tsx").read_text()

    assert "rental_block_pricing: Record<string, unknown> | null" in source
    assert "'rate_source','rental_block_pricing','subtotal'" in source
    assert "v.rental_block_pricing===null||isObject(v.rental_block_pricing)" in source
