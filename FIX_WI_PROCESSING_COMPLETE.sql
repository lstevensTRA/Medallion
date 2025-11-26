-- ============================================================================
-- FIX WI PROCESSING - COMPLETE SOLUTION
-- Purpose: Fix Bronze WI → Silver income_documents trigger for actual data structure
-- ============================================================================

DROP TRIGGER IF EXISTS trigger_bronze_wi_to_silver ON bronze_wi_raw;
DROP FUNCTION IF EXISTS process_bronze_wi();

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
  v_income NUMERIC;
  v_withholding NUMERIC;
  v_issuer_name TEXT;
  v_issuer_ein TEXT;
  v_recipient_name TEXT;
  v_recipient_ssn TEXT;
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
          -- Extract form type - try all possible keys
          v_form_type := NULL;
          
          -- Try common form type keys
          v_form_type := COALESCE(
            v_form->>'Form',
            v_form->>'form',
            v_form->>'form_type',
            v_form->>'document_type',
            v_form->>'type',
            v_form->>'FormType',
            v_form->>'formCode'
          );
          
          -- If still NULL, check if any value contains form identifiers
          IF v_form_type IS NULL OR v_form_type = '' THEN
            -- Check all string values for form patterns
            FOR v_year_key IN SELECT jsonb_object_keys(v_form)
            LOOP
              IF jsonb_typeof(v_form->v_year_key) = 'string' THEN
                DECLARE
                  v_val TEXT := v_form->>>v_year_key;
                BEGIN
                  IF v_val ~* '(W-?2|1099|WAGE|INCOME)' THEN
                    v_form_type := UPPER(TRIM(v_val));
                    EXIT;
                  END IF;
                END;
              END IF;
            END LOOP;
          END IF;
          
          -- Normalize form type
          IF v_form_type IS NOT NULL AND v_form_type != '' THEN
            v_form_type := UPPER(TRIM(v_form_type));
            
            -- Look up WI type rule
            SELECT * INTO v_wi_rule
            FROM wi_type_rules
            WHERE form_code = v_form_type
            LIMIT 1;
            
            -- Extract income - try all possible keys
            v_income := COALESCE(
              parse_decimal(v_form->>'Income'),
              parse_decimal(v_form->>'income'),
              parse_decimal(v_form->>'gross_amount'),
              parse_decimal(v_form->>'amount'),
              parse_decimal(v_form->>'Gross'),
              parse_decimal(v_form->>'Wages'),
              parse_decimal(v_form->>'wages'),
              parse_decimal(v_form->>'Total'),
              0
            );
            
            -- Extract withholding
            v_withholding := COALESCE(
              parse_decimal(v_form->>'Withholding'),
              parse_decimal(v_form->>'withholding'),
              parse_decimal(v_form->>'federal_withholding'),
              parse_decimal(v_form->>'Federal'),
              parse_decimal(v_form->>'FederalTaxWithheld'),
              0
            );
            
            -- Extract issuer info (nested or flat)
            v_issuer_name := COALESCE(
              v_form->'Issuer'->>'Name',
              v_form->'Issuer'->>'name',
              v_form->>'issuer_name',
              v_form->>'Employer',
              v_form->>'employer_name',
              v_form->>'EmployerName'
            );
            
            v_issuer_ein := COALESCE(
              v_form->'Issuer'->>'EIN',
              v_form->'Issuer'->>'ein',
              v_form->>'issuer_ein',
              v_form->>'EIN',
              v_form->>'ein',
              v_form->>'EmployerEIN'
            );
            
            -- Extract recipient info
            v_recipient_name := COALESCE(
              v_form->'Recipient'->>'Name',
              v_form->'Recipient'->>'name',
              v_form->>'recipient_name',
              v_form->>'Employee',
              v_form->>'employee_name',
              v_form->>'EmployeeName'
            );
            
            v_recipient_ssn := COALESCE(
              v_form->'Recipient'->>'SSN',
              v_form->'Recipient'->>'ssn',
              v_form->>'recipient_ssn',
              v_form->>'SSN',
              v_form->>'ssn',
              v_form->>'EmployeeSSN'
            );
            
            -- Insert income_document (only if we have at least a form type)
            IF v_form_type IS NOT NULL AND v_form_type != '' THEN
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
                v_income,
                v_withholding,
                v_issuer_name,
                v_issuer_ein,
                v_recipient_name,
                v_recipient_ssn,
                COALESCE(v_wi_rule.category, 'Unknown'),
                COALESCE(v_wi_rule.is_self_employment, FALSE)
              )
              ON CONFLICT DO NOTHING;
            END IF;
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
            COALESCE(parse_decimal(v_form->>'Income'), parse_decimal(v_form->>'income'), parse_decimal(v_form->>'gross_amount'), 0),
            COALESCE(parse_decimal(v_form->>'Withholding'), parse_decimal(v_form->>'withholding'), 0),
            COALESCE(v_form->'Issuer'->>'Name', v_form->>'issuer_name'),
            COALESCE(v_form->'Issuer'->>'EIN', v_form->>'issuer_ein'),
            COALESCE(v_form->'Recipient'->>'Name', v_form->>'recipient_name'),
            COALESCE(v_form->'Recipient'->>'SSN', v_form->>'recipient_ssn'),
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

COMMENT ON FUNCTION process_bronze_wi IS 'Extract WI data from Bronze JSONB into Silver income_documents (handles years_data structure with comprehensive field extraction)';

