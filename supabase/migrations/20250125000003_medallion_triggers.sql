-- ============================================================================
-- Migration: 20250125000003_medallion_triggers.sql
-- Purpose: Bronze → Silver → Gold Triggers for Medallion Architecture
-- Dependencies: 20250125000002_complete_medallion_schema.sql
-- ============================================================================
-- This creates:
-- 1. Helper functions (parse_year, parse_decimal, ensure_case, ensure_tax_year)
-- 2. Bronze → Silver triggers (AT, WI, TRT, Interview)
-- 3. Silver → Gold triggers (logiqs → employment, household, etc.)
-- ============================================================================

-- ============================================================================
-- PART 1: HELPER FUNCTIONS
-- ============================================================================

-- Parse year from various string formats
CREATE OR REPLACE FUNCTION parse_year(year_str TEXT)
RETURNS INTEGER AS $$
BEGIN
  IF year_str IS NULL OR year_str = '' THEN
    RETURN NULL;
  END IF;
  
  -- Extract year from "2023", "23", "Tax Year 2023", etc.
  RETURN CAST(regexp_replace(year_str, '[^0-9]', '', 'g') AS INTEGER);
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Parse decimal from string (handles "$1,234.56", "1234.56", etc.)
CREATE OR REPLACE FUNCTION parse_decimal(decimal_str TEXT)
RETURNS NUMERIC AS $$
BEGIN
  IF decimal_str IS NULL OR decimal_str = '' THEN
    RETURN NULL;
  END IF;
  
  -- Remove $, commas, spaces
  RETURN CAST(regexp_replace(decimal_str, '[$,\s]', '', 'g') AS NUMERIC);
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Parse date from various formats
CREATE OR REPLACE FUNCTION parse_date(date_str TEXT)
RETURNS DATE AS $$
BEGIN
  IF date_str IS NULL OR date_str = '' THEN
    RETURN NULL;
  END IF;
  
  RETURN CAST(date_str AS DATE);
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Ensure case exists (get UUID from case_id TEXT)
CREATE OR REPLACE FUNCTION ensure_case(p_case_id TEXT)
RETURNS UUID AS $$
DECLARE
  v_case_uuid UUID;
BEGIN
  -- Try to find existing case by case_number (assuming case_id is case_number)
  SELECT id INTO v_case_uuid
  FROM cases
  WHERE case_number = p_case_id;
  
  -- If not found, create a minimal case record
  IF v_case_uuid IS NULL THEN
    INSERT INTO cases (case_number, status_code)
    VALUES (p_case_id, 'NEW')
    RETURNING id INTO v_case_uuid;
  END IF;
  
  RETURN v_case_uuid;
END;
$$ LANGUAGE plpgsql;

-- Ensure tax_year exists for a case
CREATE OR REPLACE FUNCTION ensure_tax_year(
  p_case_uuid UUID,
  p_year INTEGER
)
RETURNS UUID AS $$
DECLARE
  v_tax_year_uuid UUID;
BEGIN
  -- Try to find existing tax_year
  SELECT id INTO v_tax_year_uuid
  FROM tax_years
  WHERE case_id = p_case_uuid
    AND year = p_year;
  
  -- If not found, create minimal tax_year record
  IF v_tax_year_uuid IS NULL THEN
    INSERT INTO tax_years (case_id, year)
    VALUES (p_case_uuid, p_year)
    RETURNING id INTO v_tax_year_uuid;
  END IF;
  
  RETURN v_tax_year_uuid;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION parse_year IS 'Extract year as integer from various string formats';
COMMENT ON FUNCTION parse_decimal IS 'Parse decimal from strings with currency symbols and commas';
COMMENT ON FUNCTION parse_date IS 'Parse date from various string formats';
COMMENT ON FUNCTION ensure_case IS 'Get or create case UUID from case_id TEXT';
COMMENT ON FUNCTION ensure_tax_year IS 'Get or create tax_year UUID for a case and year';

-- ============================================================================
-- PART 2: BRONZE → SILVER TRIGGERS
-- ============================================================================

-- Trigger 1: Bronze AT → Silver (tax_years, account_activity)
CREATE OR REPLACE FUNCTION process_bronze_at()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
  v_tax_year_uuid UUID;
  v_record JSONB;
  v_transaction JSONB;
  v_year INTEGER;
  v_transaction_code TEXT;
  v_at_rule RECORD;
BEGIN
  -- Get or create case UUID
  v_case_uuid := ensure_case(NEW.case_id);
  
  -- Process AT records (handle "at_records" array from TiParser)
  FOR v_record IN 
    SELECT * FROM jsonb_array_elements(
      COALESCE(
        NEW.raw_response->'at_records',  -- TiParser uses "at_records"
        NEW.raw_response->'records',
        NEW.raw_response->'data',
        '[]'::jsonb
      )
    )
  LOOP
    -- Extract tax year
    v_year := parse_year(COALESCE(
      v_record->>'tax_year',
      v_record->>'year',
      v_record->>'period'
    ));
    
    IF v_year IS NOT NULL THEN
      -- Get or create tax_year
      v_tax_year_uuid := ensure_tax_year(v_case_uuid, v_year);
      
      -- Update tax_years with extracted data
      UPDATE tax_years
      SET
        return_filed = CASE 
          WHEN UPPER(COALESCE(v_record->>'return_filed', v_record->>'filed')) IN ('YES', 'FILED', 'TRUE') THEN TRUE
          WHEN UPPER(COALESCE(v_record->>'return_filed', v_record->>'filed')) IN ('NO', 'UNFILED', 'FALSE') THEN FALSE
          ELSE return_filed
        END,
        filing_status = COALESCE(v_record->>'filing_status', v_record->>'FilingStatus', filing_status),
        calculated_agi = COALESCE(
          parse_decimal(COALESCE(
            v_record->>'adjusted_gross_income',
            v_record->>'agi',
            v_record->>'AGI'
          )),
          calculated_agi
        ),
        taxable_income = COALESCE(
          parse_decimal(COALESCE(
            v_record->>'taxable_income',
            v_record->>'taxableIncome'
          )),
          taxable_income
        ),
        calculated_tax_liability = COALESCE(
          parse_decimal(COALESCE(
            v_record->>'tax_per_return',
            v_record->>'TaxPerReturn'
          )),
          calculated_tax_liability
        ),
        calculated_account_balance = COALESCE(
          parse_decimal(COALESCE(
            v_record->>'account_balance',
            v_record->>'accountBalance'
          )),
          calculated_account_balance
        ),
        bronze_id = NEW.bronze_id,  -- Link to Bronze source
        updated_at = NOW()
      WHERE id = v_tax_year_uuid;
      
      -- Process transactions
      FOR v_transaction IN 
        SELECT * FROM jsonb_array_elements(
          COALESCE(
            v_record->'transactions',
            '[]'::jsonb
          )
        )
      LOOP
        v_transaction_code := COALESCE(
          v_transaction->>'code',
          v_transaction->>'transaction_code'
        );
        
        -- Look up AT transaction rule for enrichment
        SELECT * INTO v_at_rule
        FROM at_transaction_rules
        WHERE code = v_transaction_code
        LIMIT 1;
        
        -- Insert into account_activity
        INSERT INTO account_activity (
          tax_year_id,
          activity_date,
          irs_transaction_code,
          explanation,
          amount,
          calculated_transaction_type,
          affects_balance,
          affects_csed,
          indicates_collection_action,
          bronze_id
        )
        VALUES (
          v_tax_year_uuid,
          parse_date(COALESCE(
            v_transaction->>'date',
            v_transaction->>'transaction_date'
          )),
          v_transaction_code,
          COALESCE(
            v_transaction->>'description',
            v_transaction->>'explanation'
          ),
          parse_decimal(COALESCE(
            v_transaction->>'amount',
            v_transaction->>'Amount'
          )),
          COALESCE(v_at_rule.transaction_type, 'Unknown'),
          COALESCE(v_at_rule.affects_balance, FALSE),
          COALESCE(v_at_rule.affects_csed, FALSE),
          COALESCE(v_at_rule.indicates_collection_action, FALSE),
          NEW.bronze_id  -- Link to Bronze source
        )
        ON CONFLICT DO NOTHING;
      END LOOP;
    END IF;
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_bronze_at_to_silver ON bronze_at_raw;
CREATE TRIGGER trigger_bronze_at_to_silver
    AFTER INSERT ON bronze_at_raw
    FOR EACH ROW
    EXECUTE FUNCTION process_bronze_at();

-- Trigger 2: Bronze WI → Silver (income_documents)
CREATE OR REPLACE FUNCTION process_bronze_wi()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
  v_tax_year_uuid UUID;
  v_form JSONB;
  v_year INTEGER;
  v_form_type TEXT;
  v_wi_rule RECORD;
BEGIN
  -- Get or create case UUID
  v_case_uuid := ensure_case(NEW.case_id);
  
  -- Process WI forms (handle "forms" array from TiParser)
  FOR v_form IN 
    SELECT * FROM jsonb_array_elements(
      COALESCE(
        NEW.raw_response->'forms',
        NEW.raw_response->'data',
        '[]'::jsonb
      )
    )
  LOOP
    v_year := parse_year(COALESCE(
      v_form->>'Year',
      v_form->>'year',
      v_form->>'tax_year'
    ));
    
    IF v_year IS NOT NULL THEN
      -- Get or create tax_year
      v_tax_year_uuid := ensure_tax_year(v_case_uuid, v_year);
      
      v_form_type := UPPER(TRIM(COALESCE(
        v_form->>'Form',
        v_form->>'form',
        v_form->>'form_type',
        v_form->>'document_type'
      )));
      
      -- Look up WI type rule for enrichment
      SELECT * INTO v_wi_rule
      FROM wi_type_rules
      WHERE form_code = v_form_type
      LIMIT 1;
      
      -- Insert into income_documents
      INSERT INTO income_documents (
        tax_year_id,
        document_type,
        gross_amount,
        federal_withholding,
        issuer_name,
        issuer_ein,
        recipient_name,
        recipient_ssn,
        calculated_category,
        is_self_employment,
        bronze_id
      )
      VALUES (
        v_tax_year_uuid,
        v_form_type,
        parse_decimal(COALESCE(
          v_form->>'Income',
          v_form->>'income',
          v_form->>'gross_amount',
          v_form->>'amount'
        )),
        parse_decimal(COALESCE(
          v_form->>'Withholding',
          v_form->>'withholding',
          v_form->>'federal_withholding'
        )),
        COALESCE(
          v_form->'Issuer'->>'Name',
          v_form->'Issuer'->>'name',
          v_form->>'issuer_name'
        ),
        COALESCE(
          v_form->'Issuer'->>'EIN',
          v_form->'Issuer'->>'ein',
          v_form->>'issuer_ein'
        ),
        COALESCE(
          v_form->'Recipient'->>'Name',
          v_form->'Recipient'->>'name',
          v_form->>'recipient_name'
        ),
        COALESCE(
          v_form->'Recipient'->>'SSN',
          v_form->'Recipient'->>'ssn',
          v_form->>'recipient_ssn'
        ),
        COALESCE(v_wi_rule.category, 'Unknown'),
        COALESCE(v_wi_rule.is_self_employment, FALSE),
        NEW.bronze_id  -- Link to Bronze source
      )
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_bronze_wi_to_silver ON bronze_wi_raw;
CREATE TRIGGER trigger_bronze_wi_to_silver
    AFTER INSERT ON bronze_wi_raw
    FOR EACH ROW
    EXECUTE FUNCTION process_bronze_wi();

-- Trigger 3: Bronze Interview → Silver (logiqs_raw_data)
CREATE OR REPLACE FUNCTION process_bronze_interview()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
BEGIN
  -- Get or create case UUID
  v_case_uuid := ensure_case(NEW.case_id);
  
  -- Store interview data in logiqs_raw_data
  INSERT INTO logiqs_raw_data (
    case_id,
    bronze_id,
    raw_response,
    extracted_at
  )
  VALUES (
    v_case_uuid,
    NEW.bronze_id,
    NEW.raw_response,
    NOW()
  )
  ON CONFLICT (case_id) DO UPDATE SET
    raw_response = NEW.raw_response,
    bronze_id = NEW.bronze_id,
    extracted_at = NOW(),
    updated_at = NOW();
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_bronze_interview_to_silver ON bronze_interview_raw;
CREATE TRIGGER trigger_bronze_interview_to_silver
    AFTER INSERT ON bronze_interview_raw
    FOR EACH ROW
    EXECUTE FUNCTION process_bronze_interview();

COMMENT ON FUNCTION process_bronze_at IS 'Extract AT data from Bronze JSONB into Silver typed tables';
COMMENT ON FUNCTION process_bronze_wi IS 'Extract WI data from Bronze JSONB into Silver typed tables';
COMMENT ON FUNCTION process_bronze_interview IS 'Store interview data in Silver layer (logiqs_raw_data)';

-- ============================================================================
-- PART 3: SILVER → GOLD TRIGGERS (for future implementation)
-- ============================================================================

-- Note: Silver → Gold triggers will be created in a separate migration
-- after we validate Bronze → Silver is working correctly

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Medallion Triggers Migration Applied!';
    RAISE NOTICE '⚡ Bronze → Silver triggers active';
    RAISE NOTICE '📊 Triggers will automatically process new Bronze data';
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Next: Test with existing Bronze data';
END $$;


