-- ============================================================================
-- Migration: 005_bronze_pdf_metadata_table.sql
-- Purpose: Create bronze_pdf_raw table for PDF metadata
-- Dependencies: 
--   - 001_create_bronze_tables.sql
--   - 004_create_pdf_storage_bucket.sql
-- Author: Tax Resolution Team
-- Date: 2025-11-22
-- ============================================================================
-- Tables Created:
--   - bronze_pdf_raw (PDF metadata and storage paths)
-- ============================================================================
-- Rollback:
--   DROP TABLE bronze_pdf_raw;
-- ============================================================================

-- ============================================================================
-- 1. Create bronze_pdf_raw Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS bronze_pdf_raw (
  -- Primary identifier
  bronze_pdf_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Case identifier
  case_id TEXT NOT NULL,
  
  -- Document metadata
  document_type TEXT NOT NULL CHECK (document_type IN ('AT', 'WI', 'TRT', 'Interview', 'Other')),
  tax_year TEXT,
  form_type TEXT,
  
  -- Storage information
  storage_path TEXT NOT NULL UNIQUE,  -- Path in Supabase Storage: case-pdfs/{case_id}/{type}/{filename}
  storage_bucket TEXT NOT NULL DEFAULT 'case-pdfs',
  file_size_bytes BIGINT,
  file_name TEXT NOT NULL,
  mime_type TEXT DEFAULT 'application/pdf',
  
  -- Source information
  source_system TEXT NOT NULL CHECK (source_system IN ('casehelper', 'manual_upload', 'tiparser', 'other')),
  source_url TEXT,  -- Original URL where PDF was downloaded from
  download_metadata JSONB,  -- Additional metadata about the download
  
  -- Processing status
  processing_status TEXT DEFAULT 'stored' CHECK (processing_status IN ('stored', 'parsed', 'failed')),
  parsed_bronze_id UUID,  -- Link to bronze_at_raw/wi_raw/trt_raw after parsing
  processing_error TEXT,
  
  -- File hash for deduplication
  file_hash TEXT,  -- SHA-256 hash of file content
  
  -- Timestamps
  inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  parsed_at TIMESTAMP WITH TIME ZONE,
  
  -- Indexes for common queries
  CONSTRAINT fk_parsed_bronze_id FOREIGN KEY (parsed_bronze_id) REFERENCES bronze_at_raw(bronze_id) ON DELETE SET NULL
);

-- ============================================================================
-- 3. Indexes for Performance
-- ============================================================================

CREATE INDEX idx_bronze_pdf_case_id ON bronze_pdf_raw(case_id);
CREATE INDEX idx_bronze_pdf_document_type ON bronze_pdf_raw(document_type);
CREATE INDEX idx_bronze_pdf_processing_status ON bronze_pdf_raw(processing_status);
CREATE INDEX idx_bronze_pdf_file_hash ON bronze_pdf_raw(file_hash);
CREATE INDEX idx_bronze_pdf_inserted_at ON bronze_pdf_raw(inserted_at DESC);
CREATE INDEX idx_bronze_pdf_storage_path ON bronze_pdf_raw(storage_path);

-- ============================================================================
-- 4. Comments for Documentation
-- ============================================================================

COMMENT ON TABLE bronze_pdf_raw IS 'Stores metadata and storage paths for raw PDF files downloaded from external systems. Provides audit trail and ability to re-parse documents.';
COMMENT ON COLUMN bronze_pdf_raw.bronze_pdf_id IS 'Unique identifier for this PDF record';
COMMENT ON COLUMN bronze_pdf_raw.case_id IS 'Case identifier (numeric or UUID format)';
COMMENT ON COLUMN bronze_pdf_raw.document_type IS 'Type of document: AT (Account Transcript), WI (Wage & Income), TRT (Tax Return Transcript), Interview, Other';
COMMENT ON COLUMN bronze_pdf_raw.storage_path IS 'Path in Supabase Storage bucket where PDF is stored';
COMMENT ON COLUMN bronze_pdf_raw.file_hash IS 'SHA-256 hash of PDF content for deduplication and integrity verification';
COMMENT ON COLUMN bronze_pdf_raw.parsed_bronze_id IS 'Foreign key to bronze_*_raw table after PDF has been parsed by TiParser';
COMMENT ON COLUMN bronze_pdf_raw.source_system IS 'System where PDF was downloaded from (casehelper, manual_upload, etc)';
COMMENT ON COLUMN bronze_pdf_raw.download_metadata IS 'JSON metadata about download: timestamp, user, response headers, etc';

-- ============================================================================
-- 5. Helper Functions
-- ============================================================================

-- Function: Get PDF download URL
CREATE OR REPLACE FUNCTION get_pdf_download_url(p_bronze_pdf_id UUID)
RETURNS TEXT AS $$
DECLARE
  v_storage_path TEXT;
  v_bucket TEXT;
BEGIN
  SELECT storage_path, storage_bucket
  INTO v_storage_path, v_bucket
  FROM bronze_pdf_raw
  WHERE bronze_pdf_id = p_bronze_pdf_id;
  
  IF v_storage_path IS NULL THEN
    RETURN NULL;
  END IF;
  
  -- Return the storage path (client will need to generate signed URL)
  RETURN v_storage_path;
END;
$$ LANGUAGE plpgsql;

-- Function: Mark PDF as parsed and link to parsed data
CREATE OR REPLACE FUNCTION link_pdf_to_parsed_data(
  p_bronze_pdf_id UUID,
  p_parsed_bronze_id UUID
)
RETURNS VOID AS $$
BEGIN
  UPDATE bronze_pdf_raw
  SET 
    parsed_bronze_id = p_parsed_bronze_id,
    processing_status = 'parsed',
    parsed_at = NOW()
  WHERE bronze_pdf_id = p_bronze_pdf_id;
END;
$$ LANGUAGE plpgsql;

-- Function: Get all PDFs for a case
CREATE OR REPLACE FUNCTION get_case_pdfs(p_case_id TEXT)
RETURNS TABLE (
  bronze_pdf_id UUID,
  document_type TEXT,
  file_name TEXT,
  storage_path TEXT,
  file_size_bytes BIGINT,
  processing_status TEXT,
  inserted_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    bpr.bronze_pdf_id,
    bpr.document_type,
    bpr.file_name,
    bpr.storage_path,
    bpr.file_size_bytes,
    bpr.processing_status,
    bpr.inserted_at
  FROM bronze_pdf_raw bpr
  WHERE bpr.case_id = p_case_id
  ORDER BY bpr.inserted_at DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 6. Monitoring View
-- ============================================================================

CREATE OR REPLACE VIEW bronze_pdf_health AS
SELECT 
  document_type,
  processing_status,
  COUNT(*) as pdf_count,
  SUM(file_size_bytes) as total_size_bytes,
  AVG(file_size_bytes) as avg_size_bytes,
  MIN(inserted_at) as oldest_pdf,
  MAX(inserted_at) as newest_pdf
FROM bronze_pdf_raw
GROUP BY document_type, processing_status
ORDER BY document_type, processing_status;

COMMENT ON VIEW bronze_pdf_health IS 'Monitoring view showing PDF storage statistics by document type and processing status';

-- ============================================================================
-- Migration Complete
-- ============================================================================

-- Verify table creation
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'bronze_pdf_raw') THEN
    RAISE NOTICE '✅ bronze_pdf_raw table created successfully';
  ELSE
    RAISE EXCEPTION '❌ Failed to create bronze_pdf_raw table';
  END IF;
END $$;

