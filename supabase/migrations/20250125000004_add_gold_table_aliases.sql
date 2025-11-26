-- ============================================================================
-- Migration: 20250125000004_add_gold_table_aliases.sql
-- Purpose: Create views to alias vehicles_v2 → vehicles and real_property_v2 → real_estate
-- Dependencies: 20250125000002_complete_medallion_schema.sql
-- ============================================================================
-- This creates views so validation scripts and code can use the expected table names
-- while the actual tables use the v2 naming convention
-- ============================================================================

-- Create view for vehicles (aliases vehicles_v2)
CREATE OR REPLACE VIEW vehicles AS
SELECT 
    id,
    case_id,
    vehicle_type,
    year,
    make,
    model,
    vin,
    current_value,
    mileage,
    loan_balance,
    monthly_payment,
    final_payment_date,
    primary_use,
    business_use_percentage,
    equity,
    created_at,
    updated_at
FROM vehicles_v2;

-- Create view for real_estate (aliases real_property_v2)
CREATE OR REPLACE VIEW real_estate AS
SELECT 
    id,
    case_id,
    property_type,
    address,
    city,
    county,
    state,
    zip_code,
    current_market_value,
    purchase_date,
    purchase_price,
    mortgage_balance,
    monthly_payment,
    loan_interest_rate,
    final_payment_date,
    rental_income_monthly,
    rental_expenses_monthly,
    net_rental_income_monthly,
    equity,
    created_at,
    updated_at
FROM real_property_v2;

-- Add comments
COMMENT ON VIEW vehicles IS 'View aliasing vehicles_v2 for backward compatibility';
COMMENT ON VIEW real_estate IS 'View aliasing real_property_v2 for backward compatibility';

