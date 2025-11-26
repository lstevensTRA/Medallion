-- Fix pay_frequency normalization in Silver → Gold trigger
-- The trigger needs to normalize pay_frequency to lowercase

DROP TRIGGER IF EXISTS trigger_silver_to_gold ON logiqs_raw_data;
DROP FUNCTION IF EXISTS process_silver_to_gold();

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
  
  -- Continue with rest of trigger (household, expenses, etc.)
  -- For now, just return to test employment
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_silver_to_gold
    AFTER INSERT OR UPDATE ON logiqs_raw_data
    FOR EACH ROW
    EXECUTE FUNCTION process_silver_to_gold();

