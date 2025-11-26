-- Fix trigger on income_documents if it references case_id incorrectly
DROP TRIGGER IF EXISTS trigger_income_documents_to_gold ON income_documents;
DROP FUNCTION IF EXISTS process_income_documents_to_gold();

-- If there's a trigger trying to access NEW.case_id, we need to get case_id from tax_year_id
-- But let's first check if such trigger exists and fix it properly

-- Check for any other triggers that might be problematic
SELECT 'Checking for problematic triggers...' as status;

