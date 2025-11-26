-- ============================================================================
-- Force Silver Population from Bronze Records
-- ============================================================================
-- This manually processes Bronze records to populate Silver
-- Run this in Supabase SQL Editor
-- ============================================================================

-- Get case UUID
DO $$
DECLARE
    v_case_uuid UUID;
    v_bronze_record RECORD;
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
    RAISE NOTICE '🔄 Processing Bronze AT records...';
    
    -- Process each Bronze AT record
    FOR v_bronze_record IN 
        SELECT bronze_id, case_id, raw_response
        FROM bronze_at_raw
        WHERE case_id = '1295022'
    LOOP
        BEGIN
            -- Call the trigger function directly
            -- We need to create a NEW record context
            PERFORM process_bronze_at() FROM (
                SELECT 
                    v_bronze_record.bronze_id as bronze_id,
                    v_bronze_record.case_id as case_id,
                    v_bronze_record.raw_response as raw_response,
                    'tiparser' as api_source,
                    NOW() as inserted_at
            ) AS temp_bronze;
            
            v_processed := v_processed + 1;
            RAISE NOTICE '   ✅ Processed Bronze record: %', v_bronze_record.bronze_id;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE '   ⚠️  Error processing %: %', v_bronze_record.bronze_id, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE '';
    RAISE NOTICE '✅ Processed % Bronze AT records', v_processed;
    RAISE NOTICE '';
    RAISE NOTICE '🔄 Processing Bronze WI records...';
    
    v_processed := 0;
    
    -- Process each Bronze WI record
    FOR v_bronze_record IN 
        SELECT bronze_id, case_id, raw_response
        FROM bronze_wi_raw
        WHERE case_id = '1295022'
    LOOP
        BEGIN
            PERFORM process_bronze_wi() FROM (
                SELECT 
                    v_bronze_record.bronze_id as bronze_id,
                    v_bronze_record.case_id as case_id,
                    v_bronze_record.raw_response as raw_response,
                    'tiparser' as api_source,
                    NOW() as inserted_at
            ) AS temp_bronze;
            
            v_processed := v_processed + 1;
            RAISE NOTICE '   ✅ Processed Bronze record: %', v_bronze_record.bronze_id;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE '   ⚠️  Error processing %: %', v_bronze_record.bronze_id, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE '';
    RAISE NOTICE '✅ Processed % Bronze WI records', v_processed;
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

