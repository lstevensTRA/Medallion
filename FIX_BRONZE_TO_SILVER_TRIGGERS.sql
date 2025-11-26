-- ============================================================================
-- FIX BRONZE → SILVER TRIGGERS
-- Purpose: Ensure triggers are active and functions exist
-- ============================================================================

-- Step 1: Ensure ensure_case function exists
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

-- Step 2: Verify triggers are enabled
ALTER TABLE bronze_at_raw ENABLE TRIGGER trigger_bronze_at_to_silver;
ALTER TABLE bronze_wi_raw ENABLE TRIGGER trigger_bronze_wi_to_silver;
ALTER TABLE bronze_interview_raw ENABLE TRIGGER trigger_bronze_interview_to_silver;

-- Step 3: Verify triggers exist (run this to check)
-- SELECT tgname, tgrelid::regclass, tgenabled FROM pg_trigger WHERE tgname LIKE 'trigger_bronze%';
