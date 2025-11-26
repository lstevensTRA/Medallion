-- ============================================================================
-- Migration: 20250125000002_complete_medallion_schema.sql
-- Purpose: Complete Medallion Architecture Schema (Bronze → Silver → Gold)
-- Based on: User-provided Gold schema with best practices
-- ============================================================================
-- This migration:
-- 1. Ensures Bronze tables exist (already created)
-- 2. Creates/updates Silver tables with bronze_id lineage
-- 3. Creates all Gold tables from provided schema
-- 4. Creates Bronze → Silver triggers
-- 5. Creates Silver → Gold triggers
-- ============================================================================

-- ============================================================================
-- PART 1: ENSURE CORE ENTITIES EXIST
-- ============================================================================

-- Clients table
CREATE TABLE IF NOT EXISTS clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    primary_taxpayer_ssn TEXT NOT NULL UNIQUE,
    primary_taxpayer_name TEXT NOT NULL,
    spouse_ssn TEXT,
    spouse_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Cases table (maps external case_id TEXT to internal UUID)
CREATE TABLE IF NOT EXISTS cases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_number TEXT NOT NULL UNIQUE,
    client_id UUID REFERENCES clients(id) ON DELETE CASCADE,
    status_code TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    opening_investigator TEXT,
    ti_completed_date DATE,
    resolution_plan_completed_by TEXT,
    resolution_plan_completed_date DATE,
    settlement_officer TEXT,
    tra_code TEXT
);

CREATE INDEX IF NOT EXISTS idx_cases_case_number ON cases(case_number);

-- ============================================================================
-- PART 2: SILVER LAYER (with bronze_id for lineage)
-- ============================================================================

-- Tax Years (Silver)
CREATE TABLE IF NOT EXISTS tax_years (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    year INTEGER NOT NULL,
    filing_status TEXT,
    return_filed BOOLEAN DEFAULT FALSE,
    return_filed_date DATE,
    base_csed_date DATE,
    calculated_agi NUMERIC,
    calculated_tax_liability NUMERIC,
    calculated_account_balance NUMERIC,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    reason TEXT,
    status TEXT,
    levy_status TEXT,
    lien_filed BOOLEAN DEFAULT FALSE,
    projected_balance NUMERIC DEFAULT 0,
    exam_aur_analysis BOOLEAN DEFAULT FALSE,
    aur_projected NUMERIC DEFAULT 0,
    notes TEXT,
    owner TEXT CHECK (owner = ANY (ARRAY['E'::text, 'P'::text])),
    source_file TEXT,
    taxable_income NUMERIC,
    tax_per_return NUMERIC,
    accrued_interest NUMERIC DEFAULT 0,
    accrued_penalty NUMERIC DEFAULT 0,
    -- Lineage tracking
    bronze_id UUID,  -- Links back to Bronze source
    UNIQUE(case_id, year)
);

CREATE INDEX IF NOT EXISTS idx_tax_years_case_id ON tax_years(case_id);
CREATE INDEX IF NOT EXISTS idx_tax_years_bronze_id ON tax_years(bronze_id);

-- Account Activity (Silver)
CREATE TABLE IF NOT EXISTS account_activity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tax_year_id UUID REFERENCES tax_years(id) ON DELETE CASCADE,
    activity_date DATE NOT NULL,
    irs_transaction_code TEXT NOT NULL,
    explanation TEXT,
    amount NUMERIC,
    calculated_transaction_type TEXT,
    affects_balance BOOLEAN DEFAULT FALSE,
    affects_csed BOOLEAN DEFAULT FALSE,
    indicates_collection_action BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    -- Lineage tracking
    bronze_id UUID  -- Links back to Bronze source
);

CREATE INDEX IF NOT EXISTS idx_account_activity_tax_year_id ON account_activity(tax_year_id);
CREATE INDEX IF NOT EXISTS idx_account_activity_bronze_id ON account_activity(bronze_id);
CREATE INDEX IF NOT EXISTS idx_account_activity_code ON account_activity(irs_transaction_code);

-- Income Documents (Silver)
CREATE TABLE IF NOT EXISTS income_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tax_year_id UUID REFERENCES tax_years(id) ON DELETE CASCADE,
    document_type TEXT NOT NULL,
    gross_amount NUMERIC DEFAULT 0,
    federal_withholding NUMERIC DEFAULT 0,
    calculated_category TEXT,
    is_self_employment BOOLEAN DEFAULT FALSE,
    include_in_projection BOOLEAN DEFAULT TRUE,
    fields JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    issuer_id TEXT,
    issuer_name TEXT,
    issuer_address TEXT,
    recipient_id TEXT,
    recipient_name TEXT,
    recipient_address TEXT,
    combined_income NUMERIC,
    -- Lineage tracking
    bronze_id UUID  -- Links back to Bronze source
);

CREATE INDEX IF NOT EXISTS idx_income_documents_tax_year_id ON income_documents(tax_year_id);
CREATE INDEX IF NOT EXISTS idx_income_documents_bronze_id ON income_documents(bronze_id);
CREATE INDEX IF NOT EXISTS idx_income_documents_doc_type ON income_documents(document_type);

-- TRT Records (Silver)
CREATE TABLE IF NOT EXISTS trt_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    tax_year_id UUID REFERENCES tax_years(id) ON DELETE CASCADE,
    response_date DATE,
    form_number TEXT,
    tax_period_ending DATE,
    primary_ssn TEXT,
    spouse_ssn TEXT,
    type TEXT,
    category TEXT,
    sub_category TEXT,
    data TEXT,
    numeric_value NUMERIC,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    -- Lineage tracking
    bronze_id UUID  -- Links back to Bronze source
);

CREATE INDEX IF NOT EXISTS idx_trt_records_case_id ON trt_records(case_id);
CREATE INDEX IF NOT EXISTS idx_trt_records_tax_year_id ON trt_records(tax_year_id);
CREATE INDEX IF NOT EXISTS idx_trt_records_bronze_id ON trt_records(bronze_id);

-- Logiqs Raw Data (Silver - Interview data)
CREATE TABLE IF NOT EXISTS logiqs_raw_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID UNIQUE REFERENCES cases(id) ON DELETE CASCADE,
    -- Excel cell references (for TI Excel compatibility)
    c61 TEXT, c76 TEXT, c80 TEXT,
    b79 TEXT, b87 TEXT, b88 TEXT, b90 TEXT,
    al4 TEXT, al5 TEXT, al7 NUMERIC, al8 NUMERIC,
    ak7 NUMERIC, ak8 NUMERIC,
    b3 TEXT, b4 DATE, b5 NUMERIC, b6 NUMERIC, b7 TEXT,
    c3 TEXT, c4 DATE, c5 NUMERIC, c6 NUMERIC, c7 TEXT,
    b10 TEXT, b11 TEXT, b12 TEXT, b13 TEXT, b14 TEXT,
    c10 TEXT, c11 TEXT, c12 TEXT, c13 TEXT, c14 TEXT,
    b18 NUMERIC, b19 NUMERIC, b20 NUMERIC, b21 NUMERIC, b22 NUMERIC,
    b23 NUMERIC, b24 NUMERIC, b25 NUMERIC, b26 NUMERIC, b27 NUMERIC,
    b28 NUMERIC, b29 NUMERIC,
    d20 NUMERIC, d21 NUMERIC, d22 NUMERIC, d23 NUMERIC, d24 NUMERIC,
    d25 NUMERIC, d26 NUMERIC, d27 NUMERIC, d28 NUMERIC, d29 NUMERIC,
    b33 NUMERIC, b34 NUMERIC, b35 NUMERIC, b36 NUMERIC, b37 NUMERIC,
    b38 NUMERIC, b39 NUMERIC, b40 NUMERIC, b41 NUMERIC, b42 NUMERIC,
    b43 NUMERIC, b44 NUMERIC, b45 NUMERIC, b46 NUMERIC, b47 NUMERIC,
    b50 TEXT, b51 TEXT, b52 TEXT, b53 TEXT,
    b56 NUMERIC, b57 NUMERIC, b58 NUMERIC, b59 NUMERIC, b60 NUMERIC,
    b64 NUMERIC, b65 NUMERIC, b66 NUMERIC, b67 NUMERIC, b68 NUMERIC,
    b69 NUMERIC, b70 NUMERIC, b71 NUMERIC, b72 NUMERIC, b73 NUMERIC,
    b74 NUMERIC, b75 NUMERIC,
    b80 NUMERIC, b81 NUMERIC, b84 NUMERIC, b89 NUMERIC,
    ak2 TEXT, ak4 NUMERIC, ak5 NUMERIC, ak6 NUMERIC,
    c56 NUMERIC, c57 NUMERIC, c58 NUMERIC, c59 NUMERIC, c60 NUMERIC,
    c61_irs NUMERIC, al6 NUMERIC,
    -- Structured JSONB (for flexibility)
    raw_response JSONB,
    employment JSONB,
    household JSONB,
    assets JSONB,
    income JSONB,
    expenses JSONB,
    irs_standards JSONB,
    extracted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    -- Lineage tracking
    bronze_id UUID  -- Links back to Bronze source
);

CREATE INDEX IF NOT EXISTS idx_logiqs_case_id ON logiqs_raw_data(case_id);
CREATE INDEX IF NOT EXISTS idx_logiqs_bronze_id ON logiqs_raw_data(bronze_id);

-- ============================================================================
-- PART 3: GOLD LAYER (Normalized Business Entities)
-- ============================================================================

-- Employment Information (Gold)
CREATE TABLE IF NOT EXISTS employment_information (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    person_type TEXT NOT NULL CHECK (person_type = ANY (ARRAY['taxpayer'::text, 'spouse'::text])),
    employer_name TEXT,
    employer_address TEXT,
    job_title TEXT,
    employment_start_date DATE,
    employment_end_date DATE,
    pay_frequency TEXT CHECK (pay_frequency = ANY (ARRAY['weekly'::text, 'biweekly'::text, 'semimonthly'::text, 'monthly'::text, 'quarterly'::text, 'annual'::text])),
    gross_monthly_income NUMERIC,
    net_monthly_income NUMERIC,
    gross_annual_income NUMERIC,
    net_annual_income NUMERIC,
    is_self_employed BOOLEAN DEFAULT FALSE,
    self_employment_tax_rate NUMERIC DEFAULT 0.0765,
    excel_reference_map JSONB,  -- Maps to Excel cells (b3, c3, etc.)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_employment_case_id ON employment_information(case_id);

-- Household Information (Gold)
CREATE TABLE IF NOT EXISTS household_information (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID UNIQUE REFERENCES cases(id) ON DELETE CASCADE,
    total_household_members INTEGER DEFAULT 1,
    members_under_65 INTEGER DEFAULT 0,
    members_over_65 INTEGER DEFAULT 0,
    taxpayer_next_tax_return TEXT,
    taxpayer_spouse_claim TEXT,
    spouse_next_tax_return TEXT,
    spouse_spouse_claim TEXT,
    taxpayer_length_of_residency TEXT,
    taxpayer_occupancy_status TEXT,
    spouse_length_of_residency TEXT,
    spouse_occupancy_status TEXT,
    state TEXT,
    county TEXT,
    zip_code TEXT,
    excel_reference_map JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_household_case_id ON household_information(case_id);

-- Household Members (Gold)
CREATE TABLE IF NOT EXISTS household_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    relationship TEXT NOT NULL CHECK (relationship = ANY (ARRAY['self'::text, 'spouse'::text, 'child'::text, 'dependent'::text, 'other'::text])),
    full_name TEXT,
    date_of_birth DATE,
    ssn TEXT,
    age INTEGER,
    is_dependent BOOLEAN DEFAULT FALSE,
    is_over_65 BOOLEAN,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_household_members_case_id ON household_members(case_id);

-- Financial Accounts (Gold)
CREATE TABLE IF NOT EXISTS financial_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    account_type TEXT NOT NULL CHECK (account_type = ANY (ARRAY['checking'::text, 'savings'::text, 'investment'::text, 'retirement'::text, 'crypto'::text, 'other'::text])),
    institution_name TEXT,
    account_number TEXT,
    account_holder_name TEXT,
    current_balance NUMERIC DEFAULT 0,
    as_of_date DATE DEFAULT CURRENT_DATE,
    is_joint BOOLEAN DEFAULT FALSE,
    is_primary BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_financial_accounts_case_id ON financial_accounts(case_id);

-- Income Sources (Gold)
CREATE TABLE IF NOT EXISTS income_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    person_type TEXT NOT NULL CHECK (person_type = ANY (ARRAY['taxpayer'::text, 'spouse'::text, 'joint'::text, 'other'::text])),
    income_type TEXT NOT NULL CHECK (income_type = ANY (ARRAY['wages'::text, 'social_security'::text, 'pension'::text, 'dividends_interest'::text, 'rental_gross'::text, 'rental_expenses'::text, 'distributions'::text, 'alimony'::text, 'child_support'::text, 'other'::text, 'additional_1'::text, 'additional_2'::text])),
    description TEXT,
    amount NUMERIC NOT NULL DEFAULT 0,
    frequency TEXT DEFAULT 'annual'::text CHECK (frequency = ANY (ARRAY['weekly'::text, 'biweekly'::text, 'semimonthly'::text, 'monthly'::text, 'quarterly'::text, 'annual'::text])),
    normalized_monthly_amount NUMERIC DEFAULT 
        CASE frequency
            WHEN 'weekly'::text THEN (amount * 4.33)
            WHEN 'biweekly'::text THEN (amount * 2.17)
            WHEN 'semimonthly'::text THEN (amount * 2)
            WHEN 'monthly'::text THEN amount
            WHEN 'quarterly'::text THEN (amount / 3)
            WHEN 'annual'::text THEN (amount / 12)
            ELSE amount
        END,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_income_sources_case_id ON income_sources(case_id);

-- Monthly Expenses (Gold)
CREATE TABLE IF NOT EXISTS monthly_expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    expense_category TEXT NOT NULL CHECK (expense_category = ANY (ARRAY['food'::text, 'housekeeping'::text, 'apparel'::text, 'personal_care'::text, 'misc'::text, 'housing'::text, 'utilities'::text, 'transportation'::text, 'healthcare'::text, 'taxes'::text, 'insurance'::text, 'child_care'::text, 'court_payments'::text, 'other'::text])),
    expense_subcategory TEXT,
    description TEXT,
    amount NUMERIC NOT NULL DEFAULT 0,
    frequency TEXT DEFAULT 'monthly'::text CHECK (frequency = ANY (ARRAY['weekly'::text, 'biweekly'::text, 'semimonthly'::text, 'monthly'::text, 'quarterly'::text, 'annual'::text])),
    normalized_monthly_amount NUMERIC DEFAULT 
        CASE frequency
            WHEN 'weekly'::text THEN (amount * 4.33)
            WHEN 'biweekly'::text THEN (amount * 2.17)
            WHEN 'semimonthly'::text THEN (amount * 2)
            WHEN 'monthly'::text THEN amount
            WHEN 'quarterly'::text THEN (amount / 3)
            WHEN 'annual'::text THEN (amount / 12)
            ELSE amount
        END,
    is_irs_standard BOOLEAN DEFAULT FALSE,
    irs_standard_amount NUMERIC,
    use_irs_standard BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_monthly_expenses_case_id ON monthly_expenses(case_id);

-- Vehicles V2 (Gold)
CREATE TABLE IF NOT EXISTS vehicles_v2 (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    vehicle_type TEXT NOT NULL CHECK (vehicle_type = ANY (ARRAY['car'::text, 'truck'::text, 'motorcycle'::text, 'rv'::text, 'boat'::text, 'aircraft'::text, 'other'::text])),
    year INTEGER,
    make TEXT,
    model TEXT,
    vin TEXT,
    current_value NUMERIC DEFAULT 0,
    mileage INTEGER,
    loan_balance NUMERIC DEFAULT 0,
    monthly_payment NUMERIC DEFAULT 0,
    final_payment_date DATE,
    primary_use TEXT CHECK (primary_use = ANY (ARRAY['personal'::text, 'business'::text, 'mixed'::text])),
    business_use_percentage INTEGER DEFAULT 0 CHECK (business_use_percentage >= 0 AND business_use_percentage <= 100),
    equity NUMERIC DEFAULT (current_value - loan_balance),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vehicles_case_id ON vehicles_v2(case_id);

-- Real Property V2 (Gold)
CREATE TABLE IF NOT EXISTS real_property_v2 (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    property_type TEXT NOT NULL CHECK (property_type = ANY (ARRAY['primary_residence'::text, 'rental'::text, 'vacation'::text, 'commercial'::text, 'land'::text, 'other'::text])),
    address TEXT NOT NULL,
    city TEXT,
    county TEXT,
    state TEXT,
    zip_code TEXT,
    current_market_value NUMERIC DEFAULT 0,
    purchase_date DATE,
    purchase_price NUMERIC,
    mortgage_balance NUMERIC DEFAULT 0,
    monthly_payment NUMERIC DEFAULT 0,
    loan_interest_rate NUMERIC,
    final_payment_date DATE,
    rental_income_monthly NUMERIC DEFAULT 0,
    rental_expenses_monthly NUMERIC DEFAULT 0,
    net_rental_income_monthly NUMERIC DEFAULT (rental_income_monthly - rental_expenses_monthly),
    equity NUMERIC DEFAULT (current_market_value - mortgage_balance),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_real_property_case_id ON real_property_v2(case_id);

-- ============================================================================
-- PART 4: BUSINESS RULES TABLES (for AI Glossary functions)
-- ============================================================================

-- WI Type Rules (for Silver enrichment)
CREATE TABLE IF NOT EXISTS wi_type_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    form_code TEXT NOT NULL UNIQUE,
    form_name TEXT NOT NULL,
    category TEXT NOT NULL,
    is_self_employment BOOLEAN DEFAULT FALSE,
    include_in_projection BOOLEAN DEFAULT TRUE,
    affects_resolution_options BOOLEAN DEFAULT FALSE,
    resolution_income_asset TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    line_item_for_ti TEXT,
    form_433_line TEXT,
    income_fields JSONB,
    withholding_fields JSONB,
    threshold_amount NUMERIC,
    notes TEXT
);

-- AT Transaction Rules (for Silver enrichment)
CREATE TABLE IF NOT EXISTS at_transaction_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    meaning TEXT NOT NULL,
    transaction_type TEXT NOT NULL,
    affects_balance BOOLEAN DEFAULT FALSE,
    affects_csed BOOLEAN DEFAULT FALSE,
    indicates_collection_action BOOLEAN DEFAULT FALSE,
    starts_csed BOOLEAN DEFAULT FALSE,
    csed_toll_days INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    good_code TEXT,
    bad_code TEXT,
    file_status_rules JSONB
);

-- CSED Calculation Rules (for Gold business functions)
CREATE TABLE IF NOT EXISTS csed_calculation_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_category TEXT NOT NULL,
    start_code TEXT,
    end_code TEXT,
    standard_days INTEGER DEFAULT 3652,
    additional_toll_days INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- CSED Tolling Events (Silver/Gold)
CREATE TABLE IF NOT EXISTS csed_tolling_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tax_year_id UUID REFERENCES tax_years(id) ON DELETE CASCADE,
    tolling_type TEXT NOT NULL,
    start_code TEXT,
    start_date DATE,
    end_code TEXT,
    end_date DATE,
    interval_days INTEGER DEFAULT 0,
    additional_toll_days INTEGER DEFAULT 0,
    total_toll_days INTEGER DEFAULT 0,
    is_open BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_csed_tolling_tax_year_id ON csed_tolling_events(tax_year_id);

-- Status Definitions (for case management)
CREATE TABLE IF NOT EXISTS status_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    status_code TEXT NOT NULL UNIQUE,
    description TEXT NOT NULL,
    next_actions TEXT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================================
-- PART 5: ADD bronze_id COLUMNS TO EXISTING SILVER TABLES (if missing)
-- ============================================================================

-- Add bronze_id to tax_years if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'tax_years' AND column_name = 'bronze_id'
    ) THEN
        ALTER TABLE tax_years ADD COLUMN bronze_id UUID;
        CREATE INDEX IF NOT EXISTS idx_tax_years_bronze_id ON tax_years(bronze_id);
    END IF;
END $$;

-- Add bronze_id to account_activity if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'account_activity' AND column_name = 'bronze_id'
    ) THEN
        ALTER TABLE account_activity ADD COLUMN bronze_id UUID;
        CREATE INDEX IF NOT EXISTS idx_account_activity_bronze_id ON account_activity(bronze_id);
    END IF;
END $$;

-- Add bronze_id to income_documents if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'income_documents' AND column_name = 'bronze_id'
    ) THEN
        ALTER TABLE income_documents ADD COLUMN bronze_id UUID;
        CREATE INDEX IF NOT EXISTS idx_income_documents_bronze_id ON income_documents(bronze_id);
    END IF;
END $$;

-- Add bronze_id to trt_records if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'trt_records' AND column_name = 'bronze_id'
    ) THEN
        ALTER TABLE trt_records ADD COLUMN bronze_id UUID;
        CREATE INDEX IF NOT EXISTS idx_trt_records_bronze_id ON trt_records(bronze_id);
    END IF;
END $$;

-- Add bronze_id to logiqs_raw_data if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'logiqs_raw_data' AND column_name = 'bronze_id'
    ) THEN
        ALTER TABLE logiqs_raw_data ADD COLUMN bronze_id UUID;
        CREATE INDEX IF NOT EXISTS idx_logiqs_bronze_id ON logiqs_raw_data(bronze_id);
    END IF;
END $$;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Complete Medallion Schema Migration Applied!';
    RAISE NOTICE '📊 Bronze: Raw API responses (with lineage)';
    RAISE NOTICE '🥈 Silver: Typed & enriched data (with bronze_id)';
    RAISE NOTICE '🥇 Gold: Normalized business entities';
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Next: Create Bronze → Silver → Gold triggers';
END $$;


