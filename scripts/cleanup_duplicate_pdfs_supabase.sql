-- ============================================================================
-- SQL Cleanup Script: Remove Duplicate PDFs (Supabase Version)
-- Purpose: Clean up duplicate PDF records - RUN THIS IN SUPABASE SQL EDITOR
-- Date: 2025-01-28
-- Tables: pdf_documents, bronze_pdf_raw
-- ============================================================================
-- INSTRUCTIONS:
--   1. Go to Supabase Dashboard → SQL Editor
--   2. Paste this entire script
--   3. Click "Run"
-- ============================================================================

-- ============================================================================
-- STEP 1: Remove duplicates from pdf_documents (keep oldest)
-- ============================================================================

-- Delete duplicates by file_path (keep the first one)
DELETE FROM pdf_documents
WHERE id IN (
    SELECT id
    FROM (
        SELECT 
            id,
            ROW_NUMBER() OVER (PARTITION BY file_path ORDER BY uploaded_at ASC) as rn
        FROM pdf_documents
    ) ranked
    WHERE rn > 1
);

-- Delete duplicates by (case_id, file_name) (keep the first one)
DELETE FROM pdf_documents
WHERE id IN (
    SELECT id
    FROM (
        SELECT 
            id,
            ROW_NUMBER() OVER (PARTITION BY case_id, file_name ORDER BY uploaded_at ASC) as rn
        FROM pdf_documents
    ) ranked
    WHERE rn > 1
);

-- ============================================================================
-- STEP 2: Remove duplicates from bronze_pdf_raw (keep oldest)
-- ============================================================================

-- Delete duplicates by (case_id, file_name) (keep the first one)
-- Use pdf_id as the primary key (confirmed to exist)
-- Use downloaded_at for ordering (inserted_at doesn't exist)
DELETE FROM bronze_pdf_raw
WHERE pdf_id IN (
    SELECT pdf_id
    FROM (
        SELECT 
            pdf_id,
            ROW_NUMBER() OVER (
                PARTITION BY case_id, file_name 
                ORDER BY COALESCE(downloaded_at, NOW()) ASC
            ) as rn
        FROM bronze_pdf_raw
    ) ranked
    WHERE rn > 1
);

-- ============================================================================
-- STEP 3: Add unique constraints to prevent future duplicates
-- ============================================================================

-- Add unique constraint on pdf_documents (case_id, file_name) if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'pdf_documents_case_file_unique'
        AND conrelid = 'pdf_documents'::regclass
    ) THEN
        ALTER TABLE pdf_documents
        ADD CONSTRAINT pdf_documents_case_file_unique 
        UNIQUE (case_id, file_name);
    END IF;
END $$;

-- Add unique constraint on bronze_pdf_raw (case_id, file_name) if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'bronze_pdf_raw_case_file_unique'
        AND conrelid = 'bronze_pdf_raw'::regclass
    ) THEN
        ALTER TABLE bronze_pdf_raw
        ADD CONSTRAINT bronze_pdf_raw_case_file_unique 
        UNIQUE (case_id, file_name);
    END IF;
END $$;

-- ============================================================================
-- STEP 4: Show summary
-- ============================================================================

SELECT 
    'pdf_documents' as table_name,
    COUNT(*) as total_records,
    COUNT(DISTINCT (case_id, file_name)) as unique_case_files,
    COUNT(*) - COUNT(DISTINCT (case_id, file_name)) as remaining_duplicates
FROM pdf_documents

UNION ALL

SELECT 
    'bronze_pdf_raw' as table_name,
    COUNT(*) as total_records,
    COUNT(DISTINCT (case_id, file_name)) as unique_case_files,
    COUNT(*) - COUNT(DISTINCT (case_id, file_name)) as remaining_duplicates
FROM bronze_pdf_raw;

