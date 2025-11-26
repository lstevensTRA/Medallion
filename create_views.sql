-- Create views that depend on logiqs_raw_data
-- Run this after logiqs_raw_data table exists

CREATE OR REPLACE VIEW excel_reso_options_patch AS
SELECT 
  lrd.case_id,
  lrd.c61 as "D184_TP_Employer",
  lrd.c76 as "D185_Spouse_Employer",
  (SELECT total_monthly FROM calculate_total_monthly_income(lrd.case_id)) as "D186_TotalMonthlyIncome",
  (SELECT total_auto_payments FROM calculate_total_monthly_expenses(lrd.case_id)) as "E186_TotalAutoPayments",
  lrd.al5 as "D187_FoodExpense",
  lrd.al4 as "E188_PublicTrans",
  lrd.b79 as "D189_HealthInsurance",
  lrd.c80 as "D190_HealthOOP",
  lrd.b87 as "D194_CourtPayments",
  lrd.b88 as "D195_ChildCare",
  lrd.b90 as "D196_TermLifeInsurance"
FROM logiqs_raw_data lrd;

COMMENT ON VIEW excel_reso_options_patch IS 'Replicates Excel ResoOptionsPatch function - all formula cell references';

