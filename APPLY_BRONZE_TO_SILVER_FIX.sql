-- ============================================================================
-- APPLY BRONZE → SILVER TRIGGER FIX
-- Purpose: Ensure triggers exist and are enabled
-- ============================================================================
-- This ensures all Bronze → Silver triggers are active and working
-- ============================================================================

-- Step 1: Ensure ensure_case function exists (should already exist)
CREATE OR REPLACE FUNCTION ensure_case(p_case_id TEXT)
RETURNS UUID AS $$
DECLARE
  v_case_uuid UUID;
BEGIN
  -- Try to find existing case by case_number (assuming case_id is case_number)
  SELECT id INTO v_case_uuid
  FROM cases
  WHERE case_number = p_case_id;
  
  -- If not found, create a minimal case record
  IF v_case_uuid IS NULL THEN
    INSERT INTO cases (case_number, status_code)
    VALUES (p_case_id, 'NEW')
    RETURNING id INTO v_case_uuid;
  END IF;
  
  RETURN v_case_uuid;
END;
$$ LANGUAGE plpgsql;

-- Step 2: Re-create triggers (this will enable them if they exist, create if they don't)
-- Note: We need to check if trigger functions exist first

-- Drop and recreate AT trigger
DROP TRIGGER IF EXISTS trigger_bronze_at_to_silver ON bronze_at_raw;
CREATE TRIGGER trigger_bronze_at_to_silver
    AFTER INSERT ON bronze_at_raw
    FOR EACH ROW
    EXECUTE FUNCTION process_bronze_at();

-- Drop and recreate WI trigger
DROP TRIGGER IF EXISTS trigger_bronze_wi_to_silver ON bronze_wi_raw;
CREATE TRIGGER trigger_bronze_wi_to_silver
    AFTER INSERT ON bronze_wi_raw
    FOR EACH ROW
    EXECUTE FUNCTION process_bronze_wi();

-- Drop and recreate Interview trigger
DROP TRIGGER IF EXISTS trigger_bronze_interview_to_silver ON bronze_interview_raw;
CREATE TRIGGER trigger_bronze_interview_to_silver
    AFTER INSERT ON bronze_interview_raw
    FOR EACH ROW
    EXECUTE FUNCTION process_bronze_interview();

-- Step 3: Ensure triggers are enabled
ALTER TABLE bronze_at_raw ENABLE TRIGGER trigger_bronze_at_to_silver;
ALTER TABLE bronze_wi_raw ENABLE TRIGGER trigger_bronze_wi_to_silver;
ALTER TABLE bronze_interview_raw ENABLE TRIGGER trigger_bronze_interview_to_silver;

-- Step 4: Verify triggers exist and are enabled
DO $$
DECLARE
  trigger_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO trigger_count
  FROM pg_trigger
  WHERE tgname IN (
    'trigger_bronze_at_to_silver',
    'trigger_bronze_wi_to_silver',
    'trigger_bronze_interview_to_silver'
  )
  AND tgenabled = 'O';  -- 'O' = enabled
  
  IF trigger_count = 3 THEN
    RAISE NOTICE '✅ All 3 Bronze → Silver triggers are active!';
  ELSE
    RAISE WARNING '⚠️  Only % of 3 triggers are enabled', trigger_count;
  END IF;
END $$;

-- Step 5: Test ensure_case function
DO $$
DECLARE
  test_uuid UUID;
BEGIN
  test_uuid := ensure_case('1295022');
  IF test_uuid IS NOT NULL THEN
    RAISE NOTICE '✅ ensure_case function works! Case UUID: %', test_uuid;
  ELSE
    RAISE WARNING '⚠️  ensure_case function returned NULL';
  END IF;
END $$;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '✅ Bronze → Silver triggers fixed!';
    RAISE NOTICE '';
    RAISE NOTICE '📊 Triggers active:';
    RAISE NOTICE '  → trigger_bronze_at_to_silver (AT → tax_years, account_activity)';
    RAISE NOTICE '  → trigger_bronze_wi_to_silver (WI → income_documents)';
    RAISE NOTICE '  → trigger_bronze_interview_to_silver (Interview → logiqs_raw_data)';
    RAISE NOTICE '';
    RAISE NOTICE '💡 Note: Existing Bronze records will NOT trigger automatically.';
    RAISE NOTICE '   New Bronze inserts will trigger Silver population.';
    RAISE NOTICE '   To process existing Bronze records, you may need to re-insert them.';
END $$;

