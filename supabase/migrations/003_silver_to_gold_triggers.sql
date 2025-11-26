-- ============================================================================
-- Migration: 003_silver_to_gold_triggers.sql
-- Purpose: Create SQL triggers to automatically transform Silver → Gold
-- Dependencies: 
--   - 002_bronze_to_silver_triggers.sql (Silver tables populated)
--   - 20250127000014_normalized_schema_v2.sql (Gold tables: employment_information, household_information)
-- Author: Tax Resolution Medallion Architecture
-- Date: 2024-11-21
-- ============================================================================
-- Triggers Created:
--   - trigger_silver_logiqs_to_gold → employment_information, household_information
--   - trigger_silver_income_to_gold → Updates employment_information with WI data
-- ============================================================================
-- Benefits:
--   - Semantic column naming (no more Excel cell references!)
--   - Normalized business entities
--   - Business logic functions (calculate income, SE tax, etc.)
--   - Query-friendly structure
-- ============================================================================
-- Rollback:
--   DROP TRIGGER IF EXISTS trigger_silver_logiqs_to_gold ON logiqs_raw_data;
--   DROP TRIGGER IF EXISTS trigger_silver_income_to_gold ON income_documents;
--   DROP FUNCTION IF EXISTS process_logiqs_to_gold();
--   DROP FUNCTION IF EXISTS process_income_to_gold();
--   DROP FUNCTION IF EXISTS calculate_total_monthly_income(UUID);
--   DROP FUNCTION IF EXISTS calculate_se_tax(UUID);
--   DROP FUNCTION IF EXISTS calculate_disposable_income(UUID);
-- ============================================================================

-- ============================================================================
-- TRIGGER 1: LOGIQS_RAW_DATA → GOLD (Employment & Household)
-- ============================================================================

CREATE OR REPLACE FUNCTION process_logiqs_to_gold()
RETURNS TRIGGER AS $$
DECLARE
  v_employment JSONB;
  v_household JSONB;
  v_assets JSONB;
  v_income JSONB;
  v_expenses JSONB;
BEGIN
  -- Extract structured sections from Silver logiqs_raw_data
  v_employment := NEW.employment;
  v_household := NEW.household;
  v_assets := NEW.assets;
  v_income := NEW.income;
  v_expenses := NEW.expenses;
  
  BEGIN
    -- ========================================================================
    -- EMPLOYMENT INFORMATION (Taxpayer)
    -- ========================================================================
    
    -- Insert or update taxpayer employment
    INSERT INTO employment_information (
      case_id,
      person_type,
      
      -- Employer details
      employer_name,
      employer_address,
      employer_phone,
      
      -- Income details
      gross_monthly_income,
      pay_frequency,
      
      -- Employment status
      employment_status,
      occupation,
      employment_start_date,
      
      -- Metadata
      created_at,
      updated_at
    )
    VALUES (
      NEW.case_id,
      'taxpayer',
      
      -- Employer details from employment JSONB
      -- Excel mapping: B3 → employer_name
      COALESCE(
        v_employment->>'clientEmployer',
        v_employment->>'b3',  -- Excel cell reference
        v_employment->>'taxpayer_employer'
      ),
      
      COALESCE(
        v_employment->>'clientEmployerAddress',
        v_employment->>'employer_address'
      ),
      
      COALESCE(
        v_employment->>'clientEmployerPhone',
        v_employment->>'employer_phone'
      ),
      
      -- Income details
      -- Excel mapping: AL7 → gross_monthly_income
      parse_decimal(COALESCE(
        v_employment->>'clientGrossIncome',
        v_employment->>'al7',  -- Excel cell reference
        v_employment->>'taxpayer_gross_income'
      )),
      
      COALESCE(
        v_employment->>'clientPayFrequency',
        v_employment->>'pay_frequency',
        'Monthly'  -- Default
      ),
      
      -- Employment status
      COALESCE(
        v_employment->>'clientEmploymentStatus',
        v_employment->>'employment_status',
        'Employed'  -- Default
      ),
      
      COALESCE(
        v_employment->>'clientOccupation',
        v_employment->>'occupation'
      ),
      
      parse_date(COALESCE(
        v_employment->>'clientEmploymentStartDate',
        v_employment->>'start_date'
      )),
      
      -- Metadata
      NOW(),
      NOW()
    )
    ON CONFLICT (case_id, person_type) DO UPDATE SET
      employer_name = EXCLUDED.employer_name,
      employer_address = EXCLUDED.employer_address,
      employer_phone = EXCLUDED.employer_phone,
      gross_monthly_income = EXCLUDED.gross_monthly_income,
      pay_frequency = EXCLUDED.pay_frequency,
      employment_status = EXCLUDED.employment_status,
      occupation = EXCLUDED.occupation,
      employment_start_date = EXCLUDED.employment_start_date,
      updated_at = NOW();
    
    -- ========================================================================
    -- EMPLOYMENT INFORMATION (Spouse)
    -- ========================================================================
    
    -- Only insert spouse if spouse data exists
    IF v_employment ? 'spouseEmployer' OR v_employment ? 'c3' THEN
      INSERT INTO employment_information (
        case_id,
        person_type,
        
        -- Employer details
        employer_name,
        employer_address,
        employer_phone,
        
        -- Income details
        gross_monthly_income,
        pay_frequency,
        
        -- Employment status
        employment_status,
        occupation,
        employment_start_date,
        
        -- Metadata
        created_at,
        updated_at
      )
      VALUES (
        NEW.case_id,
        'spouse',
        
        -- Spouse employer details
        -- Excel mapping: C3 → spouse employer_name
        COALESCE(
          v_employment->>'spouseEmployer',
          v_employment->>'c3',  -- Excel cell reference
          v_employment->>'spouse_employer'
        ),
        
        COALESCE(
          v_employment->>'spouseEmployerAddress',
          v_employment->>'spouse_employer_address'
        ),
        
        COALESCE(
          v_employment->>'spouseEmployerPhone',
          v_employment->>'spouse_employer_phone'
        ),
        
        -- Spouse income
        -- Excel mapping: AL8 → spouse gross_monthly_income
        parse_decimal(COALESCE(
          v_employment->>'spouseGrossIncome',
          v_employment->>'al8',  -- Excel cell reference
          v_employment->>'spouse_gross_income'
        )),
        
        COALESCE(
          v_employment->>'spousePayFrequency',
          v_employment->>'spouse_pay_frequency',
          'Monthly'
        ),
        
        -- Spouse employment status
        COALESCE(
          v_employment->>'spouseEmploymentStatus',
          v_employment->>'spouse_employment_status',
          'Employed'
        ),
        
        COALESCE(
          v_employment->>'spouseOccupation',
          v_employment->>'spouse_occupation'
        ),
        
        parse_date(COALESCE(
          v_employment->>'spouseEmploymentStartDate',
          v_employment->>'spouse_start_date'
        )),
        
        -- Metadata
        NOW(),
        NOW()
      )
      ON CONFLICT (case_id, person_type) DO UPDATE SET
        employer_name = EXCLUDED.employer_name,
        employer_address = EXCLUDED.employer_address,
        employer_phone = EXCLUDED.employer_phone,
        gross_monthly_income = EXCLUDED.gross_monthly_income,
        pay_frequency = EXCLUDED.pay_frequency,
        employment_status = EXCLUDED.employment_status,
        occupation = EXCLUDED.occupation,
        employment_start_date = EXCLUDED.employment_start_date,
        updated_at = NOW();
    END IF;
    
    -- ========================================================================
    -- HOUSEHOLD INFORMATION
    -- ========================================================================
    
    INSERT INTO household_information (
      case_id,
      
      -- Taxpayer details
      taxpayer_name,
      taxpayer_ssn,
      taxpayer_dob,
      taxpayer_phone,
      taxpayer_email,
      
      -- Spouse details
      spouse_name,
      spouse_ssn,
      spouse_dob,
      
      -- Household details
      filing_status,
      number_of_dependents,
      household_size,
      marital_status,
      
      -- Address
      street_address,
      city,
      state,
      zip_code,
      
      -- Metadata
      created_at,
      updated_at
    )
    VALUES (
      NEW.case_id,
      
      -- Taxpayer details
      COALESCE(
        v_household->>'taxpayerName',
        v_household->>'clientName',
        v_household->>'name'
      ),
      
      COALESCE(
        v_household->>'taxpayerSSN',
        v_household->>'clientSSN',
        v_household->>'ssn'
      ),
      
      parse_date(COALESCE(
        v_household->>'taxpayerDOB',
        v_household->>'clientDOB',
        v_household->>'dob'
      )),
      
      COALESCE(
        v_household->>'taxpayerPhone',
        v_household->>'clientPhone',
        v_household->>'phone'
      ),
      
      COALESCE(
        v_household->>'taxpayerEmail',
        v_household->>'clientEmail',
        v_household->>'email'
      ),
      
      -- Spouse details
      COALESCE(
        v_household->>'spouseName',
        v_household->>'spouse_name'
      ),
      
      COALESCE(
        v_household->>'spouseSSN',
        v_household->>'spouse_ssn'
      ),
      
      parse_date(COALESCE(
        v_household->>'spouseDOB',
        v_household->>'spouse_dob'
      )),
      
      -- Household details
      COALESCE(
        v_household->>'filingStatus',
        v_household->>'filing_status',
        'Single'  -- Default
      ),
      
      COALESCE(
        (v_household->>'numberOfDependents')::INTEGER,
        (v_household->>'dependents')::INTEGER,
        0
      ),
      
      COALESCE(
        (v_household->>'householdSize')::INTEGER,
        (v_household->>'household_size')::INTEGER,
        1
      ),
      
      COALESCE(
        v_household->>'maritalStatus',
        v_household->>'marital_status',
        'Single'
      ),
      
      -- Address
      COALESCE(
        v_household->>'streetAddress',
        v_household->>'address',
        v_household->>'street'
      ),
      
      COALESCE(
        v_household->>'city'
      ),
      
      COALESCE(
        v_household->>'state'
      ),
      
      COALESCE(
        v_household->>'zipCode',
        v_household->>'zip'
      ),
      
      -- Metadata
      NOW(),
      NOW()
    )
    ON CONFLICT (case_id) DO UPDATE SET
      taxpayer_name = EXCLUDED.taxpayer_name,
      taxpayer_ssn = EXCLUDED.taxpayer_ssn,
      taxpayer_dob = EXCLUDED.taxpayer_dob,
      taxpayer_phone = EXCLUDED.taxpayer_phone,
      taxpayer_email = EXCLUDED.taxpayer_email,
      spouse_name = EXCLUDED.spouse_name,
      spouse_ssn = EXCLUDED.spouse_ssn,
      spouse_dob = EXCLUDED.spouse_dob,
      filing_status = EXCLUDED.filing_status,
      number_of_dependents = EXCLUDED.number_of_dependents,
      household_size = EXCLUDED.household_size,
      marital_status = EXCLUDED.marital_status,
      street_address = EXCLUDED.street_address,
      city = EXCLUDED.city,
      state = EXCLUDED.state,
      zip_code = EXCLUDED.zip_code,
      updated_at = NOW();
    
    RAISE NOTICE 'Processed logiqs_raw_data to Gold for case %', NEW.case_id;
    
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Failed to process logiqs_raw_data to Gold for case %: %', NEW.case_id, SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trigger_silver_logiqs_to_gold
  AFTER INSERT OR UPDATE ON logiqs_raw_data
  FOR EACH ROW
  EXECUTE FUNCTION process_logiqs_to_gold();

COMMENT ON FUNCTION process_logiqs_to_gold IS 'Transform Silver logiqs_raw_data to Gold employment_information and household_information. Replaces Excel cell references with semantic column names.';

-- ============================================================================
-- TRIGGER 2: INCOME_DOCUMENTS → GOLD (Update Employment with WI Data)
-- ============================================================================

CREATE OR REPLACE FUNCTION process_income_to_gold()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
  v_total_w2_income NUMERIC;
  v_total_1099_income NUMERIC;
  v_is_self_employed BOOLEAN;
BEGIN
  -- Get case UUID
  v_case_uuid := NEW.case_id;
  
  BEGIN
    -- Calculate totals for this case
    SELECT 
      COALESCE(SUM(gross_amount) FILTER (WHERE document_type LIKE 'W-2%'), 0),
      COALESCE(SUM(gross_amount) FILTER (WHERE document_type LIKE '1099%'), 0),
      BOOL_OR(is_self_employment)
    INTO 
      v_total_w2_income,
      v_total_1099_income,
      v_is_self_employed
    FROM income_documents
    WHERE case_id = v_case_uuid
      AND tax_year = NEW.tax_year;
    
    -- Update employment_information with calculated totals
    UPDATE employment_information
    SET 
      is_self_employed = v_is_self_employed,
      updated_at = NOW()
    WHERE case_id = v_case_uuid
      AND person_type = 'taxpayer';
    
    RAISE NOTICE 'Updated Gold employment for case %: W-2=$%, 1099=$%, SE=%', 
      v_case_uuid, v_total_w2_income, v_total_1099_income, v_is_self_employed;
    
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Failed to update Gold employment for case %: %', v_case_uuid, SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trigger_silver_income_to_gold
  AFTER INSERT OR UPDATE ON income_documents
  FOR EACH ROW
  EXECUTE FUNCTION process_income_to_gold();

COMMENT ON FUNCTION process_income_to_gold IS 'Update Gold employment_information when income_documents are added. Calculates W-2/1099 totals and SE status.';

-- ============================================================================
-- BUSINESS LOGIC FUNCTIONS
-- ============================================================================

-- Function: Calculate total monthly income for a case
CREATE OR REPLACE FUNCTION calculate_total_monthly_income(p_case_id UUID)
RETURNS TABLE (
  taxpayer_income NUMERIC,
  spouse_income NUMERIC,
  total_income NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(SUM(gross_monthly_income) FILTER (WHERE person_type = 'taxpayer'), 0) as taxpayer_income,
    COALESCE(SUM(gross_monthly_income) FILTER (WHERE person_type = 'spouse'), 0) as spouse_income,
    COALESCE(SUM(gross_monthly_income), 0) as total_income
  FROM employment_information
  WHERE case_id = p_case_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_total_monthly_income IS 'Calculate total monthly income for taxpayer, spouse, and combined';

-- Function: Calculate self-employment tax
CREATE OR REPLACE FUNCTION calculate_se_tax(p_case_id UUID, p_tax_year TEXT)
RETURNS NUMERIC AS $$
DECLARE
  v_se_income NUMERIC;
  v_se_tax NUMERIC;
BEGIN
  -- Get total self-employment income
  SELECT COALESCE(SUM(gross_amount), 0)
  INTO v_se_income
  FROM income_documents
  WHERE case_id = p_case_id
    AND tax_year = p_tax_year
    AND is_self_employment = true;
  
  -- Calculate SE tax (15.3% on 92.35% of SE income)
  v_se_tax := v_se_income * 0.9235 * 0.153;
  
  RETURN ROUND(v_se_tax, 2);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_se_tax IS 'Calculate self-employment tax: 15.3% on 92.35% of SE income';

-- Function: Calculate account balance for a tax year
CREATE OR REPLACE FUNCTION calculate_account_balance(p_case_id UUID, p_tax_year TEXT)
RETURNS NUMERIC AS $$
DECLARE
  v_balance NUMERIC;
BEGIN
  -- Sum all balance-affecting transactions
  SELECT COALESCE(
    SUM(
      CASE 
        WHEN is_payment = true THEN -amount
        WHEN is_penalty = true OR is_interest = true THEN amount
        ELSE amount
      END
    ),
    0
  )
  INTO v_balance
  FROM account_activity aa
  JOIN tax_years ty ON aa.tax_year_id = ty.id
  JOIN cases c ON ty.case_id = c.id
  WHERE c.id = p_case_id
    AND ty.tax_year = p_tax_year
    AND aa.affects_balance = true;
  
  RETURN ROUND(v_balance, 2);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_account_balance IS 'Calculate current account balance for a tax year (payments negative, penalties/interest positive)';

-- Function: Calculate CSED date with tolling
CREATE OR REPLACE FUNCTION calculate_csed_date(p_case_id UUID, p_tax_year TEXT)
RETURNS TABLE (
  base_csed_date DATE,
  total_toll_days INTEGER,
  final_csed_date DATE,
  csed_status TEXT
) AS $$
DECLARE
  v_return_filed_date DATE;
  v_base_csed DATE;
  v_toll_days INTEGER;
  v_final_csed DATE;
  v_status TEXT;
BEGIN
  -- Get return filed date from tax_years
  SELECT 
    COALESCE(
      (SELECT transaction_date 
       FROM account_activity aa
       WHERE aa.tax_year_id = ty.id 
         AND aa.transaction_code = '150'
       ORDER BY transaction_date ASC
       LIMIT 1
      ),
      CURRENT_DATE
    )
  INTO v_return_filed_date
  FROM tax_years ty
  JOIN cases c ON ty.case_id = c.id
  WHERE c.id = p_case_id
    AND ty.tax_year = p_tax_year;
  
  -- Base CSED is 10 years from return filed date
  v_base_csed := v_return_filed_date + INTERVAL '10 years';
  
  -- Calculate total toll days
  SELECT COALESCE(SUM(toll_days), 0)
  INTO v_toll_days
  FROM csed_tolling_events
  WHERE case_id = p_case_id
    AND tax_year = p_tax_year;
  
  -- Final CSED with tolling
  v_final_csed := v_base_csed + (v_toll_days || ' days')::INTERVAL;
  
  -- Determine status
  IF v_final_csed < CURRENT_DATE THEN
    v_status := 'EXPIRED';
  ELSIF v_final_csed < CURRENT_DATE + INTERVAL '1 year' THEN
    v_status := 'EXPIRING_SOON';
  ELSE
    v_status := 'ACTIVE';
  END IF;
  
  RETURN QUERY SELECT v_base_csed, v_toll_days, v_final_csed, v_status;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_csed_date IS 'Calculate CSED date with tolling events. Base is 10 years from return filed (code 150), plus toll days.';

-- Function: Calculate disposable income
CREATE OR REPLACE FUNCTION calculate_disposable_income(p_case_id UUID)
RETURNS TABLE (
  total_monthly_income NUMERIC,
  total_monthly_expenses NUMERIC,
  disposable_income NUMERIC
) AS $$
DECLARE
  v_income NUMERIC;
  v_expenses NUMERIC;
  v_disposable NUMERIC;
BEGIN
  -- Get total monthly income
  SELECT 
    COALESCE((calculate_total_monthly_income(p_case_id)).total_income, 0)
  INTO v_income;
  
  -- Get total monthly expenses from logiqs_raw_data
  -- Note: This is a simplified version - you'll need to expand based on your expense structure
  SELECT 
    COALESCE(
      parse_decimal(lrd.expenses->>'totalMonthlyExpenses'),
      0
    )
  INTO v_expenses
  FROM logiqs_raw_data lrd
  WHERE lrd.case_id = p_case_id;
  
  -- Calculate disposable income
  v_disposable := v_income - v_expenses;
  
  RETURN QUERY SELECT v_income, v_expenses, v_disposable;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_disposable_income IS 'Calculate disposable income: total monthly income - total monthly expenses';

-- Function: Get case summary (combines multiple calculations)
CREATE OR REPLACE FUNCTION get_case_summary(p_case_id UUID)
RETURNS TABLE (
  case_number TEXT,
  taxpayer_name TEXT,
  filing_status TEXT,
  total_monthly_income NUMERIC,
  disposable_income NUMERIC,
  is_self_employed BOOLEAN,
  active_tax_years INTEGER,
  total_balance NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.case_number,
    h.taxpayer_name,
    h.filing_status,
    (calculate_total_monthly_income(p_case_id)).total_income,
    (calculate_disposable_income(p_case_id)).disposable_income,
    (SELECT is_self_employed FROM employment_information WHERE case_id = p_case_id AND person_type = 'taxpayer'),
    (SELECT COUNT(DISTINCT tax_year) FROM tax_years WHERE case_id = p_case_id)::INTEGER,
    (SELECT COALESCE(SUM(
      CASE 
        WHEN aa.is_payment = true THEN -aa.amount
        ELSE aa.amount
      END
    ), 0)
     FROM account_activity aa
     JOIN tax_years ty ON aa.tax_year_id = ty.id
     WHERE ty.case_id = p_case_id
       AND aa.affects_balance = true
    )
  FROM cases c
  LEFT JOIN household_information h ON h.case_id = c.id
  WHERE c.id = p_case_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_case_summary IS 'Get comprehensive case summary with calculated fields';

-- ============================================================================
-- GOLD LAYER VIEWS
-- ============================================================================

-- View: Complete employment picture
CREATE OR REPLACE VIEW v_employment_complete AS
SELECT 
  e.*,
  c.case_number,
  h.taxpayer_name,
  h.spouse_name,
  -- Calculate annual income
  e.gross_monthly_income * 12 as gross_annual_income,
  -- Check if income documents exist
  (SELECT COUNT(*) FROM income_documents i WHERE i.case_id = e.case_id) as income_document_count
FROM employment_information e
JOIN cases c ON e.case_id = c.id
LEFT JOIN household_information h ON e.case_id = h.case_id;

COMMENT ON VIEW v_employment_complete IS 'Complete employment information with case details and calculated fields';

-- View: Household summary
CREATE OR REPLACE VIEW v_household_summary AS
SELECT 
  h.*,
  c.case_number,
  c.status as case_status,
  (calculate_total_monthly_income(h.case_id)).total_income as total_monthly_income,
  (SELECT COUNT(*) FROM tax_years WHERE case_id = h.case_id) as tax_year_count
FROM household_information h
JOIN cases c ON h.case_id = c.id;

COMMENT ON VIEW v_household_summary IS 'Household information with case details and calculated totals';

-- ============================================================================
-- DATA QUALITY VIEWS
-- ============================================================================

-- View: Silver → Gold health
CREATE OR REPLACE VIEW silver_gold_health AS
SELECT 
  'Employment' as entity_type,
  (SELECT COUNT(*) FROM logiqs_raw_data WHERE employment IS NOT NULL) as silver_records,
  (SELECT COUNT(*) FROM employment_information) as gold_records,
  (SELECT COUNT(DISTINCT case_id) FROM employment_information) as cases_in_gold
UNION ALL
SELECT 
  'Household' as entity_type,
  (SELECT COUNT(*) FROM logiqs_raw_data WHERE household IS NOT NULL) as silver_records,
  (SELECT COUNT(*) FROM household_information) as gold_records,
  (SELECT COUNT(DISTINCT case_id) FROM household_information) as cases_in_gold;

COMMENT ON VIEW silver_gold_health IS 'Monitor Silver → Gold data flow health';

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
  trigger_count INTEGER;
  function_count INTEGER;
BEGIN
  -- Check triggers
  SELECT COUNT(*) INTO trigger_count
  FROM information_schema.triggers
  WHERE trigger_name IN (
    'trigger_silver_logiqs_to_gold',
    'trigger_silver_income_to_gold'
  );
  
  IF trigger_count = 2 THEN
    RAISE NOTICE '✅ Silver → Gold triggers created successfully: 2/2 triggers';
  ELSE
    RAISE WARNING '⚠️  Expected 2 triggers, found %', trigger_count;
  END IF;
  
  -- Check business functions
  SELECT COUNT(*) INTO function_count
  FROM pg_proc
  WHERE proname IN (
    'calculate_total_monthly_income',
    'calculate_se_tax',
    'calculate_account_balance',
    'calculate_csed_date',
    'calculate_disposable_income',
    'get_case_summary'
  );
  
  IF function_count = 6 THEN
    RAISE NOTICE '✅ Business logic functions created successfully: 6/6 functions';
  ELSE
    RAISE WARNING '⚠️  Expected 6 business functions, found %', function_count;
  END IF;
END $$;

-- ============================================================================
-- Migration Complete
-- ============================================================================
-- What Just Happened:
-- 1. Created 2 Silver → Gold trigger functions
-- 2. Created 2 triggers (automatic Silver → Gold transformation)
-- 3. Created 6 business logic functions
-- 4. Created 2 Gold layer views
-- 5. Created 1 data quality view
--
-- Result: 
-- - Excel cell references (b3, al7, c3, al8) → Semantic column names
-- - logiqs_raw_data JSONB → Normalized tables (employment_information, household_information)
-- - Business logic centralized in database functions
-- - Query-friendly Gold layer for reporting
--
-- Next Steps:
-- 1. Apply this migration: supabase db push
-- 2. Test with sample data
-- 3. Phase 6: Dagster orchestration
-- 4. Phase 7: Testing
-- 5. Phase 8: Deployment
-- ============================================================================

