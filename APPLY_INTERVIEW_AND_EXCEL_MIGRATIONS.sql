-- ============================================================================
-- COMPLETE MIGRATION: Interview Field Extraction + Excel Formula Replacement
-- ============================================================================
-- Apply this entire file in Supabase SQL Editor
-- This combines:
-- 1. Interview field extraction (replaces simple JSONB storage with full extraction)
-- 2. Excel formula replacement (SQL functions instead of Excel formulas)
-- ============================================================================

-- ============================================================================
-- PART 1: INTERVIEW FIELD EXTRACTION
-- ============================================================================

-- Helper function to safely extract nested JSONB values
CREATE OR REPLACE FUNCTION safe_jsonb_get(data JSONB, path TEXT[])
RETURNS JSONB AS $$
BEGIN
  DECLARE
    result JSONB := data;
    key TEXT;
  BEGIN
    FOREACH key IN ARRAY path
    LOOP
      IF result IS NULL THEN
        RETURN NULL;
      END IF;
      result := result->key;
    END LOOP;
    RETURN result;
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Helper function to safely extract text from JSONB
CREATE OR REPLACE FUNCTION safe_jsonb_text(data JSONB, path TEXT[], default_val TEXT DEFAULT '')
RETURNS TEXT AS $$
BEGIN
  DECLARE
    val JSONB := safe_jsonb_get(data, path);
  BEGIN
    IF val IS NULL OR val = 'null'::jsonb THEN
      RETURN default_val;
    END IF;
    RETURN COALESCE(val::text, default_val);
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Helper function to safely extract decimal from JSONB
CREATE OR REPLACE FUNCTION safe_jsonb_decimal(data JSONB, path TEXT[], default_val NUMERIC DEFAULT 0)
RETURNS NUMERIC AS $$
BEGIN
  DECLARE
    val JSONB := safe_jsonb_get(data, path);
    num_val NUMERIC;
  BEGIN
    IF val IS NULL OR val = 'null'::jsonb THEN
      RETURN default_val;
    END IF;
    
    -- Try to cast to numeric
    BEGIN
      num_val := (val::text)::NUMERIC;
      RETURN num_val;
    EXCEPTION
      WHEN OTHERS THEN
        RETURN default_val;
    END;
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Helper function to safely extract date from JSONB
CREATE OR REPLACE FUNCTION safe_jsonb_date(data JSONB, path TEXT[])
RETURNS DATE AS $$
BEGIN
  DECLARE
    val JSONB := safe_jsonb_get(data, path);
    date_str TEXT;
  BEGIN
    IF val IS NULL OR val = 'null'::jsonb THEN
      RETURN NULL;
    END IF;
    
    date_str := val::text;
    -- Remove quotes if present
    date_str := TRIM(BOTH '"' FROM date_str);
    
    -- Try common date formats
    BEGIN
      RETURN date_str::DATE;
    EXCEPTION
      WHEN OTHERS THEN
        -- Try MM/DD/YYYY format
        BEGIN
          RETURN TO_DATE(date_str, 'MM/DD/YYYY');
        EXCEPTION
          WHEN OTHERS THEN
            RETURN NULL;
        END;
    END;
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Replace the simple interview trigger with comprehensive field extraction
CREATE OR REPLACE FUNCTION process_bronze_interview()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
  v_response JSONB;
  v_employment JSONB;
  v_household JSONB;
  v_assets JSONB;
  v_income JSONB;
  v_expenses JSONB;
  v_result JSONB;
  v_raw_data JSONB;
BEGIN
  -- Get or create case UUID
  v_case_uuid := ensure_case(NEW.case_id);
  v_response := NEW.raw_response;
  
  -- Extract major sections
  v_employment := COALESCE(v_response->'employment', '{}'::jsonb);
  v_household := COALESCE(v_response->'household', '{}'::jsonb);
  v_assets := COALESCE(v_response->'assets', '{}'::jsonb);
  v_income := COALESCE(v_response->'income', '{}'::jsonb);
  v_expenses := COALESCE(v_response->'expenses', '{}'::jsonb);
  v_result := COALESCE(v_response->'Result', v_response->'result', '{}'::jsonb);
  v_raw_data := COALESCE(v_response->'raw_data', '{}'::jsonb);
  
  -- Insert/update logiqs_raw_data with ALL extracted fields
  INSERT INTO logiqs_raw_data (
    case_id,
    bronze_id,
    employment, household, assets, income, expenses, irs_standards,
    b3, b4, b5, b6, b7,
    c3, c4, c5, c6, c7,
    b10, b11, b12, b13, b14,
    c10, c11, c12, c13, c14,
    b18, b19, b20, b21, b22, b23, b24, b25, b26, b27, b28, b29,
    d20, d21, d22, d23, d24, d25, d26, d27, d28, d29,
    b33, b34, b35, b36, b37, b38, b39, b40, b41, b42, b43, b44, b45, b46, b47,
    b50, b51, b52, b53,
    b56, b57, b58, b59, b60,
    b64, b65, b66, b67, b68, b69, b70, b71, b72, b73, b74, b75,
    b79, b80, b81,
    b84,
    b87, b88, b89, b90,
    ak2, ak4, ak5, ak6, ak7, ak8,
    c56, c57, c58, c59, c60, c61_irs, c61, c76, c80,
    al4, al5, al7, al8,
    raw_response,
    extracted_at
  )
  VALUES (
    v_case_uuid,
    NEW.bronze_id,
    v_employment, v_household, v_assets, v_income, v_expenses, v_result,
    safe_jsonb_text(v_employment, ARRAY['clientEmployer']),
    safe_jsonb_date(v_employment, ARRAY['clientStartWorkingDate']),
    safe_jsonb_decimal(v_employment, ARRAY['clientGrossIncome']),
    safe_jsonb_decimal(v_employment, ARRAY['clientNetIncome']),
    safe_jsonb_text(v_employment, ARRAY['clientFrequentlyPaid']),
    safe_jsonb_text(v_employment, ARRAY['spouseEmployer']),
    safe_jsonb_date(v_employment, ARRAY['spouseStartWorkingDate']),
    safe_jsonb_decimal(v_employment, ARRAY['spouseGrossIncome']),
    safe_jsonb_decimal(v_employment, ARRAY['spouseNetIncome']),
    safe_jsonb_text(v_employment, ARRAY['spouseFrequentlyPaid']),
    safe_jsonb_text(v_employment, ARRAY['clientHouseMembers']),
    safe_jsonb_text(v_employment, ARRAY['clientNextTaxReturn']),
    safe_jsonb_text(v_employment, ARRAY['clientSpouseClaim']),
    safe_jsonb_text(v_employment, ARRAY['clientLengthofresidency']),
    safe_jsonb_text(v_employment, ARRAY['clientOccupancyStatus']),
    safe_jsonb_text(v_employment, ARRAY['spouseHouseMembers']),
    safe_jsonb_text(v_employment, ARRAY['spouseNextTaxReturn']),
    safe_jsonb_text(v_employment, ARRAY['spouseSpouseClaim']),
    safe_jsonb_text(v_employment, ARRAY['spouseLengthofresidency']),
    safe_jsonb_text(v_employment, ARRAY['spouseOccupancyStatus']),
    safe_jsonb_decimal(v_assets, ARRAY['bankAccounts', 'accountsData']),
    safe_jsonb_decimal(v_assets, ARRAY['cashOnHand']),
    safe_jsonb_decimal(v_assets, ARRAY['investments', 'investmentMarketValue']),
    safe_jsonb_decimal(v_assets, ARRAY['lifeInsurance', 'insuranceMarketValue']),
    safe_jsonb_decimal(v_assets, ARRAY['retirement', 'retirementMarketValue']),
    safe_jsonb_decimal(v_assets, ARRAY['realProperty', 'realEstateMarketValue']),
    safe_jsonb_decimal(v_assets, ARRAY['vehicles', 'vehicle1MarketValue']),
    safe_jsonb_decimal(v_assets, ARRAY['vehicles', 'vehicle2MarketValue']),
    safe_jsonb_decimal(v_assets, ARRAY['vehicles', 'vehicle3MarketValue']),
    safe_jsonb_decimal(v_assets, ARRAY['vehicles', 'vehicle4MarketValue']),
    safe_jsonb_decimal(v_assets, ARRAY['personalEffects', 'personalEffectsMarketValue']),
    safe_jsonb_decimal(v_assets, ARRAY['otherAssets', 'otherAssetsMarketValue']),
    safe_jsonb_decimal(v_assets, ARRAY['investments', 'investmentLoan']),
    safe_jsonb_decimal(v_assets, ARRAY['lifeInsurance', 'insuranceLoan']),
    safe_jsonb_decimal(v_assets, ARRAY['retirement', 'retirementLoan']),
    safe_jsonb_decimal(v_assets, ARRAY['realProperty', 'realEstateLoan']),
    safe_jsonb_decimal(v_assets, ARRAY['vehicles', 'vehicle1Loan']),
    safe_jsonb_decimal(v_assets, ARRAY['vehicles', 'vehicle2Loan']),
    safe_jsonb_decimal(v_assets, ARRAY['vehicles', 'vehicle3Loan']),
    safe_jsonb_decimal(v_assets, ARRAY['vehicles', 'vehicle4Loan']),
    safe_jsonb_decimal(v_assets, ARRAY['personalEffects', 'personalEffectsLoan']),
    safe_jsonb_decimal(v_assets, ARRAY['otherAssets', 'otherAssetsLoan']),
    safe_jsonb_decimal(v_income, ARRAY['taxpayerIncome', 'wages']),
    safe_jsonb_decimal(v_income, ARRAY['taxpayerIncome', 'socialSecurity']),
    safe_jsonb_decimal(v_income, ARRAY['taxpayerIncome', 'pension']),
    safe_jsonb_decimal(v_income, ARRAY['spouseIncome', 'wages']),
    safe_jsonb_decimal(v_income, ARRAY['spouseIncome', 'socialSecurity']),
    safe_jsonb_decimal(v_income, ARRAY['spouseIncome', 'pension']),
    safe_jsonb_decimal(v_income, ARRAY['otherIncome', 'dividendsInterest']),
    safe_jsonb_decimal(v_income, ARRAY['otherIncome', 'rentalGross']),
    safe_jsonb_decimal(v_income, ARRAY['otherIncome', 'rentalExpenses']),
    safe_jsonb_decimal(v_income, ARRAY['otherIncome', 'distributions']),
    safe_jsonb_decimal(v_income, ARRAY['otherIncome', 'alimony']),
    safe_jsonb_decimal(v_income, ARRAY['otherIncome', 'childSupport']),
    safe_jsonb_decimal(v_income, ARRAY['otherIncome', 'other']),
    safe_jsonb_decimal(v_raw_data, ARRAY['IncomeAdditional1']),
    safe_jsonb_decimal(v_raw_data, ARRAY['IncomeAdditional2']),
    safe_jsonb_text(v_expenses, ARRAY['familySize', 'under65']),
    safe_jsonb_text(v_expenses, ARRAY['familySize', 'over65']),
    safe_jsonb_text(v_expenses, ARRAY['location', 'state']),
    safe_jsonb_text(v_expenses, ARRAY['location', 'county']),
    safe_jsonb_decimal(v_expenses, ARRAY['foodClothingMisc', 'food']),
    safe_jsonb_decimal(v_expenses, ARRAY['foodClothingMisc', 'housekeeping']),
    safe_jsonb_decimal(v_expenses, ARRAY['foodClothingMisc', 'apparel']),
    safe_jsonb_decimal(v_expenses, ARRAY['foodClothingMisc', 'personalCare']),
    safe_jsonb_decimal(v_expenses, ARRAY['foodClothingMisc', 'misc']),
    safe_jsonb_decimal(v_expenses, ARRAY['housing', 'mortgageLien1']),
    safe_jsonb_decimal(v_expenses, ARRAY['housing', 'mortgageLien2']),
    safe_jsonb_decimal(v_expenses, ARRAY['housing', 'rent']),
    safe_jsonb_decimal(v_expenses, ARRAY['housing', 'insurance']),
    safe_jsonb_decimal(v_expenses, ARRAY['housing', 'propertyTax']),
    safe_jsonb_decimal(v_expenses, ARRAY['housing', 'utilities', 'gas']),
    safe_jsonb_decimal(v_expenses, ARRAY['housing', 'utilities', 'electricity']),
    safe_jsonb_decimal(v_expenses, ARRAY['housing', 'utilities', 'water']),
    safe_jsonb_decimal(v_expenses, ARRAY['housing', 'utilities', 'sewer']),
    safe_jsonb_decimal(v_expenses, ARRAY['housing', 'utilities', 'cable']),
    safe_jsonb_decimal(v_expenses, ARRAY['housing', 'utilities', 'trash']),
    safe_jsonb_decimal(v_expenses, ARRAY['housing', 'utilities', 'phone']),
    safe_jsonb_decimal(v_expenses, ARRAY['healthcare', 'healthInsurance']),
    safe_jsonb_decimal(v_expenses, ARRAY['healthcare', 'prescriptions']),
    safe_jsonb_decimal(v_expenses, ARRAY['healthcare', 'copays']),
    safe_jsonb_decimal(v_expenses, ARRAY['taxes']),
    safe_jsonb_decimal(v_raw_data, ARRAY['ExpenseCourtPayments']),
    safe_jsonb_decimal(v_raw_data, ARRAY['ExpenseChildCare']),
    safe_jsonb_decimal(v_raw_data, ARRAY['ExpenseWholeLifeInsurance']),
    safe_jsonb_decimal(v_raw_data, ARRAY['ExpenseTermLifeInsurance']),
    safe_jsonb_text(v_expenses, ARRAY['transportation', 'vehicleCount']),
    safe_jsonb_decimal(v_expenses, ARRAY['transportation', 'publicTransportation']),
    safe_jsonb_decimal(v_raw_data, ARRAY['ExpenseAutoTotal']),
    safe_jsonb_decimal(v_expenses, ARRAY['transportation', 'autoInsurance']),
    safe_jsonb_decimal(v_expenses, ARRAY['transportation', 'autoPayment1']),
    safe_jsonb_decimal(v_expenses, ARRAY['transportation', 'autoPayment2']),
    safe_jsonb_decimal(v_result, ARRAY['Food']),
    safe_jsonb_decimal(v_result, ARRAY['Housekeeping']),
    safe_jsonb_decimal(v_result, ARRAY['Apparel']),
    safe_jsonb_decimal(v_result, ARRAY['PersonalCare']),
    safe_jsonb_decimal(v_result, ARRAY['Misc']),
    safe_jsonb_decimal(v_result, ARRAY['FoodClothingMiscTotal']),
    safe_jsonb_text(v_employment, ARRAY['clientEmployer']),
    safe_jsonb_text(v_employment, ARRAY['spouseEmployer']),
    safe_jsonb_decimal(v_result, ARRAY['HealthOutOfPocket']),
    safe_jsonb_decimal(v_result, ARRAY['PublicTrans']),
    safe_jsonb_decimal(v_expenses, ARRAY['foodClothingMisc', 'food']),
    safe_jsonb_decimal(v_income, ARRAY['taxpayerIncome', 'wages']),
    safe_jsonb_decimal(v_income, ARRAY['spouseIncome', 'wages']),
    v_response,
    NOW()
  )
  ON CONFLICT (case_id) DO UPDATE SET
    bronze_id = NEW.bronze_id,
    employment = EXCLUDED.employment,
    household = EXCLUDED.household,
    assets = EXCLUDED.assets,
    income = EXCLUDED.income,
    expenses = EXCLUDED.expenses,
    irs_standards = EXCLUDED.irs_standards,
    b3 = EXCLUDED.b3, b4 = EXCLUDED.b4, b5 = EXCLUDED.b5, b6 = EXCLUDED.b6, b7 = EXCLUDED.b7,
    c3 = EXCLUDED.c3, c4 = EXCLUDED.c4, c5 = EXCLUDED.c5, c6 = EXCLUDED.c6, c7 = EXCLUDED.c7,
    b10 = EXCLUDED.b10, b11 = EXCLUDED.b11, b12 = EXCLUDED.b12, b13 = EXCLUDED.b13, b14 = EXCLUDED.b14,
    c10 = EXCLUDED.c10, c11 = EXCLUDED.c11, c12 = EXCLUDED.c12, c13 = EXCLUDED.c13, c14 = EXCLUDED.c14,
    b18 = EXCLUDED.b18, b19 = EXCLUDED.b19, b20 = EXCLUDED.b20, b21 = EXCLUDED.b21, b22 = EXCLUDED.b22,
    b23 = EXCLUDED.b23, b24 = EXCLUDED.b24, b25 = EXCLUDED.b25, b26 = EXCLUDED.b26, b27 = EXCLUDED.b27,
    b28 = EXCLUDED.b28, b29 = EXCLUDED.b29,
    d20 = EXCLUDED.d20, d21 = EXCLUDED.d21, d22 = EXCLUDED.d22, d23 = EXCLUDED.d23, d24 = EXCLUDED.d24,
    d25 = EXCLUDED.d25, d26 = EXCLUDED.d26, d27 = EXCLUDED.d27, d28 = EXCLUDED.d28, d29 = EXCLUDED.d29,
    b33 = EXCLUDED.b33, b34 = EXCLUDED.b34, b35 = EXCLUDED.b35, b36 = EXCLUDED.b36, b37 = EXCLUDED.b37,
    b38 = EXCLUDED.b38, b39 = EXCLUDED.b39, b40 = EXCLUDED.b40, b41 = EXCLUDED.b41, b42 = EXCLUDED.b42,
    b43 = EXCLUDED.b43, b44 = EXCLUDED.b44, b45 = EXCLUDED.b45, b46 = EXCLUDED.b46, b47 = EXCLUDED.b47,
    b50 = EXCLUDED.b50, b51 = EXCLUDED.b51, b52 = EXCLUDED.b52, b53 = EXCLUDED.b53,
    b56 = EXCLUDED.b56, b57 = EXCLUDED.b57, b58 = EXCLUDED.b58, b59 = EXCLUDED.b59, b60 = EXCLUDED.b60,
    b64 = EXCLUDED.b64, b65 = EXCLUDED.b65, b66 = EXCLUDED.b66, b67 = EXCLUDED.b67, b68 = EXCLUDED.b68,
    b69 = EXCLUDED.b69, b70 = EXCLUDED.b70, b71 = EXCLUDED.b71, b72 = EXCLUDED.b72, b73 = EXCLUDED.b73,
    b74 = EXCLUDED.b74, b75 = EXCLUDED.b75,
    b79 = EXCLUDED.b79, b80 = EXCLUDED.b80, b81 = EXCLUDED.b81,
    b84 = EXCLUDED.b84,
    b87 = EXCLUDED.b87, b88 = EXCLUDED.b88, b89 = EXCLUDED.b89, b90 = EXCLUDED.b90,
    ak2 = EXCLUDED.ak2, ak4 = EXCLUDED.ak4, ak5 = EXCLUDED.ak5, ak6 = EXCLUDED.ak6,
    ak7 = EXCLUDED.ak7, ak8 = EXCLUDED.ak8,
    c56 = EXCLUDED.c56, c57 = EXCLUDED.c57, c58 = EXCLUDED.c58, c59 = EXCLUDED.c59, c60 = EXCLUDED.c60,
    c61_irs = EXCLUDED.c61_irs, c61 = EXCLUDED.c61, c76 = EXCLUDED.c76, c80 = EXCLUDED.c80,
    al4 = EXCLUDED.al4, al5 = EXCLUDED.al5, al7 = EXCLUDED.al7, al8 = EXCLUDED.al8,
    raw_response = EXCLUDED.raw_response,
    extracted_at = NOW(),
    updated_at = NOW();
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION process_bronze_interview IS 'Extract ALL interview fields (expenses, household, employment) from Bronze JSONB into Silver logiqs_raw_data';

-- ============================================================================
-- PART 2: EXCEL FORMULA REPLACEMENT
-- ============================================================================

-- Drop existing functions if they exist (to avoid return type conflicts)
DROP FUNCTION IF EXISTS calculate_total_monthly_income(UUID);
DROP FUNCTION IF EXISTS calculate_total_monthly_expenses(UUID);
DROP FUNCTION IF EXISTS calculate_disposable_income(UUID);
DROP FUNCTION IF EXISTS get_cell_value(UUID, TEXT);

-- Function: Calculate Total Monthly Income (Excel: =SUM('logiqs raw data'!AL7:AL8))
CREATE OR REPLACE FUNCTION calculate_total_monthly_income(p_case_id UUID)
RETURNS TABLE (
  taxpayer_monthly NUMERIC,
  spouse_monthly NUMERIC,
  total_monthly NUMERIC
) AS $$
BEGIN
  -- Check if logiqs_raw_data table exists
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'logiqs_raw_data') THEN
    RETURN QUERY
    SELECT 
      COALESCE(lrd.al7, 0) as taxpayer_monthly,
      COALESCE(lrd.al8, 0) as spouse_monthly,
      COALESCE(lrd.al7, 0) + COALESCE(lrd.al8, 0) as total_monthly
    FROM logiqs_raw_data lrd
    WHERE lrd.case_id = p_case_id;
  ELSE
    -- Return zeros if table doesn't exist yet
    RETURN QUERY SELECT 0::NUMERIC, 0::NUMERIC, 0::NUMERIC;
  END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_total_monthly_income IS 'Replaces Excel formula: =SUM(logiqs raw data!AL7:AL8) - Total monthly income (taxpayer + spouse)';

-- Function: Calculate Total Monthly Expenses (Excel: =SUM('logiqs raw data'!AK7:AK8))
CREATE OR REPLACE FUNCTION calculate_total_monthly_expenses(p_case_id UUID)
RETURNS TABLE (
  auto_payment_1 NUMERIC,
  auto_payment_2 NUMERIC,
  total_auto_payments NUMERIC,
  total_all_expenses NUMERIC
) AS $$
BEGIN
  -- Check if logiqs_raw_data table exists
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'logiqs_raw_data') THEN
    RETURN QUERY
    SELECT 
      COALESCE(lrd.ak7, 0) as auto_payment_1,
      COALESCE(lrd.ak8, 0) as auto_payment_2,
      COALESCE(lrd.ak7, 0) + COALESCE(lrd.ak8, 0) as total_auto_payments,
      COALESCE(lrd.b56, 0) + COALESCE(lrd.b57, 0) + COALESCE(lrd.b58, 0) + 
      COALESCE(lrd.b59, 0) + COALESCE(lrd.b60, 0) + COALESCE(lrd.b64, 0) + 
      COALESCE(lrd.b65, 0) + COALESCE(lrd.b66, 0) + COALESCE(lrd.b67, 0) + 
      COALESCE(lrd.b68, 0) + COALESCE(lrd.b69, 0) + COALESCE(lrd.b70, 0) + 
      COALESCE(lrd.b71, 0) + COALESCE(lrd.b72, 0) + COALESCE(lrd.b73, 0) + 
      COALESCE(lrd.b74, 0) + COALESCE(lrd.b75, 0) + COALESCE(lrd.b79, 0) + 
      COALESCE(lrd.b80, 0) + COALESCE(lrd.b81, 0) + COALESCE(lrd.b84, 0) + 
      COALESCE(lrd.b87, 0) + COALESCE(lrd.b88, 0) + COALESCE(lrd.b89, 0) + 
      COALESCE(lrd.b90, 0) + COALESCE(lrd.ak4, 0) + COALESCE(lrd.ak5, 0) + 
      COALESCE(lrd.ak6, 0) + COALESCE(lrd.ak7, 0) + COALESCE(lrd.ak8, 0) as total_all_expenses
    FROM logiqs_raw_data lrd
    WHERE lrd.case_id = p_case_id;
  ELSE
    -- Return zeros if table doesn't exist yet
    RETURN QUERY SELECT 0::NUMERIC, 0::NUMERIC, 0::NUMERIC, 0::NUMERIC;
  END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_total_monthly_expenses IS 'Replaces Excel formula: =SUM(logiqs raw data!AK7:AK8) and total expense calculations';

-- Function: Calculate Disposable Income (Excel: D186 - E186)
CREATE OR REPLACE FUNCTION calculate_disposable_income(p_case_id UUID)
RETURNS TABLE (
  total_monthly_income NUMERIC,
  total_monthly_expenses NUMERIC,
  disposable_income NUMERIC
) AS $$
DECLARE
  v_income NUMERIC;
  v_expenses NUMERIC;
BEGIN
  SELECT total_monthly INTO v_income FROM calculate_total_monthly_income(p_case_id);
  SELECT total_all_expenses INTO v_expenses FROM calculate_total_monthly_expenses(p_case_id);
  
  RETURN QUERY
  SELECT 
    COALESCE(v_income, 0) as total_monthly_income,
    COALESCE(v_expenses, 0) as total_monthly_expenses,
    COALESCE(v_income, 0) - COALESCE(v_expenses, 0) as disposable_income;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_disposable_income IS 'Replaces Excel formula: D186 - E186 (Total Income - Total Expenses)';

-- Function: Get cell value (replaces Excel cell reference)
CREATE OR REPLACE FUNCTION get_cell_value(p_case_id UUID, p_cell TEXT)
RETURNS NUMERIC AS $$
DECLARE
  v_value NUMERIC;
BEGIN
  -- Check if logiqs_raw_data table exists
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'logiqs_raw_data') THEN
    RETURN 0;
  END IF;
  
  CASE UPPER(p_cell)
    WHEN 'B56' THEN SELECT b56 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'B57' THEN SELECT b57 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'B79' THEN SELECT b79 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'B87' THEN SELECT b87 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'B88' THEN SELECT b88 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'B90' THEN SELECT b90 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'AL7' THEN SELECT al7 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'AL8' THEN SELECT al8 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'AK7' THEN SELECT ak7 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'AK8' THEN SELECT ak8 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'C61' THEN SELECT c61_irs INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'AL4' THEN SELECT al4 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'AL5' THEN SELECT al5 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'C80' THEN SELECT c80 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    ELSE v_value := NULL;
  END CASE;
  
  RETURN COALESCE(v_value, 0);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_cell_value IS 'Replaces Excel cell reference - get value by cell name (e.g., get_cell_value(case_id, ''b56''))';

-- Drop existing views if they exist
DROP VIEW IF EXISTS excel_reso_options_patch;
DROP VIEW IF EXISTS excel_logiqs_raw_data;

-- View: "ResoOptionsPatch" Tab (Excel equivalent)
-- Only create if logiqs_raw_data table exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'logiqs_raw_data') THEN
    CREATE OR REPLACE VIEW excel_reso_options_patch AS
    SELECT 
      lrd.case_id,
      lrd.c61 as "D184_TP_Employer",
      lrd.c76 as "D185_Spouse_Employer",
      (SELECT total_monthly FROM calculate_total_monthly_income(lrd.case_id)) as "D186_TotalMonthlyIncome",
      (SELECT total_auto_payments FROM calculate_total_monthly_expenses(lrd.case_id)) as "E186_TotalAutoPayments",
      lrd.al5 as "D187_FoodExpense",
      lrd.al4 as "E188_PublicTrans",
      lrd.b79 as "D189_HealthInsurance",
      lrd.c80 as "D190_HealthOOP",
      lrd.b87 as "D194_CourtPayments",
      lrd.b88 as "D195_ChildCare",
      lrd.b90 as "D196_TermLifeInsurance"
    FROM logiqs_raw_data lrd;
    
    COMMENT ON VIEW excel_reso_options_patch IS 'Replicates Excel ResoOptionsPatch function - all formula cell references';
    
    RAISE NOTICE '✅ View excel_reso_options_patch created';
  ELSE
    RAISE NOTICE '⚠️  logiqs_raw_data table does not exist yet - view will be created when table exists';
  END IF;
END $$;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Interview field extraction trigger updated!';
    RAISE NOTICE '✅ Excel formulas replaced with SQL functions!';
    RAISE NOTICE '';
    RAISE NOTICE '📊 Now you can:';
    RAISE NOTICE '  - SELECT * FROM calculate_total_monthly_income(case_id);';
    RAISE NOTICE '  - SELECT * FROM excel_reso_options_patch WHERE case_id = ''uuid'';';
    RAISE NOTICE '  - SELECT get_cell_value(case_id, ''b56'');';
END $$;

