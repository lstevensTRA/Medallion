-- ============================================================================
-- Migration: 006_create_silver_layer.sql
-- Purpose: Create Silver Layer tables for typed, enriched data
-- Dependencies: 
--   - Bronze tables exist (001_create_bronze_tables.sql)
--   - Business rules tables exist (wi_type_rules, at_transaction_rules)
-- ============================================================================
-- Tables Created:
--   - tax_years (tax year summaries)
--   - account_activity (AT transactions with enrichment)
--   - income_documents (WI forms with enrichment)
--   - trt_records (TRT data)
--   - logiqs_raw_data (Interview data - structured)
-- ============================================================================

-- ============================================================================
-- PART 1: CORE SILVER TABLES
-- ============================================================================

-- Cases table (if doesn't exist)
CREATE TABLE IF NOT EXISTS cases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id TEXT UNIQUE,  -- External case ID (e.g., "1295022")
    case_number TEXT,     -- Formatted case number (e.g., "CASE-1295022")
    status TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cases_case_id ON cases(case_id);
CREATE INDEX IF NOT EXISTS idx_cases_case_number ON cases(case_number);

-- Tax Years (Silver: Tax year summaries)
CREATE TABLE IF NOT EXISTS tax_years (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id TEXT NOT NULL,  -- External case_id (not UUID FK for now)
    bronze_id UUID,         -- Link back to Bronze for lineage
    tax_year TEXT NOT NULL,  -- "2023", "2024", etc.
    return_filed TEXT,      -- "Filed", "Unfiled", "Unknown"
    filing_status TEXT,      -- "Single", "Married Filing Joint", etc.
    agi DECIMAL(15, 2),      -- Adjusted Gross Income
    taxable_income DECIMAL(15, 2),
    total_tax DECIMAL(15, 2),
    account_balance DECIMAL(15, 2),
    balance_due DECIMAL(15, 2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tax_years_case_id ON tax_years(case_id);
CREATE INDEX IF NOT EXISTS idx_tax_years_tax_year ON tax_years(tax_year);
CREATE INDEX IF NOT EXISTS idx_tax_years_bronze_id ON tax_years(bronze_id);

COMMENT ON TABLE tax_years IS 'Silver layer: Tax year summaries extracted from AT data';

-- Account Activity (Silver: AT transactions with enrichment)
CREATE TABLE IF NOT EXISTS account_activity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id TEXT NOT NULL,
    bronze_id UUID,         -- Link back to Bronze
    tax_year TEXT NOT NULL,
    activity_date DATE,
    irs_transaction_code TEXT,
    explanation TEXT,
    amount DECIMAL(15, 2),
    balance_after DECIMAL(15, 2),
    
    -- Enrichment from at_transaction_rules
    calculated_transaction_type TEXT,
    affects_balance BOOLEAN DEFAULT FALSE,
    affects_csed BOOLEAN DEFAULT FALSE,
    indicates_collection_action BOOLEAN DEFAULT FALSE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_account_activity_case_id ON account_activity(case_id);
CREATE INDEX IF NOT EXISTS idx_account_activity_tax_year ON account_activity(tax_year);
CREATE INDEX IF NOT EXISTS idx_account_activity_bronze_id ON account_activity(bronze_id);
CREATE INDEX IF NOT EXISTS idx_account_activity_code ON account_activity(irs_transaction_code);

COMMENT ON TABLE account_activity IS 'Silver layer: Account Transcript transactions with business rule enrichment';

-- Income Documents (Silver: WI forms with enrichment)
CREATE TABLE IF NOT EXISTS income_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id TEXT NOT NULL,
    bronze_id UUID,         -- Link back to Bronze
    tax_year TEXT NOT NULL,
    document_type TEXT NOT NULL,  -- "W-2", "1099-NEC", "1099-MISC", etc.
    gross_amount DECIMAL(15, 2) DEFAULT 0,
    federal_withholding DECIMAL(15, 2) DEFAULT 0,
    issuer_name TEXT,
    issuer_ein TEXT,
    recipient_name TEXT,
    recipient_ssn TEXT,
    
    -- Enrichment from wi_type_rules
    calculated_category TEXT,  -- "SE", "Non-SE", "Neither"
    is_self_employment BOOLEAN DEFAULT FALSE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_income_documents_case_id ON income_documents(case_id);
CREATE INDEX IF NOT EXISTS idx_income_documents_tax_year ON income_documents(tax_year);
CREATE INDEX IF NOT EXISTS idx_income_documents_bronze_id ON income_documents(bronze_id);
CREATE INDEX IF NOT EXISTS idx_income_documents_doc_type ON income_documents(document_type);

COMMENT ON TABLE income_documents IS 'Silver layer: Wage & Income forms with business rule enrichment';

-- TRT Records (Silver: Tax Return Transcript data)
CREATE TABLE IF NOT EXISTS trt_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id TEXT NOT NULL,
    bronze_id UUID,         -- Link back to Bronze
    tax_year TEXT NOT NULL,
    form_number TEXT,        -- "Schedule C", "Schedule E", etc.
    category TEXT,
    sub_category TEXT,
    line_number TEXT,
    description TEXT,
    amount DECIMAL(15, 2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trt_records_case_id ON trt_records(case_id);
CREATE INDEX IF NOT EXISTS idx_trt_records_tax_year ON trt_records(tax_year);
CREATE INDEX IF NOT EXISTS idx_trt_records_bronze_id ON trt_records(bronze_id);

COMMENT ON TABLE trt_records IS 'Silver layer: Tax Return Transcript records';

-- Logiqs Raw Data (Silver: Interview data - structured)
CREATE TABLE IF NOT EXISTS logiqs_raw_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id TEXT NOT NULL,
    bronze_id UUID,         -- Link back to Bronze
    raw_response JSONB,     -- Structured interview data
    extracted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_logiqs_case_id ON logiqs_raw_data(case_id);
CREATE INDEX IF NOT EXISTS idx_logiqs_bronze_id ON logiqs_raw_data(bronze_id);

COMMENT ON TABLE logiqs_raw_data IS 'Silver layer: Structured interview data from CaseHelper';

-- ============================================================================
-- PART 2: HELPER FUNCTIONS
-- ============================================================================

-- Parse year from various string formats
CREATE OR REPLACE FUNCTION parse_year(year_str TEXT)
RETURNS TEXT AS $$
BEGIN
  IF year_str IS NULL OR year_str = '' THEN
    RETURN NULL;
  END IF;
  
  -- Extract year from "2023", "23", "Tax Year 2023", etc.
  RETURN regexp_replace(year_str, '[^0-9]', '', 'g');
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
  
  -- Try to cast as date
  RETURN CAST(date_str AS DATE);
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION parse_year IS 'Extract year as text from various string formats';
COMMENT ON FUNCTION parse_decimal IS 'Parse decimal from strings with currency symbols and commas';
COMMENT ON FUNCTION parse_date IS 'Parse date from various string formats';

-- ============================================================================
-- PART 3: BRONZE → SILVER TRIGGERS
-- ============================================================================

-- Trigger 1: Bronze AT → Silver (tax_years, account_activity)
CREATE OR REPLACE FUNCTION process_bronze_at()
RETURNS TRIGGER AS $$
DECLARE
  v_record JSONB;
  v_transaction JSONB;
  v_year TEXT;
  v_transaction_code TEXT;
  v_at_rule RECORD;
BEGIN
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
      -- Insert/Update tax_years
      INSERT INTO tax_years (
        case_id,
        bronze_id,
        tax_year,
        return_filed,
        filing_status,
        agi,
        taxable_income,
        total_tax,
        account_balance,
        balance_due
      )
      VALUES (
        NEW.case_id,
        NEW.bronze_id,
        v_year,
        CASE 
          WHEN UPPER(COALESCE(v_record->>'return_filed', v_record->>'filed')) IN ('YES', 'FILED', 'TRUE') THEN 'Filed'
          WHEN UPPER(COALESCE(v_record->>'return_filed', v_record->>'filed')) IN ('NO', 'UNFILED', 'FALSE') THEN 'Unfiled'
          ELSE 'Unknown'
        END,
        COALESCE(v_record->>'filing_status', v_record->>'FilingStatus'),
        parse_decimal(COALESCE(
          v_record->>'adjusted_gross_income',
          v_record->>'agi',
          v_record->>'AGI'
        )),
        parse_decimal(COALESCE(
          v_record->>'taxable_income',
          v_record->>'taxableIncome'
        )),
        parse_decimal(COALESCE(
          v_record->>'tax_per_return',
          v_record->>'TaxPerReturn'
        )),
        parse_decimal(COALESCE(
          v_record->>'account_balance',
          v_record->>'accountBalance'
        )),
        parse_decimal(COALESCE(
          v_record->>'total_balance',
          v_record->>'totalBalance'
        ))
      )
      ON CONFLICT DO NOTHING;
      
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
          case_id,
          bronze_id,
          tax_year,
          activity_date,
          irs_transaction_code,
          explanation,
          amount,
          balance_after,
          calculated_transaction_type,
          affects_balance,
          affects_csed,
          indicates_collection_action
        )
        VALUES (
          NEW.case_id,
          NEW.bronze_id,
          v_year,
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
          parse_decimal(v_transaction->>'balance_after'),
          COALESCE(v_at_rule.transaction_type, 'Unknown'),
          COALESCE(v_at_rule.affects_balance, false),
          COALESCE(v_at_rule.affects_csed, false),
          COALESCE(v_at_rule.indicates_collection_action, false)
        );
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

COMMENT ON FUNCTION process_bronze_at IS 'Extract AT data from Bronze JSONB into Silver typed tables';

-- Trigger 2: Bronze WI → Silver (income_documents)
CREATE OR REPLACE FUNCTION process_bronze_wi()
RETURNS TRIGGER AS $$
DECLARE
  v_form JSONB;
  v_year TEXT;
  v_form_type TEXT;
  v_wi_rule RECORD;
BEGIN
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
      case_id,
      bronze_id,
      tax_year,
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
      NEW.case_id,
      NEW.bronze_id,
      v_year,
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
      COALESCE(v_wi_rule.is_self_employment, false)
    );
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_bronze_wi_to_silver ON bronze_wi_raw;
CREATE TRIGGER trigger_bronze_wi_to_silver
    AFTER INSERT ON bronze_wi_raw
    FOR EACH ROW
    EXECUTE FUNCTION process_bronze_wi();

COMMENT ON FUNCTION process_bronze_wi IS 'Extract WI data from Bronze JSONB into Silver typed tables';

-- Trigger 3: Bronze Interview → Silver (logiqs_raw_data)
CREATE OR REPLACE FUNCTION process_bronze_interview()
RETURNS TRIGGER AS $$
BEGIN
  -- Store interview data in logiqs_raw_data (structured JSONB)
  INSERT INTO logiqs_raw_data (
    case_id,
    bronze_id,
    raw_response,
    extracted_at
  )
  VALUES (
    NEW.case_id,
    NEW.bronze_id,
    NEW.raw_response,
    NOW()
  )
  ON CONFLICT DO NOTHING;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_bronze_interview_to_silver ON bronze_interview_raw;
CREATE TRIGGER trigger_bronze_interview_to_silver
    AFTER INSERT ON bronze_interview_raw
    FOR EACH ROW
    EXECUTE FUNCTION process_bronze_interview();

COMMENT ON FUNCTION process_bronze_interview IS 'Store interview data in Silver layer';

-- ============================================================================
-- PART 4: HEALTH CHECK VIEW
-- ============================================================================

CREATE OR REPLACE VIEW silver_health AS
SELECT 
    'tax_years' as table_name,
    COUNT(*) as record_count,
    COUNT(DISTINCT case_id) as unique_cases,
    MAX(created_at) as last_insert
FROM tax_years
UNION ALL
SELECT 
    'account_activity',
    COUNT(*),
    COUNT(DISTINCT case_id),
    MAX(created_at)
FROM account_activity
UNION ALL
SELECT 
    'income_documents',
    COUNT(*),
    COUNT(DISTINCT case_id),
    MAX(created_at)
FROM income_documents
UNION ALL
SELECT 
    'trt_records',
    COUNT(*),
    COUNT(DISTINCT case_id),
    MAX(created_at)
FROM trt_records
UNION ALL
SELECT 
    'logiqs_raw_data',
    COUNT(*),
    COUNT(DISTINCT case_id),
    MAX(created_at)
FROM logiqs_raw_data;

COMMENT ON VIEW silver_health IS 'Monitor record counts across all Silver layer tables';

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Silver Layer Migration Complete!';
    RAISE NOTICE '📊 Created: tax_years, account_activity, income_documents, trt_records, logiqs_raw_data';
    RAISE NOTICE '⚡ Created: SQL triggers (Bronze → Silver automatic transformation)';
    RAISE NOTICE '📈 Created: Health monitoring view';
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Next Steps:';
    RAISE NOTICE '   1. Verify triggers: SELECT * FROM silver_health;';
    RAISE NOTICE '   2. Test with existing Bronze data (triggers will process automatically)';
    RAISE NOTICE '   3. Check Silver tables: SELECT * FROM tax_years WHERE case_id = ''1295022'';';
END $$;

