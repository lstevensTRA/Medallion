-- ============================================================================
-- Process Existing Bronze Records to Populate Silver
-- ============================================================================
-- This manually processes existing Bronze records that weren't processed by triggers
-- Run this in Supabase SQL Editor
-- ============================================================================

-- Get case UUID
DO $$
DECLARE
    v_case_uuid UUID;
    v_bronze_id UUID;
    v_case_id TEXT;
    v_raw_response JSONB;
    v_api_source TEXT;
    v_processed INTEGER := 0;
BEGIN
    -- Get case UUID
    SELECT id INTO v_case_uuid
    FROM cases
    WHERE case_number = '1295022';
    
    IF v_case_uuid IS NULL THEN
        RAISE NOTICE '❌ Case not found';
        RETURN;
    END IF;
    
    RAISE NOTICE '✅ Case UUID: %', v_case_uuid;
    RAISE NOTICE '';
    
    -- Process Bronze AT records
    RAISE NOTICE '🔄 Processing Bronze AT records...';
    
    FOR v_bronze_id, v_case_id, v_raw_response IN 
        SELECT bronze_id, case_id, raw_response
        FROM bronze_at_raw
        WHERE case_id = '1295022'
    LOOP
        BEGIN
            -- Manually insert a new record to fire the trigger
            -- Use a unique identifier to avoid conflicts
            INSERT INTO bronze_at_raw (
                case_id,
                raw_response
            )
            VALUES (
                v_case_id,
                v_raw_response
            );
            
            v_processed := v_processed + 1;
            RAISE NOTICE '   ✅ Triggered processing for Bronze AT: %', v_bronze_id;
        EXCEPTION
            WHEN unique_violation THEN
                -- Record already exists, that's okay
                RAISE NOTICE '   ℹ️  Record already processed: %', v_bronze_id;
            WHEN OTHERS THEN
                RAISE NOTICE '   ⚠️  Error processing %: %', v_bronze_id, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE '✅ Processed % Bronze AT records', v_processed;
    RAISE NOTICE '';
    
    -- Process Bronze WI records
    RAISE NOTICE '🔄 Processing Bronze WI records...';
    v_processed := 0;
    
    FOR v_bronze_id, v_case_id, v_raw_response IN 
        SELECT bronze_id, case_id, raw_response
        FROM bronze_wi_raw
        WHERE case_id = '1295022'
    LOOP
        BEGIN
            INSERT INTO bronze_wi_raw (
                case_id,
                raw_response
            )
            VALUES (
                v_case_id,
                v_raw_response
            );
            
            v_processed := v_processed + 1;
            RAISE NOTICE '   ✅ Triggered processing for Bronze WI: %', v_bronze_id;
        EXCEPTION
            WHEN unique_violation THEN
                RAISE NOTICE '   ℹ️  Record already processed: %', v_bronze_id;
            WHEN OTHERS THEN
                RAISE NOTICE '   ⚠️  Error processing %: %', v_bronze_id, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE '✅ Processed % Bronze WI records', v_processed;
    RAISE NOTICE '';
    RAISE NOTICE '⏳ Waiting 2 seconds for triggers to process...';
    PERFORM pg_sleep(2);
    RAISE NOTICE '';
    RAISE NOTICE '📊 Checking results...';
END $$;

-- Check results
SELECT 
    'tax_years' as table_name,
    COUNT(*) as record_count
FROM tax_years t
JOIN cases c ON t.case_id = c.id
WHERE c.case_number = '1295022'
UNION ALL
SELECT 
    'account_activity',
    COUNT(*)
FROM account_activity a
JOIN tax_years t ON a.tax_year_id = t.id
JOIN cases c ON t.case_id = c.id
WHERE c.case_number = '1295022'
UNION ALL
SELECT 
    'income_documents',
    COUNT(*)
FROM income_documents i
JOIN tax_years t ON i.tax_year_id = t.id
JOIN cases c ON t.case_id = c.id
WHERE c.case_number = '1295022';

