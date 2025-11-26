-- ============================================================================
-- COMPLETE DIAGNOSIS AND FIX FOR BRONZE → SILVER TRIGGERS
-- ============================================================================
-- Run this ENTIRE file in Supabase SQL Editor
-- It will diagnose and fix all trigger issues
-- ============================================================================

-- ============================================================================
-- PART 1: DIAGNOSIS
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'DIAGNOSING BRONZE → SILVER TRIGGERS';
    RAISE NOTICE '============================================================================';
    RAISE NOTICE '';
END $$;

-- Check if triggers exist
SELECT 
    tgname as trigger_name,
    tgrelid::regclass as table_name,
    tgenabled,
    CASE tgenabled
        WHEN 'O' THEN '✅ Enabled'
        WHEN 'D' THEN '❌ Disabled'
        WHEN 'R' THEN '⚠️  Replica'
        WHEN 'A' THEN '✅ Always'
        ELSE '❓ Unknown'
    END as status
FROM pg_trigger
WHERE tgname LIKE 'trigger_bronze%'
ORDER BY tgname;

-- Check if functions exist
SELECT 
    proname as function_name,
    CASE 
        WHEN proname = 'ensure_case' THEN '✅ Critical function'
        WHEN proname LIKE 'process_bronze%' THEN '✅ Trigger function'
        ELSE 'ℹ️  Other function'
    END as status
FROM pg_proc
WHERE proname IN ('ensure_case', 'process_bronze_at', 'process_bronze_wi', 'process_bronze_interview')
ORDER BY proname;

-- Check case exists
SELECT 
    id as case_uuid,
    case_number,
    '✅ Case exists' as status
FROM cases
WHERE case_number = '1295022';

-- Check Bronze data
SELECT 
    'bronze_at_raw' as table_name,
    COUNT(*) as record_count
FROM bronze_at_raw
WHERE case_id = '1295022'
UNION ALL
SELECT 
    'bronze_wi_raw',
    COUNT(*)
FROM bronze_wi_raw
WHERE case_id = '1295022';

-- ============================================================================
-- PART 2: FIXES
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'APPLYING FIXES';
    RAISE NOTICE '============================================================================';
    RAISE NOTICE '';
END $$;

-- Ensure ensure_case function exists (drop first if signature changed)
DROP FUNCTION IF EXISTS ensure_case(TEXT);
DROP FUNCTION IF EXISTS ensure_case(text);

CREATE OR REPLACE FUNCTION ensure_case(p_case_id TEXT)
RETURNS UUID AS $$
DECLARE
  v_case_uuid UUID;
BEGIN
  -- Try to find existing case by case_number
  SELECT id INTO v_case_uuid
  FROM cases
  WHERE case_number = p_case_id;
  
  -- If not found, create it
  IF v_case_uuid IS NULL THEN
    INSERT INTO cases (case_number, status_code)
    VALUES (p_case_id, 'NEW')
    RETURNING id INTO v_case_uuid;
  END IF;
  
  RETURN v_case_uuid;
END;
$$ LANGUAGE plpgsql;

-- Enable all Bronze triggers
DO $$
BEGIN
    ALTER TABLE bronze_at_raw ENABLE TRIGGER trigger_bronze_at_to_silver;
    RAISE NOTICE '✅ Enabled trigger_bronze_at_to_silver';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '⚠️  Could not enable trigger_bronze_at_to_silver: %', SQLERRM;
END $$;

DO $$
BEGIN
    ALTER TABLE bronze_wi_raw ENABLE TRIGGER trigger_bronze_wi_to_silver;
    RAISE NOTICE '✅ Enabled trigger_bronze_wi_to_silver';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '⚠️  Could not enable trigger_bronze_wi_to_silver: %', SQLERRM;
END $$;

-- ============================================================================
-- PART 3: MANUALLY PROCESS EXISTING BRONZE RECORDS
-- ============================================================================

DO $$
DECLARE
    v_case_uuid UUID;
    v_bronze_record RECORD;
    v_processed INTEGER := 0;
    v_year INTEGER;
    v_tax_year_uuid UUID;
    v_record JSONB;
    v_transaction JSONB;
    v_transaction_code TEXT;
    v_at_rule RECORD;
BEGIN
    -- Get case UUID
    SELECT id INTO v_case_uuid
    FROM cases
    WHERE case_number = '1295022';
    
    IF v_case_uuid IS NULL THEN
        RAISE NOTICE '❌ Case not found - creating...';
        INSERT INTO cases (case_number, status_code)
        VALUES ('1295022', 'NEW')
        RETURNING id INTO v_case_uuid;
        RAISE NOTICE '✅ Case created: %', v_case_uuid;
    END IF;
    
    RAISE NOTICE '';
    RAISE NOTICE '🔄 Manually processing Bronze AT records...';
    
    -- Process each Bronze AT record
    FOR v_bronze_record IN 
        SELECT bronze_id, case_id, raw_response
        FROM bronze_at_raw
        WHERE case_id = '1295022'
    LOOP
        BEGIN
            -- Process at_records array
            FOR v_record IN 
                SELECT * FROM jsonb_array_elements(
                    COALESCE(
                        v_bronze_record.raw_response->'at_records',
                        v_bronze_record.raw_response->'records',
                        '[]'::jsonb
                    )
                )
            LOOP
                -- Extract tax year
                v_year := NULL;
                BEGIN
                    v_year := (COALESCE(
                        v_record->>'tax_year',
                        v_record->>'year',
                        v_record->>'period'
                    ))::INTEGER;
                EXCEPTION
                    WHEN OTHERS THEN
                        -- Try parsing as text
                        v_year := NULL;
                END;
                
                IF v_year IS NOT NULL AND v_year > 1900 AND v_year < 2100 THEN
                    -- Get or create tax_year
                    INSERT INTO tax_years (case_id, year, bronze_id)
                    VALUES (v_case_uuid, v_year, v_bronze_record.bronze_id)
                    ON CONFLICT (case_id, year) DO UPDATE SET
                        bronze_id = EXCLUDED.bronze_id,
                        updated_at = NOW()
                    RETURNING id INTO v_tax_year_uuid;
                    
                    -- Process transactions
                    FOR v_transaction IN 
                        SELECT * FROM jsonb_array_elements(
                            COALESCE(v_record->'transactions', '[]'::jsonb)
                        )
                    LOOP
                        v_transaction_code := COALESCE(
                            v_transaction->>'code',
                            v_transaction->>'transaction_code'
                        );
                        
                        -- Look up AT rule
                        SELECT * INTO v_at_rule
                        FROM at_transaction_rules
                        WHERE code = v_transaction_code
                        LIMIT 1;
                        
                        -- Insert account_activity
                        INSERT INTO account_activity (
                            tax_year_id,
                            activity_date,
                            irs_transaction_code,
                            explanation,
                            amount,
                            calculated_transaction_type,
                            affects_balance,
                            affects_csed,
                            indicates_collection_action,
                            bronze_id
                        )
                        VALUES (
                            v_tax_year_uuid,
                            (v_transaction->>'date')::DATE,
                            v_transaction_code,
                            COALESCE(
                                v_transaction->>'description',
                                v_transaction->>'explanation'
                            ),
                            (v_transaction->>'amount')::NUMERIC,
                            COALESCE(v_at_rule.transaction_type, 'Unknown'),
                            COALESCE(v_at_rule.affects_balance, FALSE),
                            COALESCE(v_at_rule.affects_csed, FALSE),
                            COALESCE(v_at_rule.indicates_collection_action, FALSE),
                            v_bronze_record.bronze_id
                        )
                        ON CONFLICT DO NOTHING;
                    END LOOP;
                END IF;
            END LOOP;
            
            v_processed := v_processed + 1;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE '⚠️  Error processing Bronze AT %: %', v_bronze_record.bronze_id, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE '✅ Processed % Bronze AT records', v_processed;
    RAISE NOTICE '';
    RAISE NOTICE '🔄 Manually processing Bronze WI records...';
    
    v_processed := 0;
    
    -- Process Bronze WI records
    FOR v_bronze_record IN 
        SELECT bronze_id, case_id, raw_response
        FROM bronze_wi_raw
        WHERE case_id = '1295022'
    LOOP
        BEGIN
            -- Process forms array
            FOR v_record IN 
                SELECT * FROM jsonb_array_elements(
                    COALESCE(
                        v_bronze_record.raw_response->'forms',
                        v_bronze_record.raw_response->'data',
                        '[]'::jsonb
                    )
                )
            LOOP
                -- Extract tax year
                v_year := NULL;
                BEGIN
                    v_year := (COALESCE(
                        v_record->>'tax_year',
                        v_record->>'year'
                    ))::INTEGER;
                EXCEPTION
                    WHEN OTHERS THEN
                        v_year := NULL;
                END;
                
                IF v_year IS NOT NULL AND v_year > 1900 AND v_year < 2100 THEN
                    -- Get tax_year UUID
                    SELECT id INTO v_tax_year_uuid
                    FROM tax_years
                    WHERE case_id = v_case_uuid AND year = v_year;
                    
                    IF v_tax_year_uuid IS NULL THEN
                        INSERT INTO tax_years (case_id, year)
                        VALUES (v_case_uuid, v_year)
                        RETURNING id INTO v_tax_year_uuid;
                    END IF;
                    
                    -- Look up WI type rule
                    DECLARE
                        v_wi_rule RECORD;
                        v_doc_type TEXT;
                    BEGIN
                        v_doc_type := COALESCE(
                            v_record->>'form_type',
                            v_record->>'document_type',
                            v_record->>'type'
                        );
                        
                        SELECT * INTO v_wi_rule
                        FROM wi_type_rules
                        WHERE form_code = UPPER(TRIM(v_doc_type))
                        LIMIT 1;
                        
                        -- Insert income_documents
                        INSERT INTO income_documents (
                            tax_year_id,
                            document_type,
                            gross_amount,
                            federal_withholding,
                            calculated_category,
                            is_self_employment,
                            issuer_name,
                            recipient_name,
                            bronze_id
                        )
                        VALUES (
                            v_tax_year_uuid,
                            v_doc_type,
                            COALESCE((v_record->>'gross_amount')::NUMERIC, 0),
                            COALESCE((v_record->>'federal_withholding')::NUMERIC, 0),
                            COALESCE(v_wi_rule.category, 'Unknown'),
                            COALESCE(v_wi_rule.is_self_employment, FALSE),
                            v_record->>'issuer_name',
                            v_record->>'recipient_name',
                            v_bronze_record.bronze_id
                        )
                        ON CONFLICT DO NOTHING;
                    END;
                END IF;
            END LOOP;
            
            v_processed := v_processed + 1;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE '⚠️  Error processing Bronze WI %: %', v_bronze_record.bronze_id, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE '✅ Processed % Bronze WI records', v_processed;
END $$;

-- ============================================================================
-- PART 4: VERIFY RESULTS
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'VERIFICATION';
    RAISE NOTICE '============================================================================';
    RAISE NOTICE '';
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

DO $$
DECLARE
    v_tax_years INTEGER;
    v_account_activity INTEGER;
    v_income_documents INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_tax_years
    FROM tax_years t
    JOIN cases c ON t.case_id = c.id
    WHERE c.case_number = '1295022';
    
    SELECT COUNT(*) INTO v_account_activity
    FROM account_activity a
    JOIN tax_years t ON a.tax_year_id = t.id
    JOIN cases c ON t.case_id = c.id
    WHERE c.case_number = '1295022';
    
    SELECT COUNT(*) INTO v_income_documents
    FROM income_documents i
    JOIN tax_years t ON i.tax_year_id = t.id
    JOIN cases c ON t.case_id = c.id
    WHERE c.case_number = '1295022';
    
    RAISE NOTICE '';
    RAISE NOTICE '📊 FINAL RESULTS:';
    RAISE NOTICE '   tax_years: % records', v_tax_years;
    RAISE NOTICE '   account_activity: % records', v_account_activity;
    RAISE NOTICE '   income_documents: % records', v_income_documents;
    RAISE NOTICE '';
    
    IF v_tax_years > 0 OR v_account_activity > 0 OR v_income_documents > 0 THEN
        RAISE NOTICE '🎉 SUCCESS! Silver layer is now populated!';
    ELSE
        RAISE NOTICE '⚠️  Silver layer still empty - check trigger functions for errors';
    END IF;
END $$;

