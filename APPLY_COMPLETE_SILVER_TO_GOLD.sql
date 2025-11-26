-- ============================================================================
-- COMPLETE SILVER → GOLD TRIGGER (with pay_frequency normalization fix)
-- Purpose: Populate all Gold tables from logiqs_raw_data
-- ============================================================================
-- This includes:
-- 1. Employment Information (with pay_frequency normalization)
-- 2. Household Information
-- 3. Monthly Expenses
-- 4. Income Sources
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
  v_pay_freq_taxpayer TEXT;
  v_pay_freq_spouse TEXT;
BEGIN
  -- Get case UUID (logiqs_raw_data.case_id is already UUID)
  v_case_uuid := NEW.case_id;
  
  -- Normalize pay_frequency to lowercase
  v_pay_freq_taxpayer := LOWER(TRIM(COALESCE(NEW.b7, '')));
  v_pay_freq_spouse := LOWER(TRIM(COALESCE(NEW.c7, '')));
  
  -- Map common variations to allowed values
  IF v_pay_freq_taxpayer NOT IN ('weekly', 'biweekly', 'semimonthly', 'monthly', 'quarterly', 'annual') THEN
    v_pay_freq_taxpayer := NULL;
  END IF;
  
  IF v_pay_freq_spouse NOT IN ('weekly', 'biweekly', 'semimonthly', 'monthly', 'quarterly', 'annual') THEN
    v_pay_freq_spouse := NULL;
  END IF;
  
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
    v_pay_freq_taxpayer,  -- normalized pay_frequency
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
    v_pay_freq_spouse,  -- normalized pay_frequency
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
    CASE 
      WHEN NEW.b10 IS NOT NULL AND NEW.b10::TEXT ~ '^[0-9]+$' THEN (NEW.b10::TEXT)::INTEGER 
      ELSE 1 
    END,  -- clientHouseMembers
    CASE 
      WHEN NEW.b50 IS NOT NULL AND NEW.b50::TEXT ~ '^[0-9]+$' THEN (NEW.b50::TEXT)::INTEGER 
      ELSE 0 
    END,  -- under65
    CASE 
      WHEN NEW.b51 IS NOT NULL AND NEW.b51::TEXT ~ '^[0-9]+$' THEN (NEW.b51::TEXT)::INTEGER 
      ELSE 0 
    END,  -- over65
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
  
  -- Food/Clothing/Misc Expenses (normalized_monthly_amount is generated, don't insert it)
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency, is_irs_standard, irs_standard_amount)
  SELECT v_case_uuid, 'food', COALESCE(NEW.b56::NUMERIC, 0), 'monthly', 
         CASE WHEN NEW.c56 IS NOT NULL THEN TRUE ELSE FALSE END,
         NEW.c56::NUMERIC
  WHERE NEW.b56 IS NOT NULL AND NEW.b56 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency, is_irs_standard, irs_standard_amount)
  SELECT v_case_uuid, 'housekeeping', COALESCE(NEW.b57::NUMERIC, 0), 'monthly',
         CASE WHEN NEW.c57 IS NOT NULL THEN TRUE ELSE FALSE END,
         NEW.c57::NUMERIC
  WHERE NEW.b57 IS NOT NULL AND NEW.b57 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency, is_irs_standard, irs_standard_amount)
  SELECT v_case_uuid, 'apparel', COALESCE(NEW.b58::NUMERIC, 0), 'monthly',
         CASE WHEN NEW.c58 IS NOT NULL THEN TRUE ELSE FALSE END,
         NEW.c58::NUMERIC
  WHERE NEW.b58 IS NOT NULL AND NEW.b58 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency, is_irs_standard, irs_standard_amount)
  SELECT v_case_uuid, 'personal_care', COALESCE(NEW.b59::NUMERIC, 0), 'monthly',
         CASE WHEN NEW.c59 IS NOT NULL THEN TRUE ELSE FALSE END,
         NEW.c59::NUMERIC
  WHERE NEW.b59 IS NOT NULL AND NEW.b59 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency, is_irs_standard, irs_standard_amount)
  SELECT v_case_uuid, 'misc', COALESCE(NEW.b60::NUMERIC, 0), 'monthly',
         CASE WHEN NEW.c60 IS NOT NULL THEN TRUE ELSE FALSE END,
         NEW.c60::NUMERIC
  WHERE NEW.b60 IS NOT NULL AND NEW.b60 > 0;
  
  -- Housing Expenses (normalized_monthly_amount is generated)
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'housing', 'mortgage_lien_1', COALESCE(NEW.b64::NUMERIC, 0), 'monthly'
  WHERE NEW.b64 IS NOT NULL AND NEW.b64 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'housing', 'mortgage_lien_2', COALESCE(NEW.b65::NUMERIC, 0), 'monthly'
  WHERE NEW.b65 IS NOT NULL AND NEW.b65 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'housing', 'rent', COALESCE(NEW.b66::NUMERIC, 0), 'monthly'
  WHERE NEW.b66 IS NOT NULL AND NEW.b66 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'housing', 'insurance', COALESCE(NEW.b67::NUMERIC, 0), 'monthly'
  WHERE NEW.b67 IS NOT NULL AND NEW.b67 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'housing', 'property_tax', COALESCE(NEW.b68::NUMERIC, 0), 'monthly'
  WHERE NEW.b68 IS NOT NULL AND NEW.b68 > 0;
  
  -- Utilities (normalized_monthly_amount is generated)
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'utilities', 'gas', COALESCE(NEW.b69::NUMERIC, 0), 'monthly'
  WHERE NEW.b69 IS NOT NULL AND NEW.b69 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'utilities', 'electricity', COALESCE(NEW.b70::NUMERIC, 0), 'monthly'
  WHERE NEW.b70 IS NOT NULL AND NEW.b70 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'utilities', 'water', COALESCE(NEW.b71::NUMERIC, 0), 'monthly'
  WHERE NEW.b71 IS NOT NULL AND NEW.b71 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'utilities', 'sewer', COALESCE(NEW.b72::NUMERIC, 0), 'monthly'
  WHERE NEW.b72 IS NOT NULL AND NEW.b72 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'utilities', 'cable', COALESCE(NEW.b73::NUMERIC, 0), 'monthly'
  WHERE NEW.b73 IS NOT NULL AND NEW.b73 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'utilities', 'trash', COALESCE(NEW.b74::NUMERIC, 0), 'monthly'
  WHERE NEW.b74 IS NOT NULL AND NEW.b74 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'utilities', 'phone', COALESCE(NEW.b75::NUMERIC, 0), 'monthly'
  WHERE NEW.b75 IS NOT NULL AND NEW.b75 > 0;
  
  -- Healthcare Expenses (normalized_monthly_amount is generated)
  -- Note: b79 is TEXT, so we need to cast it
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'healthcare', 'insurance', 
         CASE 
           WHEN NEW.b79 IS NOT NULL AND NEW.b79::TEXT ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.b79::TEXT)::NUMERIC
           ELSE 0
         END, 
         'monthly'
  WHERE NEW.b79 IS NOT NULL AND NEW.b79::TEXT ~ '^[0-9]+(\.[0-9]+)?$';
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'healthcare', 'prescriptions', COALESCE(NEW.b80::NUMERIC, 0), 'monthly'
  WHERE NEW.b80 IS NOT NULL AND NEW.b80 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'healthcare', 'copays', COALESCE(NEW.b81::NUMERIC, 0), 'monthly'
  WHERE NEW.b81 IS NOT NULL AND NEW.b81 > 0;
  
  -- Taxes (normalized_monthly_amount is generated)
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency)
  SELECT v_case_uuid, 'taxes', COALESCE(NEW.b84::NUMERIC, 0), 'monthly'
  WHERE NEW.b84 IS NOT NULL AND NEW.b84 > 0;
  
  -- Other Expenses (normalized_monthly_amount is generated)
  -- Note: b87, b88, b90 are TEXT, so we need to cast them
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency)
  SELECT v_case_uuid, 'court_payments', 
         CASE 
           WHEN NEW.b87 IS NOT NULL AND NEW.b87::TEXT ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.b87::TEXT)::NUMERIC
           ELSE 0
         END, 
         'monthly'
  WHERE NEW.b87 IS NOT NULL AND NEW.b87::TEXT ~ '^[0-9]+(\.[0-9]+)?$';
  
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency)
  SELECT v_case_uuid, 'child_care', 
         CASE 
           WHEN NEW.b88 IS NOT NULL AND NEW.b88::TEXT ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.b88::TEXT)::NUMERIC
           ELSE 0
         END, 
         'monthly'
  WHERE NEW.b88 IS NOT NULL AND NEW.b88::TEXT ~ '^[0-9]+(\.[0-9]+)?$';
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'insurance', 'whole_life', COALESCE(NEW.b89::NUMERIC, 0), 'monthly'
  WHERE NEW.b89 IS NOT NULL AND NEW.b89 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'insurance', 'term_life', 
         CASE 
           WHEN NEW.b90 IS NOT NULL AND NEW.b90::TEXT ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.b90::TEXT)::NUMERIC
           ELSE 0
         END, 
         'monthly'
  WHERE NEW.b90 IS NOT NULL AND NEW.b90::TEXT ~ '^[0-9]+(\.[0-9]+)?$';
  
  -- Transportation Expenses (normalized_monthly_amount is generated)
  INSERT INTO monthly_expenses (case_id, expense_category, amount, frequency)
  SELECT v_case_uuid, 'transportation', 
         CASE 
           WHEN NEW.ak2 IS NOT NULL AND NEW.ak2 != '' AND NEW.ak2::TEXT ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.ak2::TEXT)::NUMERIC
           ELSE 0
         END, 
         'monthly'
  WHERE NEW.ak2 IS NOT NULL AND NEW.ak2 != '';
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'transportation', 'public_transportation', COALESCE(NEW.ak4::NUMERIC, 0), 'monthly'
  WHERE NEW.ak4 IS NOT NULL AND NEW.ak4 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'transportation', 'auto_insurance', COALESCE(NEW.ak6::NUMERIC, 0), 'monthly'
  WHERE NEW.ak6 IS NOT NULL AND NEW.ak6 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'transportation', 'auto_payment_1', COALESCE(NEW.ak7::NUMERIC, 0), 'monthly'
  WHERE NEW.ak7 IS NOT NULL AND NEW.ak7 > 0;
  
  INSERT INTO monthly_expenses (case_id, expense_category, expense_subcategory, amount, frequency)
  SELECT v_case_uuid, 'transportation', 'auto_payment_2', COALESCE(NEW.ak8::NUMERIC, 0), 'monthly'
  WHERE NEW.ak8 IS NOT NULL AND NEW.ak8 > 0;
  
  -- ============================================================================
  -- 4. INCOME SOURCES (from b33-b47)
  -- ============================================================================
  
  -- Delete existing income sources for this case (to avoid duplicates on update)
  DELETE FROM income_sources WHERE case_id = v_case_uuid;
  
  -- Taxpayer Wages (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'taxpayer', 'wages', COALESCE(NEW.b33::NUMERIC, 0), 'monthly'
  WHERE NEW.b33 IS NOT NULL AND NEW.b33 > 0;
  
  -- Taxpayer Social Security (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'taxpayer', 'social_security', COALESCE(NEW.b34::NUMERIC, 0), 'monthly'
  WHERE NEW.b34 IS NOT NULL AND NEW.b34 > 0;
  
  -- Taxpayer Pension (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'taxpayer', 'pension', COALESCE(NEW.b35::NUMERIC, 0), 'monthly'
  WHERE NEW.b35 IS NOT NULL AND NEW.b35 > 0;
  
  -- Spouse Wages (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'spouse', 'wages', COALESCE(NEW.b36::NUMERIC, 0), 'monthly'
  WHERE NEW.b36 IS NOT NULL AND NEW.b36 > 0;
  
  -- Spouse Social Security (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'spouse', 'social_security', COALESCE(NEW.b37::NUMERIC, 0), 'monthly'
  WHERE NEW.b37 IS NOT NULL AND NEW.b37 > 0;
  
  -- Spouse Pension (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'spouse', 'pension', COALESCE(NEW.b38::NUMERIC, 0), 'monthly'
  WHERE NEW.b38 IS NOT NULL AND NEW.b38 > 0;
  
  -- Dividends/Interest (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'joint', 'dividends_interest', COALESCE(NEW.b39::NUMERIC, 0), 'monthly'
  WHERE NEW.b39 IS NOT NULL AND NEW.b39 > 0;
  
  -- Rental Income (Gross) (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'joint', 'rental_gross', COALESCE(NEW.b40::NUMERIC, 0), 'monthly'
  WHERE NEW.b40 IS NOT NULL AND NEW.b40 > 0;
  
  -- Rental Expenses (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'joint', 'rental_expenses', COALESCE(NEW.b41::NUMERIC, 0), 'monthly'
  WHERE NEW.b41 IS NOT NULL AND NEW.b41 > 0;
  
  -- Distributions (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'joint', 'distributions', COALESCE(NEW.b42::NUMERIC, 0), 'monthly'
  WHERE NEW.b42 IS NOT NULL AND NEW.b42 > 0;
  
  -- Alimony (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'joint', 'alimony', COALESCE(NEW.b43::NUMERIC, 0), 'monthly'
  WHERE NEW.b43 IS NOT NULL AND NEW.b43 > 0;
  
  -- Child Support (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'joint', 'child_support', COALESCE(NEW.b44::NUMERIC, 0), 'monthly'
  WHERE NEW.b44 IS NOT NULL AND NEW.b44 > 0;
  
  -- Other Income (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'joint', 'other_income', COALESCE(NEW.b45::NUMERIC, 0), 'monthly'
  WHERE NEW.b45 IS NOT NULL AND NEW.b45 > 0;
  
  -- Additional Income 1 (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'joint', 'additional_income_1', COALESCE(NEW.b46::NUMERIC, 0), 'monthly'
  WHERE NEW.b46 IS NOT NULL AND NEW.b46 > 0;
  
  -- Additional Income 2 (normalized_monthly_amount is generated)
  INSERT INTO income_sources (case_id, person_type, income_type, amount, frequency)
  SELECT v_case_uuid, 'joint', 'additional_income_2', COALESCE(NEW.b47::NUMERIC, 0), 'monthly'
  WHERE NEW.b47 IS NOT NULL AND NEW.b47 > 0;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trigger_silver_to_gold
    AFTER INSERT OR UPDATE ON logiqs_raw_data
    FOR EACH ROW
    EXECUTE FUNCTION process_silver_to_gold();

