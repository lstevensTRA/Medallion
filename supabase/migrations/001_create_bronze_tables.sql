-- ============================================================================
-- Migration: 001_create_bronze_tables.sql
-- Purpose: Create Bronze layer tables for raw API response storage
-- Dependencies: Requires existing cases table
-- Author: Tax Resolution Medallion Architecture
-- Date: 2024-11-21
-- ============================================================================
-- Tables Created:
--   - bronze_at_raw (Account Transcript responses)
--   - bronze_wi_raw (Wage & Income responses)
--   - bronze_trt_raw (Tax Return Transcript responses)
--   - bronze_interview_raw (CaseHelper Interview responses)
-- ============================================================================
-- Rollback:
--   DROP TABLE IF EXISTS bronze_interview_raw;
--   DROP TABLE IF EXISTS bronze_trt_raw;
--   DROP TABLE IF EXISTS bronze_wi_raw;
--   DROP TABLE IF EXISTS bronze_at_raw;
-- ============================================================================

-- ============================================================================
-- === BRONZE: ACCOUNT TRANSCRIPT (AT) ========================================
-- ============================================================================

CREATE TABLE IF NOT EXISTS bronze_at_raw (
  -- Primary Key
  bronze_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Foreign Key (text for flexibility - can link to case_number or cases.id)
  case_id TEXT NOT NULL,
  
  -- Raw API Response (stores entire JSON as-is)
  raw_response JSONB NOT NULL,
  
  -- Metadata
  api_source TEXT DEFAULT 'tiparser',
  api_endpoint TEXT,
  api_version TEXT,
  
  -- Timestamps
  inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  processed_at TIMESTAMP WITH TIME ZONE, -- Set when Silver trigger completes
  
  -- Processing Status
  processing_status TEXT DEFAULT 'pending' CHECK (processing_status IN ('pending', 'processing', 'completed', 'failed')),
  processing_error TEXT,
  
  -- Audit Trail
  created_by TEXT DEFAULT 'system',
  source_system TEXT DEFAULT 'tiparser'
);

-- Indexes for performance
CREATE INDEX idx_bronze_at_case_id ON bronze_at_raw(case_id);
CREATE INDEX idx_bronze_at_inserted_at ON bronze_at_raw(inserted_at);
CREATE INDEX idx_bronze_at_processing_status ON bronze_at_raw(processing_status);
CREATE INDEX idx_bronze_at_raw_response_gin ON bronze_at_raw USING GIN (raw_response);

-- Comments
COMMENT ON TABLE bronze_at_raw IS 'Bronze layer: Raw Account Transcript responses from TiParser API. Stores complete JSON for replay ability.';
COMMENT ON COLUMN bronze_at_raw.raw_response IS 'Complete JSON response from TiParser /analysis/at endpoint. Never modified.';
COMMENT ON COLUMN bronze_at_raw.processing_status IS 'Status of Bronze → Silver trigger processing';
COMMENT ON COLUMN bronze_at_raw.processed_at IS 'Timestamp when Silver layer was successfully populated';

-- ============================================================================
-- === BRONZE: WAGE & INCOME (WI) =============================================
-- ============================================================================

CREATE TABLE IF NOT EXISTS bronze_wi_raw (
  -- Primary Key
  bronze_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Foreign Key
  case_id TEXT NOT NULL,
  
  -- Raw API Response
  raw_response JSONB NOT NULL,
  
  -- Metadata
  api_source TEXT DEFAULT 'tiparser',
  api_endpoint TEXT,
  api_version TEXT,
  
  -- Timestamps
  inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  processed_at TIMESTAMP WITH TIME ZONE,
  
  -- Processing Status
  processing_status TEXT DEFAULT 'pending' CHECK (processing_status IN ('pending', 'processing', 'completed', 'failed')),
  processing_error TEXT,
  
  -- Audit Trail
  created_by TEXT DEFAULT 'system',
  source_system TEXT DEFAULT 'tiparser'
);

-- Indexes
CREATE INDEX idx_bronze_wi_case_id ON bronze_wi_raw(case_id);
CREATE INDEX idx_bronze_wi_inserted_at ON bronze_wi_raw(inserted_at);
CREATE INDEX idx_bronze_wi_processing_status ON bronze_wi_raw(processing_status);
CREATE INDEX idx_bronze_wi_raw_response_gin ON bronze_wi_raw USING GIN (raw_response);

-- Comments
COMMENT ON TABLE bronze_wi_raw IS 'Bronze layer: Raw Wage & Income responses from TiParser API. Stores W-2, 1099, and other income form data.';
COMMENT ON COLUMN bronze_wi_raw.raw_response IS 'Complete JSON response from TiParser /analysis/wi endpoint. Includes all form variations.';

-- ============================================================================
-- === BRONZE: TAX RETURN TRANSCRIPT (TRT) ====================================
-- ============================================================================

CREATE TABLE IF NOT EXISTS bronze_trt_raw (
  -- Primary Key
  bronze_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Foreign Key
  case_id TEXT NOT NULL,
  
  -- Raw API Response
  raw_response JSONB NOT NULL,
  
  -- Metadata
  api_source TEXT DEFAULT 'tiparser',
  api_endpoint TEXT,
  api_version TEXT,
  
  -- Timestamps
  inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  processed_at TIMESTAMP WITH TIME ZONE,
  
  -- Processing Status
  processing_status TEXT DEFAULT 'pending' CHECK (processing_status IN ('pending', 'processing', 'completed', 'failed')),
  processing_error TEXT,
  
  -- Audit Trail
  created_by TEXT DEFAULT 'system',
  source_system TEXT DEFAULT 'tiparser'
);

-- Indexes
CREATE INDEX idx_bronze_trt_case_id ON bronze_trt_raw(case_id);
CREATE INDEX idx_bronze_trt_inserted_at ON bronze_trt_raw(inserted_at);
CREATE INDEX idx_bronze_trt_processing_status ON bronze_trt_raw(processing_status);
CREATE INDEX idx_bronze_trt_raw_response_gin ON bronze_trt_raw USING GIN (raw_response);

-- Comments
COMMENT ON TABLE bronze_trt_raw IS 'Bronze layer: Raw Tax Return Transcript responses from TiParser API. Contains Schedule C, E, expenses, deductions.';
COMMENT ON COLUMN bronze_trt_raw.raw_response IS 'Complete JSON response from TiParser /analysis/trt endpoint. Includes all form schedules.';

-- ============================================================================
-- === BRONZE: INTERVIEW DATA (CASEHELPER) ====================================
-- ============================================================================

CREATE TABLE IF NOT EXISTS bronze_interview_raw (
  -- Primary Key
  bronze_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Foreign Key
  case_id TEXT NOT NULL,
  
  -- Raw API Response
  raw_response JSONB NOT NULL,
  
  -- Metadata
  api_source TEXT DEFAULT 'casehelper',
  api_endpoint TEXT,
  api_version TEXT,
  
  -- Timestamps
  inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  processed_at TIMESTAMP WITH TIME ZONE,
  
  -- Processing Status
  processing_status TEXT DEFAULT 'pending' CHECK (processing_status IN ('pending', 'processing', 'completed', 'failed')),
  processing_error TEXT,
  
  -- Audit Trail
  created_by TEXT DEFAULT 'system',
  source_system TEXT DEFAULT 'casehelper'
);

-- Indexes
CREATE INDEX idx_bronze_interview_case_id ON bronze_interview_raw(case_id);
CREATE INDEX idx_bronze_interview_inserted_at ON bronze_interview_raw(inserted_at);
CREATE INDEX idx_bronze_interview_processing_status ON bronze_interview_raw(processing_status);
CREATE INDEX idx_bronze_interview_raw_response_gin ON bronze_interview_raw USING GIN (raw_response);

-- Comments
COMMENT ON TABLE bronze_interview_raw IS 'Bronze layer: Raw Interview responses from CaseHelper API. Contains employment, assets, income, expenses data.';
COMMENT ON COLUMN bronze_interview_raw.raw_response IS 'Complete JSON response from CaseHelper /api/cases/{id}/interview endpoint. Includes 100+ fields.';

-- ============================================================================
-- === HELPER FUNCTIONS =======================================================
-- ============================================================================

-- Function: Mark Bronze record as processed
CREATE OR REPLACE FUNCTION mark_bronze_processed(
  p_table_name TEXT,
  p_bronze_id UUID,
  p_status TEXT DEFAULT 'completed',
  p_error TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  EXECUTE format(
    'UPDATE %I SET processing_status = $1, processed_at = NOW(), processing_error = $2 WHERE bronze_id = $3',
    p_table_name
  ) USING p_status, p_error, p_bronze_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION mark_bronze_processed IS 'Helper function to update Bronze record processing status after trigger completes';

-- Function: Get unprocessed Bronze records
CREATE OR REPLACE FUNCTION get_unprocessed_bronze_records(
  p_table_name TEXT,
  p_limit INTEGER DEFAULT 100
) RETURNS TABLE (
  bronze_id UUID,
  case_id TEXT,
  raw_response JSONB,
  inserted_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY EXECUTE format(
    'SELECT bronze_id, case_id, raw_response, inserted_at FROM %I WHERE processing_status = ''pending'' ORDER BY inserted_at LIMIT $1',
    p_table_name
  ) USING p_limit;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_unprocessed_bronze_records IS 'Retrieve Bronze records that have not been processed to Silver yet';

-- ============================================================================
-- === DATA QUALITY VIEWS =====================================================
-- ============================================================================

-- View: Bronze ingestion summary
CREATE OR REPLACE VIEW bronze_ingestion_summary AS
SELECT 
  'AT' as data_type,
  COUNT(*) as total_records,
  COUNT(*) FILTER (WHERE processing_status = 'completed') as processed,
  COUNT(*) FILTER (WHERE processing_status = 'pending') as pending,
  COUNT(*) FILTER (WHERE processing_status = 'failed') as failed,
  MIN(inserted_at) as first_ingestion,
  MAX(inserted_at) as last_ingestion
FROM bronze_at_raw
UNION ALL
SELECT 
  'WI' as data_type,
  COUNT(*) as total_records,
  COUNT(*) FILTER (WHERE processing_status = 'completed') as processed,
  COUNT(*) FILTER (WHERE processing_status = 'pending') as pending,
  COUNT(*) FILTER (WHERE processing_status = 'failed') as failed,
  MIN(inserted_at) as first_ingestion,
  MAX(inserted_at) as last_ingestion
FROM bronze_wi_raw
UNION ALL
SELECT 
  'TRT' as data_type,
  COUNT(*) as total_records,
  COUNT(*) FILTER (WHERE processing_status = 'completed') as processed,
  COUNT(*) FILTER (WHERE processing_status = 'pending') as pending,
  COUNT(*) FILTER (WHERE processing_status = 'failed') as failed,
  MIN(inserted_at) as first_ingestion,
  MAX(inserted_at) as last_ingestion
FROM bronze_trt_raw
UNION ALL
SELECT 
  'Interview' as data_type,
  COUNT(*) as total_records,
  COUNT(*) FILTER (WHERE processing_status = 'completed') as processed,
  COUNT(*) FILTER (WHERE processing_status = 'pending') as pending,
  COUNT(*) FILTER (WHERE processing_status = 'failed') as failed,
  MIN(inserted_at) as first_ingestion,
  MAX(inserted_at) as last_ingestion
FROM bronze_interview_raw;

COMMENT ON VIEW bronze_ingestion_summary IS 'Summary of Bronze layer ingestion and processing status across all data types';

-- ============================================================================
-- === GRANTS (Optional - adjust based on your security model) ================
-- ============================================================================

-- Grant read access to authenticated users (adjust as needed)
-- ALTER TABLE bronze_at_raw ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE bronze_wi_raw ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE bronze_trt_raw ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE bronze_interview_raw ENABLE ROW LEVEL SECURITY;

-- Example RLS policy (uncomment and adjust as needed):
-- CREATE POLICY "Users can view their own case Bronze data" ON bronze_at_raw
--   FOR SELECT
--   USING (auth.uid() IN (SELECT user_id FROM cases WHERE case_number = bronze_at_raw.case_id));

-- ============================================================================
-- === VALIDATION =============================================================
-- ============================================================================

-- Verify tables created successfully
DO $$
DECLARE
  table_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO table_count
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_name IN ('bronze_at_raw', 'bronze_wi_raw', 'bronze_trt_raw', 'bronze_interview_raw');
  
  IF table_count = 4 THEN
    RAISE NOTICE '✅ Bronze layer tables created successfully: 4/4 tables';
  ELSE
    RAISE WARNING '⚠️  Expected 4 Bronze tables, found %', table_count;
  END IF;
END $$;

-- ============================================================================
-- Migration Complete
-- ============================================================================
-- Next Steps:
-- 1. Apply this migration: supabase db push
-- 2. Verify tables: SELECT * FROM bronze_ingestion_summary;
-- 3. Create Bronze → Silver triggers (002_bronze_to_silver_triggers.sql)
-- 4. Modify Python code to insert into Bronze tables
-- ============================================================================

