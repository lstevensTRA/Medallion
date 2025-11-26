-- ============================================================================
-- Manually Populate Silver from Existing Bronze Records
-- ============================================================================
-- This processes existing Bronze records to populate Silver
-- Run this in Supabase SQL Editor
-- ============================================================================

-- STEP 1: Process existing Bronze AT records
DO $$
DECLARE
    v_bronze_record RECORD;
    v_case_uuid UUID;
    v_count INTEGER := 0;
BEGIN
    RAISE NOTICE '🔄 Processing Bronze AT records...';
    
    FOR v_bronze_record IN 
        SELECT bronze_id, case_id, raw_response
        FROM bronze_at_raw
        WHERE case_id = '1295022'
    LOOP
        BEGIN
            -- Get or create case UUID
            v_case_uuid := ensure_case(v_bronze_record.case_id);
            
            -- Manually call the trigger function
            -- We'll insert a temporary record to fire the trigger
            INSERT INTO bronze_at_raw (case_id, raw_response, api_source)
            VALUES (v_bronze_record.case_id, v_bronze_record.raw_response, 'tiparser')
            ON CONFLICT DO NOTHING;
            
            v_count := v_count + 1;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE '⚠️  Error processing Bronze record %: %', v_bronze_record.bronze_id, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE '✅ Processed % Bronze AT records', v_count;
END $$;

-- STEP 2: Process existing Bronze WI records
DO $$
DECLARE
    v_bronze_record RECORD;
    v_case_uuid UUID;
    v_count INTEGER := 0;
BEGIN
    RAISE NOTICE '🔄 Processing Bronze WI records...';
    
    FOR v_bronze_record IN 
        SELECT bronze_id, case_id, raw_response
        FROM bronze_wi_raw
        WHERE case_id = '1295022'
    LOOP
        BEGIN
            -- Get or create case UUID
            v_case_uuid := ensure_case(v_bronze_record.case_id);
            
            -- Manually call the trigger function by re-inserting
            INSERT INTO bronze_wi_raw (case_id, raw_response, api_source)
            VALUES (v_bronze_record.case_id, v_bronze_record.raw_response, 'tiparser')
            ON CONFLICT DO NOTHING;
            
            v_count := v_count + 1;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE '⚠️  Error processing Bronze record %: %', v_bronze_record.bronze_id, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE '✅ Processed % Bronze WI records', v_count;
END $$;

-- STEP 3: Check results
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

