-- ============================================================================
-- APPLY_SILVER_TO_GOLD_TRIGGERS.sql
-- Purpose: Apply Silver → Gold triggers (safe to re-run)
-- ============================================================================
-- This file can be pasted directly into Supabase SQL Editor
-- It includes DROP statements to prevent conflicts on re-application
-- ============================================================================

-- Drop existing trigger and function if they exist
DROP TRIGGER IF EXISTS trigger_silver_to_gold ON logiqs_raw_data;
DROP FUNCTION IF EXISTS process_silver_to_gold();

-- ============================================================================
-- CREATE TRIGGER FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION process_silver_to_gold()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
BEGIN
  -- Get case UUID (logiqs_raw_data.case_id is already UUID)
  v_case_uuid := NEW.case_id;
  
  -- ============================================================================
  -- 1. EMPLOYMENT INFORMATION (from b3-b7, c3-c7, al7, al8)
  -- ============================================================================
  
  -- Taxpayer Employment
  INSERT INTO employment_information (
    case_id,
    person_type,
    employer_name,
    employment_start_date,
    gross_annual_income,
    net_annual_income,
    pay_frequency,
    gross_monthly_income,
    net_monthly_income,
    excel_reference_map
  )
  VALUES (
    v_case_uuid,
    'taxpayer',
    NEW.b3,  -- clientEmployer
    NEW.b4,  -- clientStartWorkingDate
    NEW.b5,  -- clientGrossIncome
    NEW.b6,  -- clientNetIncome
    NEW.b7,  -- clientFrequentlyPaid
    NEW.al7, -- taxpayer monthly income
    CASE 
      WHEN NEW.b6 IS NOT NULL AND NEW.b6 > 0 THEN NEW.b6 / 12
      ELSE NULL
    END,  -- net monthly (calculated)
    jsonb_build_object(
      'b3', 'employer_name',
      'b4', 'employment_start_date',
      'b5', 'gross_annual_income',
      'b6', 'net_annual_income',
      'b7', 'pay_frequency',
      'al7', 'gross_monthly_income'
    )
  )
  ON CONFLICT (case_id, person_type) DO UPDATE SET
    employer_name = EXCLUDED.employer_name,
    employment_start_date = EXCLUDED.employment_start_date,
    gross_annual_income = EXCLUDED.gross_annual_income,
    net_annual_income = EXCLUDED.net_annual_income,
    pay_frequency = EXCLUDED.pay_frequency,
    gross_monthly_income = EXCLUDED.gross_monthly_income,
    net_monthly_income = EXCLUDED.net_monthly_income,
    excel_reference_map = EXCLUDED.excel_reference_map,
    updated_at = NOW();
  
  -- Spouse Employment
  INSERT INTO employment_information (
    case_id,
    person_type,
    employer_name,
    employment_start_date,
    gross_annual_income,
    net_annual_income,
    pay_frequency,
    gross_monthly_income,
    net_monthly_income,
    excel_reference_map
  )
  VALUES (
    v_case_uuid,
    'spouse',
    NEW.c3,  -- spouseEmployer
    NEW.c4,  -- spouseStartWorkingDate
    NEW.c5,  -- spouseGrossIncome
    NEW.c6,  -- spouseNetIncome
    NEW.c7,  -- spouseFrequentlyPaid
    NEW.al8, -- spouse monthly income
    CASE 
      WHEN NEW.c6 IS NOT NULL AND NEW.c6 > 0 THEN NEW.c6 / 12
      ELSE NULL
    END,  -- net monthly (calculated)
    jsonb_build_object(
      'c3', 'employer_name',
      'c4', 'employment_start_date',
      'c5', 'gross_annual_income',
      'c6', 'net_annual_income',
      'c7', 'pay_frequency',
      'al8', 'gross_monthly_income'
    )
  )
  ON CONFLICT (case_id, person_type) DO UPDATE SET
    employer_name = EXCLUDED.employer_name,
    employment_start_date = EXCLUDED.employment_start_date,
    gross_annual_income = EXCLUDED.gross_annual_income,
    net_annual_income = EXCLUDED.net_annual_income,
    pay_frequency = EXCLUDED.pay_frequency,
    gross_monthly_income = EXCLUDED.gross_monthly_income,
    net_monthly_income = EXCLUDED.net_monthly_income,
    excel_reference_map = EXCLUDED.excel_reference_map,
    updated_at = NOW();
  
  -- ============================================================================
  -- 2. HOUSEHOLD INFORMATION (from b10-b14, c10-c14, b50-b53)
  -- ============================================================================
  
  INSERT INTO household_information (
    case_id,
    total_household_members,
    members_under_65,
    members_over_65,
    taxpayer_next_tax_return,
    taxpayer_spouse_claim,
    spouse_next_tax_return,
    spouse_spouse_claim,
    taxpayer_length_of_residency,
    taxpayer_occupancy_status,
    spouse_length_of_residency,
    spouse_occupancy_status,
    state,
    county,
    excel_reference_map
  )
  VALUES (
    v_case_uuid,
    COALESCE((NEW.b10::TEXT)::INTEGER, 1),  -- clientHouseMembers
    COALESCE((NEW.b50::TEXT)::INTEGER, 0),  -- under65
    COALESCE((NEW.b51::TEXT)::INTEGER, 0),  -- over65
    NEW.b11,  -- clientNextTaxReturn
    NEW.b12,  -- clientSpouseClaim
    NEW.c11,  -- spouseNextTaxReturn
    NEW.c12,  -- spouseSpouseClaim
    NEW.b13,  -- clientLengthofresidency
    NEW.b14,  -- clientOccupancyStatus
    NEW.c13,  -- spouseLengthofresidency
    NEW.c14,  -- spouseOccupancyStatus
    NEW.b52,  -- state
    NEW.b53,  -- county
    jsonb_build_object(
      'b10', 'total_household_members',
      'b50', 'members_under_65',
      'b51', 'members_over_65',
      'b11', 'taxpayer_next_tax_return',
      'b12', 'taxpayer_spouse_claim',
      'b52', 'state',
      'b53', 'county'
    )
  )
  ON CONFLICT (case_id) DO UPDATE SET
    total_household_members = EXCLUDED.total_household_members,
    members_under_65 = EXCLUDED.members_under_65,
    members_over_65 = EXCLUDED.members_over_65,
    taxpayer_next_tax_return = EXCLUDED.taxpayer_next_tax_return,
    taxpayer_spouse_claim = EXCLUDED.taxpayer_spouse_claim,
    spouse_next_tax_return = EXCLUDED.spouse_next_tax_return,
    spouse_spouse_claim = EXCLUDED.spouse_spouse_claim,
    taxpayer_length_of_residency = EXCLUDED.taxpayer_length_of_residency,
    taxpayer_occupancy_status = EXCLUDED.taxpayer_occupancy_status,
    spouse_length_of_residency = EXCLUDED.spouse_length_of_residency,
    spouse_occupancy_status = EXCLUDED.spouse_occupancy_status,
    state = EXCLUDED.state,
    county = EXCLUDED.county,
    excel_reference_map = EXCLUDED.excel_reference_map,
    updated_at = NOW();
  
  -- ============================================================================
  -- 3. MONTHLY EXPENSES (from b56-b90, ak2-ak8)
  -- ============================================================================
  
  -- Delete existing expenses for this case (to avoid duplicates on update)
  DELETE FROM monthly_expenses WHERE case_id = v_case_uuid;
  
  -- Food/Clothing/Misc Expenses
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency, normalized_monthly_amount, is_irs_standard, irs_standard_amount)
  SELECT v_case_uuid, 'food', COALESCE(NEW.b56, 0), 'monthly', COALESCE(NEW.b56, 0), 
         CASE WHEN NEW.c56 IS NOT NULL THEN TRUE ELSE FALSE END,
         NEW.c56
  WHERE NEW.b56 IS NOT NULL AND NEW.b56 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency, normalized_monthly_amount, is_irs_standard, irs_standard_amount)
  SELECT v_case_uuid, 'housekeeping', COALESCE(NEW.b57, 0), 'monthly', COALESCE(NEW.b57, 0),
         CASE WHEN NEW.c57 IS NOT NULL THEN TRUE ELSE FALSE END,
         NEW.c57
  WHERE NEW.b57 IS NOT NULL AND NEW.b57 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency, normalized_monthly_amount, is_irs_standard, irs_standard_amount)
  SELECT v_case_uuid, 'apparel', COALESCE(NEW.b58, 0), 'monthly', COALESCE(NEW.b58, 0),
         CASE WHEN NEW.c58 IS NOT NULL THEN TRUE ELSE FALSE END,
         NEW.c58
  WHERE NEW.b58 IS NOT NULL AND NEW.b58 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency, normalized_monthly_amount, is_irs_standard, irs_standard_amount)
  SELECT v_case_uuid, 'personal_care', COALESCE(NEW.b59, 0), 'monthly', COALESCE(NEW.b59, 0),
         CASE WHEN NEW.c59 IS NOT NULL THEN TRUE ELSE FALSE END,
         NEW.c59
  WHERE NEW.b59 IS NOT NULL AND NEW.b59 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency, normalized_monthly_amount, is_irs_standard, irs_standard_amount)
  SELECT v_case_uuid, 'misc', COALESCE(NEW.b60, 0), 'monthly', COALESCE(NEW.b60, 0),
         CASE WHEN NEW.c60 IS NOT NULL THEN TRUE ELSE FALSE END,
         NEW.c60
  WHERE NEW.b60 IS NOT NULL AND NEW.b60 > 0;
  
  -- Housing Expenses
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'housing', 'mortgage_lien_1', COALESCE(NEW.b64, 0), 'monthly', COALESCE(NEW.b64, 0)
  WHERE NEW.b64 IS NOT NULL AND NEW.b64 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'housing', 'mortgage_lien_2', COALESCE(NEW.b65, 0), 'monthly', COALESCE(NEW.b65, 0)
  WHERE NEW.b65 IS NOT NULL AND NEW.b65 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'housing', 'rent', COALESCE(NEW.b66, 0), 'monthly', COALESCE(NEW.b66, 0)
  WHERE NEW.b66 IS NOT NULL AND NEW.b66 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'housing', 'insurance', COALESCE(NEW.b67, 0), 'monthly', COALESCE(NEW.b67, 0)
  WHERE NEW.b67 IS NOT NULL AND NEW.b67 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'housing', 'property_tax', COALESCE(NEW.b68, 0), 'monthly', COALESCE(NEW.b68, 0)
  WHERE NEW.b68 IS NOT NULL AND NEW.b68 > 0;
  
  -- Utilities
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'utilities', 'gas', COALESCE(NEW.b69, 0), 'monthly', COALESCE(NEW.b69, 0)
  WHERE NEW.b69 IS NOT NULL AND NEW.b69 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'utilities', 'electricity', COALESCE(NEW.b70, 0), 'monthly', COALESCE(NEW.b70, 0)
  WHERE NEW.b70 IS NOT NULL AND NEW.b70 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'utilities', 'water', COALESCE(NEW.b71, 0), 'monthly', COALESCE(NEW.b71, 0)
  WHERE NEW.b71 IS NOT NULL AND NEW.b71 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'utilities', 'sewer', COALESCE(NEW.b72, 0), 'monthly', COALESCE(NEW.b72, 0)
  WHERE NEW.b72 IS NOT NULL AND NEW.b72 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'utilities', 'cable', COALESCE(NEW.b73, 0), 'monthly', COALESCE(NEW.b73, 0)
  WHERE NEW.b73 IS NOT NULL AND NEW.b73 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'utilities', 'trash', COALESCE(NEW.b74, 0), 'monthly', COALESCE(NEW.b74, 0)
  WHERE NEW.b74 IS NOT NULL AND NEW.b74 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'utilities', 'phone', COALESCE(NEW.b75, 0), 'monthly', COALESCE(NEW.b75, 0)
  WHERE NEW.b75 IS NOT NULL AND NEW.b75 > 0;
  
  -- Healthcare Expenses
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'healthcare', 'insurance', COALESCE(NEW.b79, 0), 'monthly', COALESCE(NEW.b79, 0)
  WHERE NEW.b79 IS NOT NULL AND NEW.b79 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'healthcare', 'prescriptions', COALESCE(NEW.b80, 0), 'monthly', COALESCE(NEW.b80, 0)
  WHERE NEW.b80 IS NOT NULL AND NEW.b80 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'healthcare', 'copays', COALESCE(NEW.b81, 0), 'monthly', COALESCE(NEW.b81, 0)
  WHERE NEW.b81 IS NOT NULL AND NEW.b81 > 0;
  
  -- Taxes
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'taxes', COALESCE(NEW.b84, 0), 'monthly', COALESCE(NEW.b84, 0)
  WHERE NEW.b84 IS NOT NULL AND NEW.b84 > 0;
  
  -- Other Expenses
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'court_payments', COALESCE(NEW.b87, 0), 'monthly', COALESCE(NEW.b87, 0)
  WHERE NEW.b87 IS NOT NULL AND NEW.b87 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'child_care', COALESCE(NEW.b88, 0), 'monthly', COALESCE(NEW.b88, 0)
  WHERE NEW.b88 IS NOT NULL AND NEW.b88 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'insurance', 'whole_life', COALESCE(NEW.b89, 0), 'monthly', COALESCE(NEW.b89, 0)
  WHERE NEW.b89 IS NOT NULL AND NEW.b89 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'insurance', 'term_life', COALESCE(NEW.b90, 0), 'monthly', COALESCE(NEW.b90, 0)
  WHERE NEW.b90 IS NOT NULL AND NEW.b90 > 0;
  
  -- Transportation Expenses
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'transportation', 'public_transportation', COALESCE(NEW.ak4, 0), 'monthly', COALESCE(NEW.ak4, 0)
  WHERE NEW.ak4 IS NOT NULL AND NEW.ak4 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'transportation', 'auto_insurance', COALESCE(NEW.ak6, 0), 'monthly', COALESCE(NEW.ak6, 0)
  WHERE NEW.ak6 IS NOT NULL AND NEW.ak6 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'transportation', 'auto_payment_1', COALESCE(NEW.ak7, 0), 'monthly', COALESCE(NEW.ak7, 0)
  WHERE NEW.ak7 IS NOT NULL AND NEW.ak7 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'transportation', 'auto_payment_2', COALESCE(NEW.ak8, 0), 'monthly', COALESCE(NEW.ak8, 0)
  WHERE NEW.ak8 IS NOT NULL AND NEW.ak8 > 0;
  
  -- ============================================================================
  -- 4. INCOME SOURCES (from b33-b47)
  -- ============================================================================
  
  -- Delete existing income sources for this case
  DELETE FROM income_sources WHERE case_id = v_case_uuid;
  
  -- Taxpayer Income
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'taxpayer', 'wages', COALESCE(NEW.b33, 0), 'annual', COALESCE(NEW.b33, 0) / 12
  WHERE NEW.b33 IS NOT NULL AND NEW.b33 > 0;
  
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'taxpayer', 'social_security', COALESCE(NEW.b34, 0), 'annual', COALESCE(NEW.b34, 0) / 12
  WHERE NEW.b34 IS NOT NULL AND NEW.b34 > 0;
  
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'taxpayer', 'pension', COALESCE(NEW.b35, 0), 'annual', COALESCE(NEW.b35, 0) / 12
  WHERE NEW.b35 IS NOT NULL AND NEW.b35 > 0;
  
  -- Spouse Income
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'spouse', 'wages', COALESCE(NEW.b36, 0), 'annual', COALESCE(NEW.b36, 0) / 12
  WHERE NEW.b36 IS NOT NULL AND NEW.b36 > 0;
  
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'spouse', 'social_security', COALESCE(NEW.b37, 0), 'annual', COALESCE(NEW.b37, 0) / 12
  WHERE NEW.b37 IS NOT NULL AND NEW.b37 > 0;
  
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'spouse', 'pension', COALESCE(NEW.b38, 0), 'annual', COALESCE(NEW.b38, 0) / 12
  WHERE NEW.b38 IS NOT NULL AND NEW.b38 > 0;
  
  -- Other Income
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'joint', 'dividends_interest', COALESCE(NEW.b39, 0), 'annual', COALESCE(NEW.b39, 0) / 12
  WHERE NEW.b39 IS NOT NULL AND NEW.b39 > 0;
  
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'joint', 'rental_gross', COALESCE(NEW.b40, 0), 'annual', COALESCE(NEW.b40, 0) / 12
  WHERE NEW.b40 IS NOT NULL AND NEW.b40 > 0;
  
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'joint', 'rental_expenses', COALESCE(NEW.b41, 0), 'annual', COALESCE(NEW.b41, 0) / 12
  WHERE NEW.b41 IS NOT NULL AND NEW.b41 > 0;
  
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'joint', 'distributions', COALESCE(NEW.b42, 0), 'annual', COALESCE(NEW.b42, 0) / 12
  WHERE NEW.b42 IS NOT NULL AND NEW.b42 > 0;
  
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'joint', 'alimony', COALESCE(NEW.b43, 0), 'annual', COALESCE(NEW.b43, 0) / 12
  WHERE NEW.b43 IS NOT NULL AND NEW.b43 > 0;
  
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'joint', 'child_support', COALESCE(NEW.b44, 0), 'annual', COALESCE(NEW.b44, 0) / 12
  WHERE NEW.b44 IS NOT NULL AND NEW.b44 > 0;
  
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'joint', 'other', COALESCE(NEW.b45, 0), 'annual', COALESCE(NEW.b45, 0) / 12
  WHERE NEW.b45 IS NOT NULL AND NEW.b45 > 0;
  
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'joint', 'additional_1', COALESCE(NEW.b46, 0), 'annual', COALESCE(NEW.b46, 0) / 12
  WHERE NEW.b46 IS NOT NULL AND NEW.b46 > 0;
  
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency, normalized_monthly_amount)
  SELECT v_case_uuid, 'joint', 'additional_2', COALESCE(NEW.b47, 0), 'annual', COALESCE(NEW.b47, 0) / 12
  WHERE NEW.b47 IS NOT NULL AND NEW.b47 > 0;
  
  -- ============================================================================
  -- 5. FINANCIAL ACCOUNTS (from b18-b22)
  -- ============================================================================
  
  -- Delete existing financial accounts for this case
  DELETE FROM financial_accounts WHERE case_id = v_case_uuid;
  
  -- Bank Accounts (b18 - sum of all accounts, we'll create one entry)
  INSERT INTO financial_accounts (case_id, account_type, current_balance, is_primary)
  SELECT v_case_uuid, 'checking', COALESCE(NEW.b18, 0), TRUE
  WHERE NEW.b18 IS NOT NULL AND NEW.b18 > 0;
  
  -- Cash on Hand
  INSERT INTO financial_accounts (case_id, account_type, description, current_balance)
  SELECT v_case_uuid, 'other', 'Cash on Hand', COALESCE(NEW.b19, 0)
  WHERE NEW.b19 IS NOT NULL AND NEW.b19 > 0;
  
  -- Investments
  INSERT INTO financial_accounts (case_id, account_type, current_balance)
  SELECT v_case_uuid, 'investment', COALESCE(NEW.b20, 0)
  WHERE NEW.b20 IS NOT NULL AND NEW.b20 > 0;
  
  -- Life Insurance
  INSERT INTO financial_accounts (case_id, account_type, description, current_balance)
  SELECT v_case_uuid, 'other', 'Life Insurance', COALESCE(NEW.b21, 0)
  WHERE NEW.b21 IS NOT NULL AND NEW.b21 > 0;
  
  -- Retirement
  INSERT INTO financial_accounts (case_id, account_type, current_balance)
  SELECT v_case_uuid, 'retirement', COALESCE(NEW.b22, 0)
  WHERE NEW.b22 IS NOT NULL AND NEW.b22 > 0;
  
  -- ============================================================================
  -- 6. VEHICLES (from b24-b27, d24-d27)
  -- ============================================================================
  
  -- Delete existing vehicles for this case
  DELETE FROM vehicles_v2 WHERE case_id = v_case_uuid;
  
  -- Vehicle 1
  INSERT INTO vehicles_v2 (case_id, vehicle_type, current_value, loan_balance, equity)
  SELECT v_case_uuid, 'car', COALESCE(NEW.b24, 0), COALESCE(NEW.d24, 0), 
         COALESCE(NEW.b24, 0) - COALESCE(NEW.d24, 0)
  WHERE NEW.b24 IS NOT NULL AND NEW.b24 > 0;
  
  -- Vehicle 2
  INSERT INTO vehicles_v2 (case_id, vehicle_type, current_value, loan_balance, equity)
  SELECT v_case_uuid, 'car', COALESCE(NEW.b25, 0), COALESCE(NEW.d25, 0),
         COALESCE(NEW.b25, 0) - COALESCE(NEW.d25, 0)
  WHERE NEW.b25 IS NOT NULL AND NEW.b25 > 0;
  
  -- Vehicle 3
  INSERT INTO vehicles_v2 (case_id, vehicle_type, current_value, loan_balance, equity)
  SELECT v_case_uuid, 'car', COALESCE(NEW.b26, 0), COALESCE(NEW.d26, 0),
         COALESCE(NEW.b26, 0) - COALESCE(NEW.d26, 0)
  WHERE NEW.b26 IS NOT NULL AND NEW.b26 > 0;
  
  -- Vehicle 4
  INSERT INTO vehicles_v2 (case_id, vehicle_type, current_value, loan_balance, equity)
  SELECT v_case_uuid, 'car', COALESCE(NEW.b27, 0), COALESCE(NEW.d27, 0),
         COALESCE(NEW.b27, 0) - COALESCE(NEW.d27, 0)
  WHERE NEW.b27 IS NOT NULL AND NEW.b27 > 0;
  
  -- ============================================================================
  -- 7. REAL PROPERTY (from b23, d23)
  -- ============================================================================
  
  -- Delete existing real property for this case
  DELETE FROM real_property_v2 WHERE case_id = v_case_uuid;
  
  -- Real Estate (primary residence assumed if exists)
  INSERT INTO real_property_v2 (
    case_id,
    property_type,
    current_market_value,
    mortgage_balance,
    equity
  )
  SELECT 
    v_case_uuid,
    'primary_residence',
    COALESCE(NEW.b23, 0),
    COALESCE(NEW.d23, 0),
    COALESCE(NEW.b23, 0) - COALESCE(NEW.d23, 0)
  WHERE NEW.b23 IS NOT NULL AND NEW.b23 > 0;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION process_silver_to_gold IS 'Populate Gold layer tables from Silver logiqs_raw_data - transforms Excel cell references to semantic business entities';

-- ============================================================================
-- CREATE TRIGGER
-- ============================================================================

CREATE TRIGGER trigger_silver_to_gold
    AFTER INSERT OR UPDATE ON logiqs_raw_data
    FOR EACH ROW
    EXECUTE FUNCTION process_silver_to_gold();

COMMENT ON TRIGGER trigger_silver_to_gold ON logiqs_raw_data IS 'Automatically populates Gold tables when Silver logiqs_raw_data is inserted/updated';

-- ============================================================================
-- ADD UNIQUE CONSTRAINT FOR EMPLOYMENT (if not exists)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'employment_information_case_person_unique'
  ) THEN
    ALTER TABLE employment_information 
    ADD CONSTRAINT employment_information_case_person_unique 
    UNIQUE (case_id, person_type);
  END IF;
END $$;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Silver → Gold triggers created!';
    RAISE NOTICE '';
    RAISE NOTICE '📊 When logiqs_raw_data is inserted/updated:';
    RAISE NOTICE '  → employment_information (taxpayer + spouse)';
    RAISE NOTICE '  → household_information';
    RAISE NOTICE '  → monthly_expenses (all categories)';
    RAISE NOTICE '  → income_sources (all types)';
    RAISE NOTICE '  → financial_accounts';
    RAISE NOTICE '  → vehicles_v2';
    RAISE NOTICE '  → real_property_v2';
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Complete pipeline: Bronze → Silver → Gold';
END $$;

