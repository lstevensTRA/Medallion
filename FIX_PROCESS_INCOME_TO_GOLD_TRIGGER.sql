-- ============================================================================
-- FIX process_income_to_gold TRIGGER
-- Purpose: Fix trigger that incorrectly references NEW.case_id on income_documents
-- ============================================================================

DROP TRIGGER IF EXISTS trigger_silver_income_to_gold ON income_documents;
DROP TRIGGER IF EXISTS trigger_income_to_gold ON income_documents;
DROP FUNCTION IF EXISTS process_income_to_gold() CASCADE;

-- Recreate function with correct logic (get case_id from tax_year_id)
CREATE OR REPLACE FUNCTION process_income_to_gold()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
BEGIN
  -- Get case_id from tax_year_id
  SELECT case_id INTO v_case_uuid
  FROM tax_years
  WHERE id = NEW.tax_year_id;
  
  -- If case_id not found, just return (shouldn't happen but be safe)
  IF v_case_uuid IS NULL THEN
    RETURN NEW;
  END IF;
  
  -- Insert or update income_sources
  INSERT INTO income_sources (
    case_id,
    source_type,
    source_name,
    gross_monthly_amount,
    net_monthly_amount,
    frequency,
    is_self_employment,
    source_year
  )
  SELECT
    v_case_uuid,
    NEW.document_type,
    COALESCE(NEW.issuer_name, 'Unknown'),
    NEW.gross_amount / 12.0,  -- Convert annual to monthly
    (NEW.gross_amount - NEW.federal_withholding) / 12.0,  -- Net monthly
    'monthly',
    NEW.is_self_employment,
    (SELECT year FROM tax_years WHERE id = NEW.tax_year_id)
  WHERE NEW.gross_amount > 0
  ON CONFLICT (case_id, source_type, source_name, source_year) DO UPDATE SET
    gross_monthly_amount = EXCLUDED.gross_monthly_amount,
    net_monthly_amount = EXCLUDED.net_monthly_amount,
    is_self_employment = EXCLUDED.is_self_employment,
    updated_at = NOW();
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate trigger
DROP TRIGGER IF EXISTS trigger_silver_income_to_gold ON income_documents;
CREATE TRIGGER trigger_silver_income_to_gold
    AFTER INSERT OR UPDATE ON income_documents
    FOR EACH ROW
    EXECUTE FUNCTION process_income_to_gold();

COMMENT ON FUNCTION process_income_to_gold IS 'Populate Gold income_sources from Silver income_documents (fixed to get case_id from tax_year_id)';

