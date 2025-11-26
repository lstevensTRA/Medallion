-- ============================================================================
-- FIX auto_categorize_income_document TRIGGER
-- Purpose: Fix trigger that incorrectly references NEW.case_id
-- ============================================================================

DROP TRIGGER IF EXISTS trigger_auto_categorize_income_document ON income_documents;
DROP FUNCTION IF EXISTS auto_categorize_income_document();

-- Recreate function with correct logic (get case_id from tax_year_id)
CREATE OR REPLACE FUNCTION auto_categorize_income_document()
RETURNS TRIGGER AS $$
DECLARE
  v_case_id UUID;
  v_wi_rule RECORD;
BEGIN
  -- Get case_id from tax_year_id
  SELECT case_id INTO v_case_id
  FROM tax_years
  WHERE id = NEW.tax_year_id;
  
  -- If case_id not found, just return (shouldn't happen but be safe)
  IF v_case_id IS NULL THEN
    RETURN NEW;
  END IF;
  
  -- Look up WI type rule
  SELECT * INTO v_wi_rule
  FROM wi_type_rules
  WHERE form_code = UPPER(TRIM(NEW.document_type))
  LIMIT 1;
  
  -- Update calculated fields if rule found
  IF v_wi_rule IS NOT NULL THEN
    NEW.calculated_category := v_wi_rule.category;
    NEW.is_self_employment := v_wi_rule.is_self_employment;
  ELSE
    -- Default values
    NEW.calculated_category := COALESCE(NEW.calculated_category, 'Unknown');
    NEW.is_self_employment := COALESCE(NEW.is_self_employment, FALSE);
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate trigger
CREATE TRIGGER trigger_auto_categorize_income_document
    BEFORE INSERT OR UPDATE ON income_documents
    FOR EACH ROW
    EXECUTE FUNCTION auto_categorize_income_document();

COMMENT ON FUNCTION auto_categorize_income_document IS 'Auto-categorize income documents using WI type rules (fixed to get case_id from tax_year_id)';

