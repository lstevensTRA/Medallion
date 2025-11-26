-- ============================================================================
-- SUPER SIMPLE: Just Bronze Tables (No Triggers)
-- ============================================================================

-- Drop old tables
DROP TABLE IF EXISTS bronze_pdf_raw CASCADE;
DROP TABLE IF EXISTS bronze_interview_raw CASCADE;
DROP TABLE IF EXISTS bronze_trt_raw CASCADE;
DROP TABLE IF EXISTS bronze_wi_raw CASCADE;
DROP TABLE IF EXISTS bronze_at_raw CASCADE;

-- Create Bronze AT table
CREATE TABLE bronze_at_raw (
    bronze_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id TEXT NOT NULL,
    raw_response JSONB NOT NULL,
    inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create Bronze WI table
CREATE TABLE bronze_wi_raw (
    bronze_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id TEXT NOT NULL,
    raw_response JSONB NOT NULL,
    inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create Bronze TRT table
CREATE TABLE bronze_trt_raw (
    bronze_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id TEXT NOT NULL,
    raw_response JSONB NOT NULL,
    inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create Bronze Interview table
CREATE TABLE bronze_interview_raw (
    bronze_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id TEXT NOT NULL,
    raw_response JSONB NOT NULL,
    inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create Bronze PDF metadata table
CREATE TABLE bronze_pdf_raw (
    pdf_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id TEXT NOT NULL,
    document_type TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_size BIGINT,
    downloaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add indexes
CREATE INDEX idx_bronze_at_case_id ON bronze_at_raw(case_id);
CREATE INDEX idx_bronze_wi_case_id ON bronze_wi_raw(case_id);
CREATE INDEX idx_bronze_trt_case_id ON bronze_trt_raw(case_id);
CREATE INDEX idx_bronze_interview_case_id ON bronze_interview_raw(case_id);
CREATE INDEX idx_bronze_pdf_case_id ON bronze_pdf_raw(case_id);

-- Done!
SELECT 'Bronze tables created successfully!' as status;

