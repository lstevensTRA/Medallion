-- ============================================================================
-- Migration: 20250125000005_extract_interview_fields.sql
-- Purpose: Update interview trigger to extract ALL fields from JSONB (expenses, household, employment)
-- Dependencies: 20250125000003_medallion_triggers.sql
-- ============================================================================
-- This replaces the simple trigger that only stored raw JSONB with a comprehensive
-- extraction that maps all interview fields to logiqs_raw_data columns
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
    
    -- Structured JSONB sections
    employment,
    household,
    assets,
    income,
    expenses,
    irs_standards,
    
    -- Employment Section (Taxpayer - Column B)
    b3,  -- clientEmployer
    b4,  -- clientStartWorkingDate
    b5,  -- clientGrossIncome
    b6,  -- clientNetIncome
    b7,  -- clientFrequentlyPaid
    
    -- Employment Section (Spouse - Column C)
    c3,  -- spouseEmployer
    c4,  -- spouseStartWorkingDate
    c5,  -- spouseGrossIncome
    c6,  -- spouseNetIncome
    c7,  -- spouseFrequentlyPaid
    
    -- Household Section (Taxpayer - Column B)
    b10,  -- clientHouseMembers
    b11,  -- clientNextTaxReturn
    b12,  -- clientSpouseClaim
    b13,  -- clientLengthofresidency
    b14,  -- clientOccupancyStatus
    
    -- Household Section (Spouse - Column C)
    c10,  -- spouseHouseMembers
    c11,  -- spouseNextTaxReturn
    c12,  -- spouseSpouseClaim
    c13,  -- spouseLengthofresidency
    c14,  -- spouseOccupancyStatus
    
    -- Assets Section (Column B - Market Values)
    b18,  -- bankAccounts total
    b19,  -- cashOnHand
    b20,  -- investments market value
    b21,  -- lifeInsurance market value
    b22,  -- retirement market value
    b23,  -- realProperty market value
    b24,  -- vehicle1 market value
    b25,  -- vehicle2 market value
    b26,  -- vehicle3 market value
    b27,  -- vehicle4 market value
    b28,  -- personalEffects market value
    b29,  -- otherAssets market value
    
    -- Assets Section (Column D - Loans)
    d20,  -- investments loan
    d21,  -- lifeInsurance loan
    d22,  -- retirement loan
    d23,  -- realProperty loan
    d24,  -- vehicle1 loan
    d25,  -- vehicle2 loan
    d26,  -- vehicle3 loan
    d27,  -- vehicle4 loan
    d28,  -- personalEffects loan
    d29,  -- otherAssets loan
    
    -- Income Section
    b33,  -- taxpayer wages
    b34,  -- taxpayer social security
    b35,  -- taxpayer pension
    b36,  -- spouse wages
    b37,  -- spouse social security
    b38,  -- spouse pension
    b39,  -- dividends/interest
    b40,  -- rental gross
    b41,  -- rental expenses
    b42,  -- distributions
    b43,  -- alimony
    b44,  -- child support
    b45,  -- other income
    b46,  -- additional income 1
    b47,  -- additional income 2
    
    -- Expenses Section - Family Size & Location
    b50,  -- family size under 65
    b51,  -- family size over 65
    b52,  -- state
    b53,  -- county
    
    -- Expenses Section - Food/Clothing/Misc
    b56,  -- food
    b57,  -- housekeeping
    b58,  -- apparel
    b59,  -- personal care
    b60,  -- misc
    
    -- Expenses Section - Housing
    b64,  -- mortgage lien 1
    b65,  -- mortgage lien 2
    b66,  -- rent
    b67,  -- insurance
    b68,  -- property tax
    b69,  -- utilities gas
    b70,  -- utilities electricity
    b71,  -- utilities water
    b72,  -- utilities sewer
    b73,  -- utilities cable
    b74,  -- utilities trash
    b75,  -- utilities phone
    
    -- Expenses Section - Healthcare
    b79,  -- health insurance (TEXT in schema, but we'll store as NUMERIC if possible)
    b80,  -- prescriptions
    b81,  -- copays
    
    -- Expenses Section - Taxes
    b84,  -- taxes
    
    -- Expenses Section - Other Expenses
    b87,  -- court payments
    b88,  -- child care
    b89,  -- whole life insurance
    b90,  -- term life insurance
    
    -- Expenses Section - Transportation (Column AK)
    ak2,  -- vehicle count
    ak4,  -- public transportation
    ak5,  -- auto total
    ak6,  -- auto insurance
    ak7,  -- auto payment 1
    ak8,  -- auto payment 2
    
    -- IRS Standards (Column C)
    c56,  -- IRS food
    c57,  -- IRS housekeeping
    c58,  -- IRS apparel
    c59,  -- IRS personal care
    c60,  -- IRS misc
    c61_irs,  -- IRS food/clothing/misc total
    c61,  -- clientEmployer (formula cell)
    c76,  -- spouseEmployer (formula cell)
    c80,  -- health out of pocket
    
    -- IRS Standards (Column AL)
    al4,  -- public trans
    al5,  -- food (formula cell)
    al7,  -- taxpayer monthly income (formula cell)
    al8,  -- spouse monthly income (formula cell)
    
    -- Store full response
    raw_response,
    extracted_at
  )
  VALUES (
    v_case_uuid,
    NEW.bronze_id,
    
    -- Structured JSONB
    v_employment,
    v_household,
    v_assets,
    v_income,
    v_expenses,
    v_result,
    
    -- Employment (Taxpayer)
    safe_jsonb_text(v_employment, ARRAY['clientEmployer']),
    safe_jsonb_date(v_employment, ARRAY['clientStartWorkingDate']),
    safe_jsonb_decimal(v_employment, ARRAY['clientGrossIncome']),
    safe_jsonb_decimal(v_employment, ARRAY['clientNetIncome']),
    safe_jsonb_text(v_employment, ARRAY['clientFrequentlyPaid']),
    
    -- Employment (Spouse)
    safe_jsonb_text(v_employment, ARRAY['spouseEmployer']),
    safe_jsonb_date(v_employment, ARRAY['spouseStartWorkingDate']),
    safe_jsonb_decimal(v_employment, ARRAY['spouseGrossIncome']),
    safe_jsonb_decimal(v_employment, ARRAY['spouseNetIncome']),
    safe_jsonb_text(v_employment, ARRAY['spouseFrequentlyPaid']),
    
    -- Household (Taxpayer)
    safe_jsonb_text(v_employment, ARRAY['clientHouseMembers']),
    safe_jsonb_text(v_employment, ARRAY['clientNextTaxReturn']),
    safe_jsonb_text(v_employment, ARRAY['clientSpouseClaim']),
    safe_jsonb_text(v_employment, ARRAY['clientLengthofresidency']),
    safe_jsonb_text(v_employment, ARRAY['clientOccupancyStatus']),
    
    -- Household (Spouse)
    safe_jsonb_text(v_employment, ARRAY['spouseHouseMembers']),
    safe_jsonb_text(v_employment, ARRAY['spouseNextTaxReturn']),
    safe_jsonb_text(v_employment, ARRAY['spouseSpouseClaim']),
    safe_jsonb_text(v_employment, ARRAY['spouseLengthofresidency']),
    safe_jsonb_text(v_employment, ARRAY['spouseOccupancyStatus']),
    
    -- Assets (Market Values)
    safe_jsonb_decimal(v_assets, ARRAY['bankAccounts', 'accountsData']),  -- May need to sum array
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
    
    -- Assets (Loans)
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
    
    -- Income
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
    
    -- Expenses - Family Size & Location
    safe_jsonb_text(v_expenses, ARRAY['familySize', 'under65']),
    safe_jsonb_text(v_expenses, ARRAY['familySize', 'over65']),
    safe_jsonb_text(v_expenses, ARRAY['location', 'state']),
    safe_jsonb_text(v_expenses, ARRAY['location', 'county']),
    
    -- Expenses - Food/Clothing/Misc
    safe_jsonb_decimal(v_expenses, ARRAY['foodClothingMisc', 'food']),
    safe_jsonb_decimal(v_expenses, ARRAY['foodClothingMisc', 'housekeeping']),
    safe_jsonb_decimal(v_expenses, ARRAY['foodClothingMisc', 'apparel']),
    safe_jsonb_decimal(v_expenses, ARRAY['foodClothingMisc', 'personalCare']),
    safe_jsonb_decimal(v_expenses, ARRAY['foodClothingMisc', 'misc']),
    
    -- Expenses - Housing
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
    
    -- Expenses - Healthcare (b79 is TEXT in schema, but we extract as decimal for calculation)
    safe_jsonb_decimal(v_expenses, ARRAY['healthcare', 'healthInsurance']),
    safe_jsonb_decimal(v_expenses, ARRAY['healthcare', 'prescriptions']),
    safe_jsonb_decimal(v_expenses, ARRAY['healthcare', 'copays']),
    
    -- Expenses - Taxes
    safe_jsonb_decimal(v_expenses, ARRAY['taxes']),
    
    -- Expenses - Other
    safe_jsonb_decimal(v_raw_data, ARRAY['ExpenseCourtPayments']),
    safe_jsonb_decimal(v_raw_data, ARRAY['ExpenseChildCare']),
    safe_jsonb_decimal(v_raw_data, ARRAY['ExpenseWholeLifeInsurance']),
    safe_jsonb_decimal(v_raw_data, ARRAY['ExpenseTermLifeInsurance']),
    
    -- Expenses - Transportation
    safe_jsonb_text(v_expenses, ARRAY['transportation', 'vehicleCount']),
    safe_jsonb_decimal(v_expenses, ARRAY['transportation', 'publicTransportation']),
    safe_jsonb_decimal(v_raw_data, ARRAY['ExpenseAutoTotal']),
    safe_jsonb_decimal(v_expenses, ARRAY['transportation', 'autoInsurance']),
    safe_jsonb_decimal(v_expenses, ARRAY['transportation', 'autoPayment1']),
    safe_jsonb_decimal(v_expenses, ARRAY['transportation', 'autoPayment2']),
    
    -- IRS Standards
    safe_jsonb_decimal(v_result, ARRAY['Food']),
    safe_jsonb_decimal(v_result, ARRAY['Housekeeping']),
    safe_jsonb_decimal(v_result, ARRAY['Apparel']),
    safe_jsonb_decimal(v_result, ARRAY['PersonalCare']),
    safe_jsonb_decimal(v_result, ARRAY['Misc']),
    safe_jsonb_decimal(v_result, ARRAY['FoodClothingMiscTotal']),
    safe_jsonb_text(v_employment, ARRAY['clientEmployer']),  -- c61 formula cell
    safe_jsonb_text(v_employment, ARRAY['spouseEmployer']),  -- c76 formula cell
    safe_jsonb_decimal(v_result, ARRAY['HealthOutOfPocket']),
    
    -- IRS Standards (AL)
    safe_jsonb_decimal(v_result, ARRAY['PublicTrans']),
    safe_jsonb_decimal(v_expenses, ARRAY['foodClothingMisc', 'food']),  -- al5 formula cell
    safe_jsonb_decimal(v_income, ARRAY['taxpayerIncome', 'wages']),  -- al7 formula cell (monthly)
    safe_jsonb_decimal(v_income, ARRAY['spouseIncome', 'wages']),  -- al8 formula cell (monthly)
    
    -- Full response
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
    -- Update all extracted fields
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

