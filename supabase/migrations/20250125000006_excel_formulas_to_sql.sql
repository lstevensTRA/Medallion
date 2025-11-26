-- ============================================================================
-- Migration: 20250125000006_excel_formulas_to_sql.sql
-- Purpose: Replace Excel formulas with SQL functions/views (Excel-free replication)
-- Dependencies: 20250125000005_extract_interview_fields.sql
-- ============================================================================
-- This replaces ALL Excel formulas with database functions, so you never need Excel
-- The Silver layer keeps cell references (b56, b90, etc.) for compatibility
-- The Gold layer provides normalized, semantic queries
-- ============================================================================

-- ============================================================================
-- PART 1: CALCULATED COLUMNS (Replacing Excel formulas in logiqs_raw_data)
-- ============================================================================

-- These replicate Excel formulas as GENERATED columns that auto-calculate

-- AL7: Taxpayer Monthly Income (Excel: =B5/12 or calculated from pay frequency)
-- This is already extracted, but we can add a calculated version if needed
-- Note: AL7 and AL8 are already populated by the trigger from income data

-- C61_IRS: Food/Clothing/Misc Total (Excel: =SUM(C56:C60))
-- This should be calculated from IRS standards
ALTER TABLE logiqs_raw_data 
  ADD COLUMN IF NOT EXISTS c61_irs_calculated NUMERIC 
  GENERATED ALWAYS AS (
    COALESCE(c56, 0) + 
    COALESCE(c57, 0) + 
    COALESCE(c58, 0) + 
    COALESCE(c59, 0) + 
    COALESCE(c60, 0)
  ) STORED;

-- ============================================================================
-- PART 2: SQL FUNCTIONS (Replacing Excel Formulas)
-- ============================================================================

-- Function: Calculate Total Monthly Income (Excel: =SUM('logiqs raw data'!AL7:AL8))
-- Used in ResoOptionsPatch D186
CREATE OR REPLACE FUNCTION calculate_total_monthly_income(p_case_id UUID)
RETURNS TABLE (
  taxpayer_monthly NUMERIC,
  spouse_monthly NUMERIC,
  total_monthly NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(lrd.al7, 0) as taxpayer_monthly,
    COALESCE(lrd.al8, 0) as spouse_monthly,
    COALESCE(lrd.al7, 0) + COALESCE(lrd.al8, 0) as total_monthly
  FROM logiqs_raw_data lrd
  WHERE lrd.case_id = p_case_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_total_monthly_income IS 'Replaces Excel formula: =SUM(logiqs raw data!AL7:AL8) - Total monthly income (taxpayer + spouse)';

-- Function: Calculate Total Monthly Expenses (Excel: =SUM('logiqs raw data'!AK7:AK8))
-- Used in ResoOptionsPatch E186
CREATE OR REPLACE FUNCTION calculate_total_monthly_expenses(p_case_id UUID)
RETURNS TABLE (
  auto_payment_1 NUMERIC,
  auto_payment_2 NUMERIC,
  total_auto_payments NUMERIC,
  total_all_expenses NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(lrd.ak7, 0) as auto_payment_1,
    COALESCE(lrd.ak8, 0) as auto_payment_2,
    COALESCE(lrd.ak7, 0) + COALESCE(lrd.ak8, 0) as total_auto_payments,
    -- Sum all expense fields (replicating Excel SUM formulas)
    COALESCE(lrd.b56, 0) + COALESCE(lrd.b57, 0) + COALESCE(lrd.b58, 0) + 
    COALESCE(lrd.b59, 0) + COALESCE(lrd.b60, 0) + COALESCE(lrd.b64, 0) + 
    COALESCE(lrd.b65, 0) + COALESCE(lrd.b66, 0) + COALESCE(lrd.b67, 0) + 
    COALESCE(lrd.b68, 0) + COALESCE(lrd.b69, 0) + COALESCE(lrd.b70, 0) + 
    COALESCE(lrd.b71, 0) + COALESCE(lrd.b72, 0) + COALESCE(lrd.b73, 0) + 
    COALESCE(lrd.b74, 0) + COALESCE(lrd.b75, 0) + COALESCE(lrd.b79, 0) + 
    COALESCE(lrd.b80, 0) + COALESCE(lrd.b81, 0) + COALESCE(lrd.b84, 0) + 
    COALESCE(lrd.b87, 0) + COALESCE(lrd.b88, 0) + COALESCE(lrd.b89, 0) + 
    COALESCE(lrd.b90, 0) + COALESCE(lrd.ak4, 0) + COALESCE(lrd.ak5, 0) + 
    COALESCE(lrd.ak6, 0) + COALESCE(lrd.ak7, 0) + COALESCE(lrd.ak8, 0) as total_all_expenses
  FROM logiqs_raw_data lrd
  WHERE lrd.case_id = p_case_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_total_monthly_expenses IS 'Replaces Excel formula: =SUM(logiqs raw data!AK7:AK8) and total expense calculations';

-- Function: Calculate Disposable Income (Excel: D186 - E186)
-- This is Total Monthly Income - Total Monthly Expenses
CREATE OR REPLACE FUNCTION calculate_disposable_income(p_case_id UUID)
RETURNS TABLE (
  total_monthly_income NUMERIC,
  total_monthly_expenses NUMERIC,
  disposable_income NUMERIC
) AS $$
DECLARE
  v_income NUMERIC;
  v_expenses NUMERIC;
BEGIN
  -- Get total monthly income
  SELECT total_monthly INTO v_income
  FROM calculate_total_monthly_income(p_case_id);
  
  -- Get total monthly expenses
  SELECT total_all_expenses INTO v_expenses
  FROM calculate_total_monthly_expenses(p_case_id);
  
  RETURN QUERY
  SELECT 
    COALESCE(v_income, 0) as total_monthly_income,
    COALESCE(v_expenses, 0) as total_monthly_expenses,
    COALESCE(v_income, 0) - COALESCE(v_expenses, 0) as disposable_income;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_disposable_income IS 'Replaces Excel formula: D186 - E186 (Total Income - Total Expenses)';

-- ============================================================================
-- PART 3: VIEWS (Replicating Excel "Tabs")
-- ============================================================================

-- View: "Logiqs Raw Data" Tab (Excel equivalent)
-- This view provides the exact same structure as the Excel tab
CREATE OR REPLACE VIEW excel_logiqs_raw_data AS
SELECT 
  case_id,
  -- Employment (Taxpayer - Column B)
  b3 as "B3_Employer_TP",
  b4 as "B4_StartDate_TP",
  b5 as "B5_GrossIncome_TP",
  b6 as "B6_NetIncome_TP",
  b7 as "B7_PayFreq_TP",
  -- Employment (Spouse - Column C)
  c3 as "C3_Employer_Spouse",
  c4 as "C4_StartDate_Spouse",
  c5 as "C5_GrossIncome_Spouse",
  c6 as "C6_NetIncome_Spouse",
  c7 as "C7_PayFreq_Spouse",
  -- Household
  b10 as "B10_HouseholdSize",
  b11 as "B11_NextTaxReturn_TP",
  b12 as "B12_SpouseClaim_TP",
  b50 as "B50_Under65",
  b51 as "B51_Over65",
  b52 as "B52_State",
  b53 as "B53_County",
  -- Assets
  b18 as "B18_BankAccounts",
  b19 as "B19_CashOnHand",
  b20 as "B20_Investments",
  b23 as "B23_RealEstate",
  b24 as "B24_Vehicle1",
  -- Income
  b33 as "B33_Wages_TP",
  b34 as "B34_SS_TP",
  b36 as "B36_Wages_Spouse",
  b40 as "B40_RentalGross",
  b41 as "B41_RentalExpenses",
  -- Expenses
  b56 as "B56_Food",
  b57 as "B57_Housekeeping",
  b58 as "B58_Apparel",
  b64 as "B64_Mortgage1",
  b66 as "B66_Rent",
  b79 as "B79_HealthInsurance",
  b87 as "B87_CourtPayments",
  b88 as "B88_ChildCare",
  b90 as "B90_TermLifeInsurance",
  -- IRS Standards
  c56 as "C56_IRS_Food",
  c57 as "C57_IRS_Housekeeping",
  c61_irs as "C61_IRS_Total",
  c80 as "C80_HealthOOP",
  -- Formula cells (calculated)
  al4 as "AL4_PublicTrans",
  al5 as "AL5_Food",
  al7 as "AL7_MonthlyIncome_TP",
  al8 as "AL8_MonthlyIncome_Spouse",
  ak7 as "AK7_AutoPayment1",
  ak8 as "AK8_AutoPayment2",
  -- Formula results (from functions)
  (SELECT total_monthly FROM calculate_total_monthly_income(case_id)) as "D186_TotalMonthlyIncome",
  (SELECT total_all_expenses FROM calculate_total_monthly_expenses(case_id)) as "E186_TotalMonthlyExpenses",
  (SELECT disposable_income FROM calculate_disposable_income(case_id)) as "DisposableIncome"
FROM logiqs_raw_data;

COMMENT ON VIEW excel_logiqs_raw_data IS 'Replicates Excel "Logiqs Raw Data" tab - all cell references with calculated formulas';

-- View: "ResoOptionsPatch" Tab (Excel equivalent)
-- This view replicates the ResoOptionsPatch function output
CREATE OR REPLACE VIEW excel_reso_options_patch AS
SELECT 
  lrd.case_id,
  -- D184: ='Logiqs Raw Data'!C61 (Taxpayer Employer)
  lrd.c61 as "D184_TP_Employer",
  -- D185: ='logiqs raw data'!C76 (Spouse Employer)
  lrd.c76 as "D185_Spouse_Employer",
  -- D186: =SUM('logiqs raw data'!AL7:AL8) (Total Monthly Income)
  (SELECT total_monthly FROM calculate_total_monthly_income(lrd.case_id)) as "D186_TotalMonthlyIncome",
  -- E186: =SUM('logiqs raw data'!AK7:AK8) (Total Monthly Expenses)
  (SELECT total_auto_payments FROM calculate_total_monthly_expenses(lrd.case_id)) as "E186_TotalAutoPayments",
  -- D187: ='logiqs raw data'!AL5 (Food Expense)
  lrd.al5 as "D187_FoodExpense",
  -- E188: ='logiqs raw data'!AL4 (Public Transportation)
  lrd.al4 as "E188_PublicTrans",
  -- D189: ='logiqs raw data'!B79 (Health Insurance)
  lrd.b79 as "D189_HealthInsurance",
  -- D190: ='logiqs raw data'!C80 (Health Out of Pocket)
  lrd.c80 as "D190_HealthOOP",
  -- D194: ='logiqs raw data'!B87 (Court Payments)
  lrd.b87 as "D194_CourtPayments",
  -- D195: ='logiqs raw data'!B88 (Child Care)
  lrd.b88 as "D195_ChildCare",
  -- D196: ='logiqs raw data'!B90 (Term Life Insurance)
  lrd.b90 as "D196_TermLifeInsurance"
FROM logiqs_raw_data lrd;

COMMENT ON VIEW excel_reso_options_patch IS 'Replicates Excel ResoOptionsPatch function - all formula cell references';

-- ============================================================================
-- PART 4: HELPER FUNCTIONS (For common Excel operations)
-- ============================================================================

-- Function: Get cell value (replaces Excel cell reference)
-- Usage: SELECT get_cell_value('case-uuid', 'b56') -- Returns food expense
CREATE OR REPLACE FUNCTION get_cell_value(p_case_id UUID, p_cell TEXT)
RETURNS NUMERIC AS $$
DECLARE
  v_value NUMERIC;
BEGIN
  -- Map cell references to columns
  CASE UPPER(p_cell)
    WHEN 'B56' THEN SELECT b56 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'B57' THEN SELECT b57 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'B79' THEN SELECT b79 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'B87' THEN SELECT b87 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'B88' THEN SELECT b88 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'B90' THEN SELECT b90 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'AL7' THEN SELECT al7 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'AL8' THEN SELECT al8 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'AK7' THEN SELECT ak7 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'AK8' THEN SELECT ak8 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'C61' THEN SELECT c61_irs INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'AL4' THEN SELECT al4 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'AL5' THEN SELECT al5 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    WHEN 'C80' THEN SELECT c80 INTO v_value FROM logiqs_raw_data WHERE case_id = p_case_id;
    ELSE v_value := NULL;
  END CASE;
  
  RETURN COALESCE(v_value, 0);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_cell_value IS 'Replaces Excel cell reference - get value by cell name (e.g., get_cell_value(case_id, ''b56''))';

-- ============================================================================
-- PART 5: SUMMARY
-- ============================================================================

-- All Excel formulas are now replaced with:
-- 1. Calculated columns (GENERATED ALWAYS AS) for simple formulas
-- 2. SQL functions for complex calculations
-- 3. Views that replicate Excel tabs
-- 4. Helper functions for cell lookups

-- Usage Examples:
-- 
-- Instead of Excel: =SUM('logiqs raw data'!AL7:AL8)
-- Use SQL: SELECT total_monthly FROM calculate_total_monthly_income(case_id);
--
-- Instead of Excel: ='Logiqs Raw Data'!B56
-- Use SQL: SELECT get_cell_value(case_id, 'b56');
--
-- Instead of opening Excel tab "Logiqs Raw Data"
-- Use SQL: SELECT * FROM excel_logiqs_raw_data WHERE case_id = 'uuid';
--
-- Instead of running ResoOptionsPatch macro
-- Use SQL: SELECT * FROM excel_reso_options_patch WHERE case_id = 'uuid';

