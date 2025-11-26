-- ============================================================================
-- Diagnose and Fix Bronze → Silver Triggers
-- ============================================================================
-- Run this in Supabase SQL Editor to diagnose and fix trigger issues
-- ============================================================================

-- STEP 1: Check if triggers exist
SELECT 
    tgname as trigger_name,
    tgrelid::regclass as table_name,
    tgenabled,
    CASE tgenabled
        WHEN 'O' THEN 'Enabled'
        WHEN 'D' THEN 'Disabled'
        WHEN 'R' THEN 'Replica'
        WHEN 'A' THEN 'Always'
        ELSE 'Unknown'
    END as status
FROM pg_trigger
WHERE tgname LIKE 'trigger_bronze%'
ORDER BY tgname;

-- STEP 2: Check if ensure_case function exists
SELECT 
    proname as function_name,
    pg_get_functiondef(oid) as function_definition
FROM pg_proc
WHERE proname = 'ensure_case';

-- STEP 3: Test ensure_case function
SELECT ensure_case('1295022') as case_uuid;

-- STEP 4: Check Bronze data
SELECT 
    'bronze_at_raw' as table_name,
    COUNT(*) as record_count,
    MIN(inserted_at) as oldest,
    MAX(inserted_at) as newest
FROM bronze_at_raw
WHERE case_id = '1295022'
UNION ALL
SELECT 
    'bronze_wi_raw',
    COUNT(*),
    MIN(inserted_at),
    MAX(inserted_at)
FROM bronze_wi_raw
WHERE case_id = '1295022';

-- STEP 5: Check Silver data (should be populated by triggers)
SELECT 
    'tax_years' as table_name,
    COUNT(*) as record_count
FROM tax_years t
JOIN cases c ON t.case_id = c.id
WHERE c.case_number = '1295022'
UNION ALL
SELECT 
    'income_documents',
    COUNT(*)
FROM income_documents i
JOIN cases c ON i.case_id = c.id
WHERE c.case_number = '1295022';

-- STEP 6: If triggers don't exist, create them
-- (This will be done in a separate migration if needed)

-- STEP 7: Enable triggers if they're disabled
DO $$
BEGIN
    -- Enable Bronze → Silver triggers
    ALTER TABLE bronze_at_raw ENABLE TRIGGER trigger_bronze_at_to_silver;
    ALTER TABLE bronze_wi_raw ENABLE TRIGGER trigger_bronze_wi_to_silver;
    ALTER TABLE bronze_trt_raw ENABLE TRIGGER trigger_bronze_trt_to_silver;
    ALTER TABLE bronze_interview_raw ENABLE TRIGGER trigger_bronze_interview_to_silver;
    
    RAISE NOTICE '✅ Triggers enabled';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '⚠️  Could not enable triggers: %', SQLERRM;
END $$;

-- STEP 8: Manually test trigger by re-inserting a Bronze record
-- (This will fire the trigger and populate Silver)
-- Uncomment to test:
/*
DO $$
DECLARE
    v_bronze_record RECORD;
BEGIN
    -- Get a Bronze AT record
    SELECT * INTO v_bronze_record
    FROM bronze_at_raw
    WHERE case_id = '1295022'
    LIMIT 1;
    
    -- Re-insert to fire trigger
    INSERT INTO bronze_at_raw (case_id, raw_response, api_source)
    VALUES (v_bronze_record.case_id, v_bronze_record.raw_response, v_bronze_record.api_source);
    
    RAISE NOTICE '✅ Test insert completed - check Silver tables';
END $$;
*/

