-- ============================================================================
-- SQL Cleanup Script: Remove Duplicate PDFs (Safe Version)
-- Purpose: Clean up duplicate PDF records in pdf_documents and bronze_pdf_raw
-- Date: 2025-01-28
-- Tables: pdf_documents, bronze_pdf_raw
-- Storage Bucket: case-pdfs
-- This version checks for table existence before running queries
-- ============================================================================

-- ============================================================================
-- STEP 1: Check which tables exist
-- ============================================================================

DO $$
DECLARE
    v_pdf_docs_exists BOOLEAN;
    v_bronze_pdf_exists BOOLEAN;
BEGIN
    -- Check if tables exist
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'pdf_documents'
    ) INTO v_pdf_docs_exists;
    
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'bronze_pdf_raw'
    ) INTO v_bronze_pdf_exists;
    
    RAISE NOTICE '📋 Table existence check:';
    RAISE NOTICE '   pdf_documents: %', CASE WHEN v_pdf_docs_exists THEN '✅ EXISTS' ELSE '❌ NOT FOUND' END;
    RAISE NOTICE '   bronze_pdf_raw: %', CASE WHEN v_bronze_pdf_exists THEN '✅ EXISTS' ELSE '❌ NOT FOUND' END;
END $$;

-- ============================================================================
-- STEP 2: Find and report duplicates in pdf_documents (if exists)
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'pdf_documents') THEN
        RAISE NOTICE '';
        RAISE NOTICE '📊 Checking pdf_documents for duplicates...';
    END IF;
END $$;

-- Show duplicates by file_path
SELECT 
    'pdf_documents duplicates by file_path' as table_name,
    file_path,
    COUNT(*) as duplicate_count,
    STRING_AGG(id::TEXT, ', ' ORDER BY uploaded_at) as duplicate_ids,
    STRING_AGG(file_name, ', ' ORDER BY uploaded_at) as file_names
FROM public.pdf_documents
GROUP BY file_path
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC, file_path;

-- Show duplicates by (case_id, file_name)
SELECT 
    'pdf_documents duplicates by case_id + file_name' as table_name,
    case_id,
    file_name,
    COUNT(*) as duplicate_count,
    STRING_AGG(id::TEXT, ', ' ORDER BY uploaded_at) as duplicate_ids,
    STRING_AGG(uploaded_at::TEXT, ', ' ORDER BY uploaded_at) as upload_times
FROM public.pdf_documents
GROUP BY case_id, file_name
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC, case_id, file_name;

-- ============================================================================
-- STEP 3: Remove duplicates from pdf_documents (keep oldest)
-- ============================================================================

DO $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'pdf_documents') THEN
        -- Delete duplicates by file_path (keep the first one)
        DELETE FROM public.pdf_documents
        WHERE id IN (
            SELECT id
            FROM (
                SELECT 
                    id,
                    ROW_NUMBER() OVER (PARTITION BY file_path ORDER BY uploaded_at ASC) as rn
                FROM public.pdf_documents
            ) ranked
            WHERE rn > 1
        );
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✅ Deleted % pdf_documents duplicates by file_path', v_deleted_count;

        -- Delete duplicates by (case_id, file_name) (keep the first one)
        DELETE FROM public.pdf_documents
        WHERE id IN (
            SELECT id
            FROM (
                SELECT 
                    id,
                    ROW_NUMBER() OVER (PARTITION BY case_id, file_name ORDER BY uploaded_at ASC) as rn
                FROM public.pdf_documents
            ) ranked
            WHERE rn > 1
        );
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✅ Deleted % pdf_documents duplicates by case_id + file_name', v_deleted_count;
    ELSE
        RAISE NOTICE '⚠️  pdf_documents table does not exist - skipping cleanup';
    END IF;
END $$;

-- ============================================================================
-- STEP 4: Find and report duplicates in bronze_pdf_raw (if exists)
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'bronze_pdf_raw') THEN
        RAISE NOTICE '';
        RAISE NOTICE '📊 Checking bronze_pdf_raw for duplicates...';
    END IF;
END $$;

-- Show duplicates by (case_id, file_name) - skipped, will show in summary

-- ============================================================================
-- STEP 5: Remove duplicates from bronze_pdf_raw (keep oldest)
-- ============================================================================

DO $$
DECLARE
    v_pdf_id_col TEXT;
    v_deleted_count INTEGER;
    v_sql TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'bronze_pdf_raw') THEN
        -- Determine which ID column exists
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'bronze_pdf_raw' AND column_name = 'pdf_id') THEN
            v_pdf_id_col := 'pdf_id';
        ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'bronze_pdf_raw' AND column_name = 'bronze_pdf_id') THEN
            v_pdf_id_col := 'bronze_pdf_id';
        ELSE
            v_pdf_id_col := 'id';
        END IF;
        
        -- Delete duplicates by (case_id, file_name) (keep the first one)
        v_sql := format('
            DELETE FROM public.bronze_pdf_raw
            WHERE %I IN (
                SELECT %I
                FROM (
                    SELECT 
                        %I as record_id,
                        ROW_NUMBER() OVER (
                            PARTITION BY case_id, file_name 
                            ORDER BY COALESCE(inserted_at, downloaded_at, NOW()) ASC
                        ) as rn
                    FROM public.bronze_pdf_raw
                ) ranked
                WHERE rn > 1
            )', v_pdf_id_col, v_pdf_id_col, v_pdf_id_col);
        
        EXECUTE v_sql;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✅ Deleted % bronze_pdf_raw duplicates', v_deleted_count;
    ELSE
        RAISE NOTICE '⚠️  bronze_pdf_raw table does not exist - skipping cleanup';
    END IF;
END $$;

-- ============================================================================
-- STEP 6: Add unique constraints to prevent future duplicates
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'pdf_documents') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint 
            WHERE conname = 'pdf_documents_case_file_unique'
            AND conrelid = 'public.pdf_documents'::regclass
        ) THEN
            ALTER TABLE public.pdf_documents
            ADD CONSTRAINT pdf_documents_case_file_unique 
            UNIQUE (case_id, file_name);
            
            RAISE NOTICE '✅ Added unique constraint on pdf_documents(case_id, file_name)';
        ELSE
            RAISE NOTICE 'ℹ️  Unique constraint pdf_documents_case_file_unique already exists';
        END IF;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'bronze_pdf_raw') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint 
            WHERE conname = 'bronze_pdf_raw_case_file_unique'
            AND conrelid = 'public.bronze_pdf_raw'::regclass
        ) THEN
            ALTER TABLE public.bronze_pdf_raw
            ADD CONSTRAINT bronze_pdf_raw_case_file_unique 
            UNIQUE (case_id, file_name);
            
            RAISE NOTICE '✅ Added unique constraint on bronze_pdf_raw(case_id, file_name)';
        ELSE
            RAISE NOTICE 'ℹ️  Unique constraint bronze_pdf_raw_case_file_unique already exists';
        END IF;
    END IF;
END $$;

-- ============================================================================
-- STEP 7: Summary report (only for tables that exist)
-- ============================================================================

DO $$
DECLARE
    v_pdf_docs_count INTEGER;
    v_pdf_docs_duplicates INTEGER;
    v_bronze_count INTEGER;
    v_bronze_duplicates INTEGER;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '📊 Cleanup Summary:';
    
    -- Summary for pdf_documents
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'pdf_documents') THEN
        SELECT 
            COUNT(*),
            COUNT(*) - COUNT(DISTINCT (case_id, file_name))
        INTO v_pdf_docs_count, v_pdf_docs_duplicates
        FROM public.pdf_documents;
        
        RAISE NOTICE '   pdf_documents: % total records, % duplicates', v_pdf_docs_count, v_pdf_docs_duplicates;
    ELSE
        RAISE NOTICE '   pdf_documents: table does not exist';
    END IF;
    
    -- Summary for bronze_pdf_raw
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'bronze_pdf_raw') THEN
        SELECT 
            COUNT(*),
            COUNT(*) - COUNT(DISTINCT (case_id, file_name))
        INTO v_bronze_count, v_bronze_duplicates
        FROM public.bronze_pdf_raw;
        
        RAISE NOTICE '   bronze_pdf_raw: % total records, % duplicates', v_bronze_count, v_bronze_duplicates;
    ELSE
        RAISE NOTICE '   bronze_pdf_raw: table does not exist';
    END IF;
END $$;

-- ============================================================================
-- END OF CLEANUP SCRIPT
-- ============================================================================

