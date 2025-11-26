-- ============================================================================
-- FIX BRONZE → SILVER TRIGGERS FOR DATA COMPLETENESS
-- Purpose: Apply triggers and fix WI processing for actual data structure
-- ============================================================================

-- Drop existing triggers and functions
DROP TRIGGER IF EXISTS trigger_bronze_at_to_silver ON bronze_at_raw;
DROP TRIGGER IF EXISTS trigger_bronze_wi_to_silver ON bronze_wi_raw;
DROP TRIGGER IF EXISTS trigger_bronze_interview_to_silver ON bronze_interview_raw;
DROP FUNCTION IF EXISTS process_bronze_at();
DROP FUNCTION IF EXISTS process_bronze_wi();
DROP FUNCTION IF EXISTS process_bronze_interview();

-- ============================================================================
-- HELPER FUNCTIONS (if not exist)
-- ============================================================================

CREATE OR REPLACE FUNCTION parse_year(year_str TEXT)
RETURNS INTEGER AS $$
BEGIN
  IF year_str IS NULL OR year_str = '' THEN
    RETURN NULL;
  END IF;
  RETURN CAST(regexp_replace(year_str, '[^0-9]', '', 'g') AS INTEGER);
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION parse_decimal(decimal_str TEXT)
RETURNS NUMERIC AS $$
BEGIN
  IF decimal_str IS NULL OR decimal_str = '' THEN
    RETURN NULL;
  END IF;
  RETURN CAST(regexp_replace(decimal_str, '[$,\s]', '', 'g') AS NUMERIC);
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

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

CREATE OR REPLACE FUNCTION ensure_case(p_case_id TEXT)
RETURNS UUID AS $$
DECLARE
  v_case_uuid UUID;
BEGIN
  SELECT id INTO v_case_uuid
  FROM cases
  WHERE case_number = p_case_id;
  
  IF v_case_uuid IS NULL THEN
    INSERT INTO cases (case_number, status_code)
    VALUES (p_case_id, 'NEW')
    RETURNING id INTO v_case_uuid;
  END IF;
  
  RETURN v_case_uuid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION ensure_tax_year(
  p_case_uuid UUID,
  p_year INTEGER
)
RETURNS UUID AS $$
DECLARE
  v_tax_year_uuid UUID;
BEGIN
  SELECT id INTO v_tax_year_uuid
  FROM tax_years
  WHERE case_id = p_case_uuid
    AND year = p_year;
  
  IF v_tax_year_uuid IS NULL THEN
    INSERT INTO tax_years (case_id, year)
    VALUES (p_case_uuid, p_year)
    RETURNING id INTO v_tax_year_uuid;
  END IF;
  
  RETURN v_tax_year_uuid;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TRIGGER 1: BRONZE AT → SILVER
-- ============================================================================

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
  v_case_uuid := ensure_case(NEW.case_id);
  
  FOR v_record IN 
    SELECT * FROM jsonb_array_elements(
      COALESCE(
        NEW.raw_response->'at_records',
        NEW.raw_response->'records',
        NEW.raw_response->'data',
        '[]'::jsonb
      )
    )
  LOOP
    v_year := parse_year(COALESCE(
      v_record->>'tax_year',
      v_record->>'year',
      v_record->>'period'
    ));
    
    IF v_year IS NOT NULL THEN
      v_tax_year_uuid := ensure_tax_year(v_case_uuid, v_year);
      
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
            v_record->>'accountBalance',
            v_record->>'total_balance'
          )),
          calculated_account_balance
        ),
        updated_at = NOW()
      WHERE id = v_tax_year_uuid;
      
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
        
        IF v_transaction_code IS NOT NULL THEN
          SELECT * INTO v_at_rule
          FROM at_transaction_rules
          WHERE code = v_transaction_code
          LIMIT 1;
          
          INSERT INTO account_activity (
            tax_year_id,
            activity_date,
            irs_transaction_code,
            explanation,
            amount,
            calculated_transaction_type,
            affects_balance,
            affects_csed,
            indicates_collection_action
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
            COALESCE(v_at_rule.indicates_collection_action, FALSE)
          )
          ON CONFLICT DO NOTHING;
        END IF;
      END LOOP;
    END IF;
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_bronze_at_to_silver
    AFTER INSERT ON bronze_at_raw
    FOR EACH ROW
    EXECUTE FUNCTION process_bronze_at();

-- ============================================================================
-- TRIGGER 2: BRONZE WI → SILVER (FIXED FOR years_data STRUCTURE)
-- ============================================================================

CREATE OR REPLACE FUNCTION process_bronze_wi()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
  v_tax_year_uuid UUID;
  v_form JSONB;
  v_year INTEGER;
  v_year_key TEXT;
  v_year_data JSONB;
  v_form_type TEXT;
  v_wi_rule RECORD;
BEGIN
  v_case_uuid := ensure_case(NEW.case_id);
  
  -- Handle TiParser WI structure: { "years_data": { "2023": { "forms": [...] } } }
  IF NEW.raw_response ? 'years_data' AND jsonb_typeof(NEW.raw_response->'years_data') = 'object' THEN
    -- Iterate through years_data object
    FOR v_year_key, v_year_data IN SELECT * FROM jsonb_each(NEW.raw_response->'years_data')
    LOOP
      v_year := parse_year(v_year_key);
      
      IF v_year IS NOT NULL THEN
        v_tax_year_uuid := ensure_tax_year(v_case_uuid, v_year);
        
        -- Process forms in this year
        FOR v_form IN 
          SELECT * FROM jsonb_array_elements(
            COALESCE(
              v_year_data->'forms',
              '[]'::jsonb
            )
          )
        LOOP
          v_form_type := UPPER(TRIM(COALESCE(
            v_form->>'Form',
            v_form->>'form',
            v_form->>'form_type',
            v_form->>'document_type',
            v_form->>'type'
          )));
          
          IF v_form_type IS NOT NULL AND v_form_type != '' THEN
            -- Look up WI type rule
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
              is_self_employment
            )
            VALUES (
              v_tax_year_uuid,
              v_form_type,
              parse_decimal(COALESCE(
                v_form->>'Income',
                v_form->>'income',
                v_form->>'gross_amount',
                v_form->>'amount',
                v_form->>'Gross'
              )),
              parse_decimal(COALESCE(
                v_form->>'Withholding',
                v_form->>'withholding',
                v_form->>'federal_withholding',
                v_form->>'Federal'
              )),
              COALESCE(
                v_form->'Issuer'->>'Name',
                v_form->'Issuer'->>'name',
                v_form->>'issuer_name',
                v_form->>'Employer'
              ),
              COALESCE(
                v_form->'Issuer'->>'EIN',
                v_form->'Issuer'->>'ein',
                v_form->>'issuer_ein',
                v_form->>'EIN'
              ),
              COALESCE(
                v_form->'Recipient'->>'Name',
                v_form->'Recipient'->>'name',
                v_form->>'recipient_name',
                v_form->>'Employee'
              ),
              COALESCE(
                v_form->'Recipient'->>'SSN',
                v_form->'Recipient'->>'ssn',
                v_form->>'recipient_ssn',
                v_form->>'SSN'
              ),
              COALESCE(v_wi_rule.category, 'Unknown'),
              COALESCE(v_wi_rule.is_self_employment, FALSE)
            )
            ON CONFLICT DO NOTHING;
          END IF;
        END LOOP;
      END IF;
    END LOOP;
  ELSE
    -- Fallback: Handle old structure with direct "forms" array
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
        v_tax_year_uuid := ensure_tax_year(v_case_uuid, v_year);
        
        v_form_type := UPPER(TRIM(COALESCE(
          v_form->>'Form',
          v_form->>'form',
          v_form->>'form_type',
          v_form->>'document_type'
        )));
        
        IF v_form_type IS NOT NULL AND v_form_type != '' THEN
          SELECT * INTO v_wi_rule
          FROM wi_type_rules
          WHERE form_code = v_form_type
          LIMIT 1;
          
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
            is_self_employment
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
            COALESCE(v_wi_rule.is_self_employment, FALSE)
          )
          ON CONFLICT DO NOTHING;
        END IF;
      END IF;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_bronze_wi_to_silver
    AFTER INSERT ON bronze_wi_raw
    FOR EACH ROW
    EXECUTE FUNCTION process_bronze_wi();

-- ============================================================================
-- TRIGGER 3: BRONZE INTERVIEW → SILVER
-- ============================================================================

CREATE OR REPLACE FUNCTION process_bronze_interview()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
BEGIN
  v_case_uuid := ensure_case(NEW.case_id);
  
  -- This trigger is handled by the more comprehensive trigger in 20250125000005_extract_interview_fields.sql
  -- Just ensure case exists
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_bronze_interview_to_silver
    AFTER INSERT ON bronze_interview_raw
    FOR EACH ROW
    EXECUTE FUNCTION process_bronze_interview();

COMMENT ON FUNCTION process_bronze_at IS 'Extract AT data from Bronze JSONB into Silver typed tables';
COMMENT ON FUNCTION process_bronze_wi IS 'Extract WI data from Bronze JSONB into Silver income_documents (handles years_data structure)';
COMMENT ON FUNCTION process_bronze_interview IS 'Ensure case exists for interview data';

