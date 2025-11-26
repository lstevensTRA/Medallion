-- ============================================================================
-- Migration: 002_bronze_to_silver_triggers.sql
-- Purpose: Create SQL triggers to automatically transform Bronze → Silver
-- Dependencies: 
--   - 001_create_bronze_tables.sql (Bronze tables)
--   - 20250127000001_create_tax_processing_schema.sql (Silver tables)
--   - supabase/seed.sql (business rules: wi_type_rules, at_transaction_rules)
-- Author: Tax Resolution Medallion Architecture
-- Date: 2024-11-21
-- ============================================================================
-- Triggers Created:
--   - trigger_bronze_at_to_silver → account_activity, tax_years, csed_tolling_events
--   - trigger_bronze_wi_to_silver → income_documents
--   - trigger_bronze_trt_to_silver → trt_records
--   - trigger_bronze_interview_to_silver → logiqs_raw_data
-- ============================================================================
-- Benefits:
--   - Automatic transformation (no Python code needed)
--   - Handles all field variations (COALESCE logic)
--   - Applies business rules (enrichment via JOINs)
--   - Marks Bronze as processed
--   - Maintains data lineage (bronze_id preserved)
-- ============================================================================
-- Rollback:
--   DROP TRIGGER IF EXISTS trigger_bronze_at_to_silver ON bronze_at_raw;
--   DROP TRIGGER IF EXISTS trigger_bronze_wi_to_silver ON bronze_wi_raw;
--   DROP TRIGGER IF EXISTS trigger_bronze_trt_to_silver ON bronze_trt_raw;
--   DROP TRIGGER IF EXISTS trigger_bronze_interview_to_silver ON bronze_interview_raw;
--   DROP FUNCTION IF EXISTS process_bronze_at();
--   DROP FUNCTION IF EXISTS process_bronze_wi();
--   DROP FUNCTION IF EXISTS process_bronze_trt();
--   DROP FUNCTION IF EXISTS process_bronze_interview();
-- ============================================================================

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Parse year from various string formats
CREATE OR REPLACE FUNCTION parse_year(year_str TEXT)
RETURNS INTEGER AS $$
BEGIN
  IF year_str IS NULL OR year_str = '' THEN
    RETURN NULL;
  END IF;
  
  -- Handle "2023", "23", "Tax Year 2023", etc.
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
  
  -- Try various date formats
  RETURN CAST(date_str AS DATE);
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Ensure case exists (get UUID from case_number)
CREATE OR REPLACE FUNCTION ensure_case(p_case_number TEXT)
RETURNS UUID AS $$
DECLARE
  v_case_uuid UUID;
BEGIN
  -- Try to find existing case by case_number
  SELECT id INTO v_case_uuid
  FROM cases
  WHERE case_number = p_case_number;
  
  -- If not found, create a minimal case record
  IF v_case_uuid IS NULL THEN
    INSERT INTO cases (case_number, status)
    VALUES (p_case_number, 'NEW')
    RETURNING id INTO v_case_uuid;
  END IF;
  
  RETURN v_case_uuid;
END;
$$ LANGUAGE plpgsql;

-- Ensure tax_year exists for a case
CREATE OR REPLACE FUNCTION ensure_tax_year(
  p_case_uuid UUID,
  p_year TEXT
)
RETURNS UUID AS $$
DECLARE
  v_tax_year_uuid UUID;
BEGIN
  -- Try to find existing tax_year
  SELECT id INTO v_tax_year_uuid
  FROM tax_years
  WHERE case_id = p_case_uuid
    AND tax_year = p_year;
  
  -- If not found, create minimal tax_year record
  IF v_tax_year_uuid IS NULL THEN
    INSERT INTO tax_years (case_id, tax_year)
    VALUES (p_case_uuid, p_year)
    RETURNING id INTO v_tax_year_uuid;
  END IF;
  
  RETURN v_tax_year_uuid;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION parse_year IS 'Extract year as integer from various string formats';
COMMENT ON FUNCTION parse_decimal IS 'Parse decimal from strings with currency symbols and commas';
COMMENT ON FUNCTION parse_date IS 'Parse date from various string formats';
COMMENT ON FUNCTION ensure_case IS 'Get or create case UUID from case_number';
COMMENT ON FUNCTION ensure_tax_year IS 'Get or create tax_year UUID for a case and year';

-- ============================================================================
-- TRIGGER 1: BRONZE_AT_RAW → SILVER (Account Transcript)
-- ============================================================================

CREATE OR REPLACE FUNCTION process_bronze_at()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
  v_tax_year_uuid UUID;
  v_record JSONB;
  v_transaction JSONB;
  v_year TEXT;
  v_transaction_code TEXT;
  v_at_rule RECORD;
  v_records_processed INTEGER := 0;
  v_transactions_processed INTEGER := 0;
BEGIN
  -- Mark as processing
  UPDATE bronze_at_raw
  SET processing_status = 'processing'
  WHERE bronze_id = NEW.bronze_id;
  
  BEGIN
    -- Get or create case UUID
    v_case_uuid := ensure_case(NEW.case_id);
    
    -- Handle multiple possible top-level keys for records array
    -- Field variations from Phase 1 analysis:
    -- - "records" (most common)
    -- - "at_records" (alternative)
    -- - "data" (fallback)
    FOR v_record IN 
      SELECT * FROM jsonb_array_elements(
        COALESCE(
          NEW.raw_response->'records',
          NEW.raw_response->'at_records',
          NEW.raw_response->'data',
          '[]'::jsonb
        )
      )
    LOOP
      v_records_processed := v_records_processed + 1;
      
      -- Extract tax year (handle variations)
      v_year := COALESCE(
        v_record->>'tax_year',
        v_record->>'taxYear',
        v_record->>'year',
        v_record->>'period'
      );
      
      IF v_year IS NOT NULL THEN
        -- Get or create tax_year
        v_tax_year_uuid := ensure_tax_year(v_case_uuid, v_year);
        
        -- Update tax_year with additional fields
        UPDATE tax_years
        SET
          return_filed = COALESCE(
            CASE 
              WHEN UPPER(v_record->>'filed') IN ('YES', 'FILED', 'TRUE') THEN 'Filed'
              WHEN UPPER(v_record->>'filed') IN ('NO', 'UNFILED', 'FALSE') THEN 'Unfiled'
              ELSE return_filed
            END,
            return_filed
          ),
          filing_status = COALESCE(
            v_record->>'filing_status',
            v_record->>'filingStatus',
            filing_status
          ),
          agi = COALESCE(
            parse_decimal(COALESCE(
              v_record->>'adjusted_gross_income',
              v_record->>'agi',
              v_record->>'AGI'
            )),
            agi
          ),
          taxable_income = COALESCE(
            parse_decimal(COALESCE(
              v_record->>'taxable_income',
              v_record->>'taxableIncome'
            )),
            taxable_income
          ),
          total_tax = COALESCE(
            parse_decimal(COALESCE(
              v_record->>'total_tax',
              v_record->>'totalTax'
            )),
            total_tax
          ),
          updated_at = NOW()
        WHERE id = v_tax_year_uuid;
        
        -- Process transactions/activity within this tax year
        FOR v_transaction IN 
          SELECT * FROM jsonb_array_elements(
            COALESCE(
              v_record->'transactions',
              v_record->'activity',
              v_record->'account_activity',
              '[]'::jsonb
            )
          )
        LOOP
          v_transactions_processed := v_transactions_processed + 1;
          
          -- Extract transaction code
          v_transaction_code := COALESCE(
            v_transaction->>'code',
            v_transaction->>'transaction_code',
            v_transaction->>'tc'
          );
          
          -- Look up AT transaction rule for enrichment
          SELECT * INTO v_at_rule
          FROM at_transaction_rules
          WHERE code = v_transaction_code;
          
          -- Insert into account_activity (Silver layer)
          INSERT INTO account_activity (
            tax_year_id,
            transaction_date,
            transaction_code,
            transaction_description,
            amount,
            balance_after,
            
            -- Enrichment from business rules (Phase 2)
            code_category,
            affects_balance,
            affects_csed,
            is_payment,
            is_penalty,
            is_interest,
            is_collection_activity,
            
            -- Metadata
            source_bronze_id,
            created_at
          )
          VALUES (
            v_tax_year_uuid,
            
            -- Transaction date (multiple variations)
            parse_date(COALESCE(
              v_transaction->>'date',
              v_transaction->>'transaction_date',
              v_transaction->>'posted_date'
            )),
            
            -- Transaction code
            v_transaction_code,
            
            -- Description
            COALESCE(
              v_transaction->>'description',
              v_transaction->>'explanation',
              v_at_rule.description  -- Fallback to rule description
            ),
            
            -- Amount (handle negative signs)
            parse_decimal(COALESCE(
              v_transaction->>'amount',
              v_transaction->>'transaction_amount'
            )),
            
            -- Balance after transaction
            parse_decimal(COALESCE(
              v_transaction->>'balance',
              v_transaction->>'balance_after',
              v_transaction->>'ending_balance'
            )),
            
            -- Enrichment from at_transaction_rules
            v_at_rule.category,
            COALESCE(v_at_rule.affects_balance, false),
            COALESCE(v_at_rule.affects_csed, false),
            COALESCE(v_at_rule.is_payment, false),
            COALESCE(v_at_rule.is_penalty, false),
            COALESCE(v_at_rule.is_interest, false),
            COALESCE(v_at_rule.is_collection_activity, false),
            
            -- Metadata
            NEW.bronze_id,
            NOW()
          )
          ON CONFLICT DO NOTHING;  -- Prevent duplicates if replayed
          
          -- Check if this is a CSED-affecting event
          IF v_at_rule.affects_csed = true THEN
            -- Insert into csed_tolling_events
            INSERT INTO csed_tolling_events (
              case_id,
              tax_year,
              event_type,
              event_date,
              event_code,
              toll_days,
              description,
              source_bronze_id,
              created_at
            )
            VALUES (
              v_case_uuid,
              v_year,
              v_at_rule.category,
              parse_date(COALESCE(
                v_transaction->>'date',
                v_transaction->>'transaction_date'
              )),
              v_transaction_code,
              
              -- Look up toll days from csed_calculation_rules (Phase 2)
              (SELECT toll_days 
               FROM csed_calculation_rules 
               WHERE category = v_at_rule.category 
               LIMIT 1),
              
              COALESCE(
                v_transaction->>'description',
                v_at_rule.description
              ),
              NEW.bronze_id,
              NOW()
            )
            ON CONFLICT DO NOTHING;
          END IF;
          
        END LOOP;  -- End transaction loop
        
      END IF;  -- End if v_year is not null
      
    END LOOP;  -- End record loop
    
    -- Mark Bronze record as successfully processed
    UPDATE bronze_at_raw
    SET 
      processing_status = 'completed',
      processed_at = NOW(),
      processing_error = NULL
    WHERE bronze_id = NEW.bronze_id;
    
    RAISE NOTICE 'Processed Bronze AT record %: % tax years, % transactions', 
      NEW.bronze_id, v_records_processed, v_transactions_processed;
    
  EXCEPTION
    WHEN OTHERS THEN
      -- Mark as failed with error message
      UPDATE bronze_at_raw
      SET 
        processing_status = 'failed',
        processing_error = SQLERRM
      WHERE bronze_id = NEW.bronze_id;
      
      RAISE WARNING 'Failed to process Bronze AT record %: %', NEW.bronze_id, SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trigger_bronze_at_to_silver
  AFTER INSERT ON bronze_at_raw
  FOR EACH ROW
  EXECUTE FUNCTION process_bronze_at();

COMMENT ON FUNCTION process_bronze_at IS 'Transform Bronze AT data to Silver tables (account_activity, tax_years, csed_tolling_events). Handles 8+ field variations, applies at_transaction_rules enrichment.';

-- ============================================================================
-- TRIGGER 2: BRONZE_WI_RAW → SILVER (Wage & Income)
-- ============================================================================

CREATE OR REPLACE FUNCTION process_bronze_wi()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
  v_tax_year_uuid UUID;
  v_form JSONB;
  v_year TEXT;
  v_form_type TEXT;
  v_wi_rule RECORD;
  v_forms_processed INTEGER := 0;
BEGIN
  -- Mark as processing
  UPDATE bronze_wi_raw
  SET processing_status = 'processing'
  WHERE bronze_id = NEW.bronze_id;
  
  BEGIN
    -- Get or create case UUID
    v_case_uuid := ensure_case(NEW.case_id);
    
    -- Handle multiple possible top-level keys for forms array
    -- Field variations from Phase 1:
    -- - "forms" (most common)
    -- - "wi_forms"
    -- - "documents"
    -- - "income_documents"
    FOR v_form IN 
      SELECT * FROM jsonb_array_elements(
        COALESCE(
          NEW.raw_response->'forms',
          NEW.raw_response->'wi_forms',
          NEW.raw_response->'documents',
          NEW.raw_response->'income_documents',
          '[]'::jsonb
        )
      )
    LOOP
      v_forms_processed := v_forms_processed + 1;
      
      -- Extract tax year
      v_year := COALESCE(
        v_form->>'Year',
        v_form->>'year',
        v_form->>'tax_year',
        v_form->>'taxYear'
      );
      
      -- Extract form type
      v_form_type := UPPER(TRIM(COALESCE(
        v_form->>'Form',
        v_form->>'form',
        v_form->>'form_type',
        v_form->>'FormType',
        v_form->>'document_type'
      )));
      
      IF v_year IS NOT NULL AND v_form_type IS NOT NULL THEN
        -- Get or create tax_year
        v_tax_year_uuid := ensure_tax_year(v_case_uuid, v_year);
        
        -- Look up WI type rule for enrichment
        SELECT * INTO v_wi_rule
        FROM wi_type_rules
        WHERE form_code = v_form_type;
        
        -- Insert into income_documents (Silver layer)
        INSERT INTO income_documents (
          case_id,
          tax_year_id,
          tax_year,
          document_type,
          
          -- Issuer information (nested structure)
          issuer_name,
          issuer_ein,
          issuer_address,
          
          -- Recipient information (nested structure)
          recipient_name,
          recipient_ssn,
          
          -- Financial data
          gross_amount,
          withholding_amount,
          income_type,
          
          -- Enrichment from wi_type_rules (Phase 2)
          calculated_category,
          is_self_employment,
          
          -- Metadata
          source_bronze_id,
          created_at
        )
        VALUES (
          v_case_uuid,
          v_tax_year_uuid,
          v_year,
          v_form_type,
          
          -- Issuer (handle 3 levels of nesting from Phase 1 analysis)
          COALESCE(
            v_form->'Issuer'->>'Name',
            v_form->'Issuer'->>'name',
            v_form->'issuer'->>'Name',
            v_form->'issuer'->>'name',
            v_form->>'IssuerName',
            v_form->>'issuer_name'
          ),
          
          COALESCE(
            v_form->'Issuer'->>'EIN',
            v_form->'Issuer'->>'ein',
            v_form->'issuer'->>'EIN',
            v_form->'issuer'->>'ein',
            v_form->>'IssuerEIN',
            v_form->>'issuer_ein'
          ),
          
          COALESCE(
            v_form->'Issuer'->>'Address',
            v_form->'Issuer'->>'address',
            v_form->'issuer'->>'Address',
            v_form->'issuer'->>'address',
            v_form->>'IssuerAddress'
          ),
          
          -- Recipient (handle 3 levels of nesting)
          COALESCE(
            v_form->'Recipient'->>'Name',
            v_form->'Recipient'->>'name',
            v_form->'recipient'->>'Name',
            v_form->'recipient'->>'name',
            v_form->>'RecipientName',
            v_form->>'recipient_name'
          ),
          
          COALESCE(
            v_form->'Recipient'->>'SSN',
            v_form->'Recipient'->>'ssn',
            v_form->'recipient'->>'SSN',
            v_form->'recipient'->>'ssn',
            v_form->>'RecipientSSN',
            v_form->>'recipient_ssn'
          ),
          
          -- Financial data (multiple field name variations)
          parse_decimal(COALESCE(
            v_form->>'Income',
            v_form->>'income',
            v_form->>'gross_amount',
            v_form->>'GrossAmount',
            v_form->>'Amount',
            v_form->>'amount'
          )),
          
          parse_decimal(COALESCE(
            v_form->>'Withholding',
            v_form->>'withholding',
            v_form->>'federal_withholding',
            v_form->>'FederalWithholding',
            v_form->>'WithholdingAmount'
          )),
          
          COALESCE(
            v_form->>'IncomeType',
            v_form->>'income_type',
            v_wi_rule.category  -- Fallback to rule category
          ),
          
          -- Enrichment from wi_type_rules
          v_wi_rule.category,
          COALESCE(v_wi_rule.is_self_employment, false),
          
          -- Metadata
          NEW.bronze_id,
          NOW()
        )
        ON CONFLICT DO NOTHING;
        
      END IF;  -- End if year and form_type not null
      
    END LOOP;  -- End form loop
    
    -- Mark Bronze record as successfully processed
    UPDATE bronze_wi_raw
    SET 
      processing_status = 'completed',
      processed_at = NOW(),
      processing_error = NULL
    WHERE bronze_id = NEW.bronze_id;
    
    RAISE NOTICE 'Processed Bronze WI record %: % forms', NEW.bronze_id, v_forms_processed;
    
  EXCEPTION
    WHEN OTHERS THEN
      -- Mark as failed
      UPDATE bronze_wi_raw
      SET 
        processing_status = 'failed',
        processing_error = SQLERRM
      WHERE bronze_id = NEW.bronze_id;
      
      RAISE WARNING 'Failed to process Bronze WI record %: %', NEW.bronze_id, SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trigger_bronze_wi_to_silver
  AFTER INSERT ON bronze_wi_raw
  FOR EACH ROW
  EXECUTE FUNCTION process_bronze_wi();

COMMENT ON FUNCTION process_bronze_wi IS 'Transform Bronze WI data to Silver income_documents table. Handles 15+ field variations, applies wi_type_rules enrichment.';

-- ============================================================================
-- TRIGGER 3: BRONZE_TRT_RAW → SILVER (Tax Return Transcript)
-- ============================================================================

CREATE OR REPLACE FUNCTION process_bronze_trt()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
  v_record JSONB;
  v_records_processed INTEGER := 0;
BEGIN
  -- Mark as processing
  UPDATE bronze_trt_raw
  SET processing_status = 'processing'
  WHERE bronze_id = NEW.bronze_id;
  
  BEGIN
    -- Get or create case UUID
    v_case_uuid := ensure_case(NEW.case_id);
    
    -- Handle multiple possible top-level keys
    FOR v_record IN 
      SELECT * FROM jsonb_array_elements(
        COALESCE(
          NEW.raw_response->'records',
          NEW.raw_response->'trt_records',
          NEW.raw_response->'documents',
          '[]'::jsonb
        )
      )
    LOOP
      v_records_processed := v_records_processed + 1;
      
      -- Insert into trt_records (Silver layer)
      INSERT INTO trt_records (
        case_id,
        tax_year,
        form_number,
        category,
        sub_category,
        line_number,
        description,
        amount,
        
        -- Metadata
        source_bronze_id,
        created_at
      )
      VALUES (
        v_case_uuid,
        
        -- Tax year
        COALESCE(
          v_record->>'tax_year',
          v_record->>'taxYear',
          v_record->>'year'
        ),
        
        -- Form number (Schedule C, E, etc.)
        COALESCE(
          v_record->>'form_number',
          v_record->>'formNumber',
          v_record->>'form',
          v_record->>'schedule'
        ),
        
        -- Category (Expenses, Income, Deductions)
        COALESCE(
          v_record->>'category',
          v_record->>'type'
        ),
        
        -- Sub-category (more specific)
        COALESCE(
          v_record->>'sub_category',
          v_record->>'subCategory',
          v_record->>'subcategory'
        ),
        
        -- Line number on form
        COALESCE(
          v_record->>'line_number',
          v_record->>'lineNumber',
          v_record->>'line'
        ),
        
        -- Description
        COALESCE(
          v_record->>'description',
          v_record->>'label'
        ),
        
        -- Amount (parse as decimal)
        parse_decimal(COALESCE(
          v_record->>'data',
          v_record->>'amount',
          v_record->>'value'
        )),
        
        -- Metadata
        NEW.bronze_id,
        NOW()
      )
      ON CONFLICT DO NOTHING;
      
    END LOOP;
    
    -- Mark as processed
    UPDATE bronze_trt_raw
    SET 
      processing_status = 'completed',
      processed_at = NOW(),
      processing_error = NULL
    WHERE bronze_id = NEW.bronze_id;
    
    RAISE NOTICE 'Processed Bronze TRT record %: % records', NEW.bronze_id, v_records_processed;
    
  EXCEPTION
    WHEN OTHERS THEN
      UPDATE bronze_trt_raw
      SET 
        processing_status = 'failed',
        processing_error = SQLERRM
      WHERE bronze_id = NEW.bronze_id;
      
      RAISE WARNING 'Failed to process Bronze TRT record %: %', NEW.bronze_id, SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trigger_bronze_trt_to_silver
  AFTER INSERT ON bronze_trt_raw
  FOR EACH ROW
  EXECUTE FUNCTION process_bronze_trt();

COMMENT ON FUNCTION process_bronze_trt IS 'Transform Bronze TRT data to Silver trt_records table. Handles 9+ field variations.';

-- ============================================================================
-- TRIGGER 4: BRONZE_INTERVIEW_RAW → SILVER (CaseHelper Interview)
-- ============================================================================

CREATE OR REPLACE FUNCTION process_bronze_interview()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
BEGIN
  -- Mark as processing
  UPDATE bronze_interview_raw
  SET processing_status = 'processing'
  WHERE bronze_id = NEW.bronze_id;
  
  BEGIN
    -- Get or create case UUID
    v_case_uuid := ensure_case(NEW.case_id);
    
    -- Insert into logiqs_raw_data (Silver layer)
    -- This table stores the complete interview response in structured JSONB columns
    INSERT INTO logiqs_raw_data (
      case_id,
      
      -- Structured JSONB columns (from Phase 1 analysis)
      employment,
      household,
      assets,
      income,
      expenses,
      irs_standards,
      
      -- Metadata
      source_bronze_id,
      created_at
    )
    VALUES (
      v_case_uuid,
      
      -- Extract structured sections
      NEW.raw_response->'employment',
      NEW.raw_response->'household',
      NEW.raw_response->'assets',
      NEW.raw_response->'income',
      NEW.raw_response->'expenses',
      NEW.raw_response->'irs_standards',
      
      -- Metadata
      NEW.bronze_id,
      NOW()
    )
    ON CONFLICT (case_id) DO UPDATE SET
      employment = EXCLUDED.employment,
      household = EXCLUDED.household,
      assets = EXCLUDED.assets,
      income = EXCLUDED.income,
      expenses = EXCLUDED.expenses,
      irs_standards = EXCLUDED.irs_standards,
      source_bronze_id = EXCLUDED.source_bronze_id,
      updated_at = NOW();
    
    -- Mark as processed
    UPDATE bronze_interview_raw
    SET 
      processing_status = 'completed',
      processed_at = NOW(),
      processing_error = NULL
    WHERE bronze_id = NEW.bronze_id;
    
    RAISE NOTICE 'Processed Bronze Interview record %', NEW.bronze_id;
    
  EXCEPTION
    WHEN OTHERS THEN
      UPDATE bronze_interview_raw
      SET 
        processing_status = 'failed',
        processing_error = SQLERRM
      WHERE bronze_id = NEW.bronze_id;
      
      RAISE WARNING 'Failed to process Bronze Interview record %: %', NEW.bronze_id, SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trigger_bronze_interview_to_silver
  AFTER INSERT ON bronze_interview_raw
  FOR EACH ROW
  EXECUTE FUNCTION process_bronze_interview();

COMMENT ON FUNCTION process_bronze_interview IS 'Transform Bronze Interview data to Silver logiqs_raw_data table. Stores structured JSONB sections.';

-- ============================================================================
-- DATA QUALITY VIEWS
-- ============================================================================

-- View: Bronze → Silver data flow health
CREATE OR REPLACE VIEW bronze_silver_health AS
SELECT 
  'AT' as data_type,
  COUNT(*) as bronze_total,
  COUNT(*) FILTER (WHERE processing_status = 'completed') as bronze_processed,
  COUNT(*) FILTER (WHERE processing_status = 'pending') as bronze_pending,
  COUNT(*) FILTER (WHERE processing_status = 'failed') as bronze_failed,
  (SELECT COUNT(*) FROM account_activity WHERE source_bronze_id IN (SELECT bronze_id FROM bronze_at_raw)) as silver_records
FROM bronze_at_raw
UNION ALL
SELECT 
  'WI' as data_type,
  COUNT(*) as bronze_total,
  COUNT(*) FILTER (WHERE processing_status = 'completed') as bronze_processed,
  COUNT(*) FILTER (WHERE processing_status = 'pending') as bronze_pending,
  COUNT(*) FILTER (WHERE processing_status = 'failed') as bronze_failed,
  (SELECT COUNT(*) FROM income_documents WHERE source_bronze_id IN (SELECT bronze_id FROM bronze_wi_raw)) as silver_records
FROM bronze_wi_raw
UNION ALL
SELECT 
  'TRT' as data_type,
  COUNT(*) as bronze_total,
  COUNT(*) FILTER (WHERE processing_status = 'completed') as bronze_processed,
  COUNT(*) FILTER (WHERE processing_status = 'pending') as bronze_pending,
  COUNT(*) FILTER (WHERE processing_status = 'failed') as bronze_failed,
  (SELECT COUNT(*) FROM trt_records WHERE source_bronze_id IN (SELECT bronze_id FROM bronze_trt_raw)) as silver_records
FROM bronze_trt_raw
UNION ALL
SELECT 
  'Interview' as data_type,
  COUNT(*) as bronze_total,
  COUNT(*) FILTER (WHERE processing_status = 'completed') as bronze_processed,
  COUNT(*) FILTER (WHERE processing_status = 'pending') as bronze_pending,
  COUNT(*) FILTER (WHERE processing_status = 'failed') as bronze_failed,
  (SELECT COUNT(*) FROM logiqs_raw_data WHERE source_bronze_id IN (SELECT bronze_id FROM bronze_interview_raw)) as silver_records
FROM bronze_interview_raw;

COMMENT ON VIEW bronze_silver_health IS 'Monitor Bronze → Silver trigger health. Shows processing status and record counts.';

-- ============================================================================
-- VALIDATION QUERIES
-- ============================================================================

-- Query: Check for Bronze records that failed processing
CREATE OR REPLACE FUNCTION get_failed_bronze_records()
RETURNS TABLE (
  data_type TEXT,
  bronze_id UUID,
  case_id TEXT,
  inserted_at TIMESTAMP WITH TIME ZONE,
  error_message TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 'AT'::TEXT, b.bronze_id, b.case_id, b.inserted_at, b.processing_error
  FROM bronze_at_raw b
  WHERE b.processing_status = 'failed'
  UNION ALL
  SELECT 'WI'::TEXT, b.bronze_id, b.case_id, b.inserted_at, b.processing_error
  FROM bronze_wi_raw b
  WHERE b.processing_status = 'failed'
  UNION ALL
  SELECT 'TRT'::TEXT, b.bronze_id, b.case_id, b.inserted_at, b.processing_error
  FROM bronze_trt_raw b
  WHERE b.processing_status = 'failed'
  UNION ALL
  SELECT 'Interview'::TEXT, b.bronze_id, b.case_id, b.inserted_at, b.processing_error
  FROM bronze_interview_raw b
  WHERE b.processing_status = 'failed'
  ORDER BY inserted_at DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_failed_bronze_records IS 'Get all Bronze records that failed processing with error messages';

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
  trigger_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO trigger_count
  FROM information_schema.triggers
  WHERE trigger_name IN (
    'trigger_bronze_at_to_silver',
    'trigger_bronze_wi_to_silver',
    'trigger_bronze_trt_to_silver',
    'trigger_bronze_interview_to_silver'
  );
  
  IF trigger_count = 4 THEN
    RAISE NOTICE '✅ Bronze → Silver triggers created successfully: 4/4 triggers';
  ELSE
    RAISE WARNING '⚠️  Expected 4 triggers, found %', trigger_count;
  END IF;
END $$;

-- ============================================================================
-- Migration Complete
-- ============================================================================
-- What Just Happened:
-- 1. Created 4 helper functions (parse_year, parse_decimal, parse_date, ensure_case)
-- 2. Created 4 trigger functions (process_bronze_at/wi/trt/interview)
-- 3. Created 4 triggers (automatic Bronze → Silver transformation)
-- 4. Created data quality views (bronze_silver_health)
-- 5. Created validation functions (get_failed_bronze_records)
--
-- Result: 
-- - Your 1,235 lines of Python parsing → replaced by SQL triggers
-- - Automatic transformation on Bronze INSERT
-- - Business rule enrichment applied
-- - Processing status tracked
-- - Data lineage maintained
--
-- Next Steps:
-- 1. Apply this migration: supabase db push
-- 2. Test with sample data: INSERT INTO bronze_at_raw (...)
-- 3. Verify Silver populated: SELECT * FROM bronze_silver_health;
-- 4. Modify Python code to use BronzeStorage (Phase 3 guide)
-- 5. Remove old save_*_data() functions
-- ============================================================================

