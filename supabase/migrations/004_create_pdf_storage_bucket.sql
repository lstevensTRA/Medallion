-- ============================================================================
-- Migration: 004_create_pdf_storage_bucket.sql
-- Purpose: Create storage bucket for PDF files
-- Author: Tax Resolution Team
-- Date: 2025-11-22
-- ============================================================================

-- Create the storage bucket for PDFs
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'case-pdfs',
  'case-pdfs',
  false,  -- Private bucket
  52428800,  -- 50MB max file size
  ARRAY['application/pdf']::text[]  -- Only PDFs allowed
)
ON CONFLICT (id) DO NOTHING;

-- Enable RLS on storage.objects if not already enabled
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Allow authenticated uploads to case-pdfs" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated reads from case-pdfs" ON storage.objects;
DROP POLICY IF EXISTS "Service role full access to case-pdfs" ON storage.objects;

-- Policy: Allow authenticated users to upload PDFs to case-pdfs bucket
CREATE POLICY "Allow authenticated uploads to case-pdfs"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'case-pdfs');

-- Policy: Allow authenticated users to read PDFs from case-pdfs bucket
CREATE POLICY "Allow authenticated reads from case-pdfs"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'case-pdfs');

-- Policy: Allow service role full access
CREATE POLICY "Service role full access to case-pdfs"
ON storage.objects
FOR ALL
TO service_role
USING (bucket_id = 'case-pdfs')
WITH CHECK (bucket_id = 'case-pdfs');

-- Verify bucket creation
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'case-pdfs') THEN
    RAISE NOTICE '✅ Storage bucket "case-pdfs" created successfully';
  ELSE
    RAISE EXCEPTION '❌ Failed to create storage bucket "case-pdfs"';
  END IF;
END $$;

