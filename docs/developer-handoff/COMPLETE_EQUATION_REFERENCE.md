# Tax Investigation - Complete Equation Reference

**Purpose:** Comprehensive reference for ALL equation types, calculation patterns, and formulas used across Tax Investigation sheets. This is a generic reference applicable to any case.

**Based on:**
- Analysis of multiple TI Excel sheets (including case 941839 and others)
- `TI_SHEET_TO_DATABASE_COMPLETE_MAPPING.md` - Complete mapping reference
- `EXCEL_FORMULAS_EXTRACTED.md` - Extracted formulas from sample cases
- AI Glossary business rules
- Database schema and function implementations

---

## Document Structure

This document catalogs:
- **Equation Types** - All categories of calculations (CSED, Tax Projections, AUR, etc.)
- **Formula Patterns** - Common Excel formula patterns and their SQL equivalents
- **Calculation Logic** - Business logic for each equation type
- **Database Implementation** - How each equation maps to database functions/tables
- **Validation Patterns** - How to verify calculations match Excel

---

## Table of Contents

1. [CSED Calculations](#1-csed-calculations)
2. [Tax Projection Calculations](#2-tax-projection-calculations)
3. [Account Balance Calculations](#3-account-balance-calculations)
4. [AUR (Automated Underreporter) Calculations](#4-aur-automated-underreporter-calculations)
5. [SFR (Substitute For Return) Calculations](#5-sfr-substitute-for-return-calculations)
6. [Income Aggregation Calculations](#6-income-aggregation-calculations)
7. [Resolution Options Calculations](#7-resolution-options-calculations)
8. [Tax Bracket and Deduction Calculations](#8-tax-bracket-and-deduction-calculations)
9. [Self-Employment Tax Calculations](#9-self-employment-tax-calculations)
10. [Disposable Income Calculations](#10-disposable-income-calculations)
11. [Lookup and Reference Formulas](#11-lookup-and-reference-formulas)
12. [Conditional Logic Formulas](#12-conditional-logic-formulas)
13. [Date and Time Calculations](#13-date-and-time-calculations)
14. [Mathematical Aggregation Formulas](#14-mathematical-aggregation-formulas)
15. [Cross-Sheet Reference Patterns](#15-cross-sheet-reference-patterns)

---

## 1. CSED Calculations

### Purpose
Collection Statute Expiration Date (CSED) calculations determine when the IRS can no longer collect on a tax debt.

### Equation Types

#### 1.1 Base CSED Calculation

**Excel Formula Pattern:**
```excel
=IFERROR(
  IF(start_date = "", "",
    start_date + 3652  // 10 years in days
  ),
  ""
)
```

**Business Logic:**
- Base CSED = Return Filed Date (Code 150 transaction) + 10 years (3652 days)
- If no return filed date exists, CSED is undefined/null

**Database Equivalent:**
```sql
-- Function: calculate_base_csed(tax_year_id)
SELECT 
  CASE 
    WHEN return_filed_date IS NULL THEN NULL
    ELSE return_filed_date + INTERVAL '10 years'
  END as base_csed
FROM tax_years
WHERE id = tax_year_id;
```

**Database Table/Column:**
- Source: `tax_years.return_filed_date`
- Output: `tax_years.base_csed_date`
- Function: `calculate_base_csed(UUID)`

**Validation:**
- Verify: Base CSED = Filed Date + 3652 days (accounting for leap years, use INTERVAL '10 years')
- Check: Returns NULL if no filed date

---

#### 1.2 CSED Tolling - Bankruptcy

**Excel Formula Pattern:**
```excel
=IF(
  AND(start_code = "520", end_code = ""),
  "OPEN",  // Bankruptcy is open
  IF(
    end_code = "521",
    start_date + interval_days + 180,  // Add 6 months after release
    ""
  )
)
```

**Business Logic:**
- If Bankruptcy Code 520 exists without Code 521: CSED is OPEN (indefinite)
- If Bankruptcy closed (Code 521): Add interval days + 180 days (6 months)
- Tolling = (Bankruptcy End Date - Bankruptcy Start Date) + 180 days

**Database Equivalent:**
```sql
-- Check for open bankruptcy
SELECT 
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM account_activity 
      WHERE code = '520' 
        AND tax_year_id = $1
        AND NOT EXISTS (
          SELECT 1 FROM account_activity 
          WHERE code = '521' 
            AND tax_year_id = $1
            AND activity_date >= account_activity.activity_date
        )
    ) THEN NULL  -- CSED is OPEN
    ELSE (
      SELECT 
        base_csed + (
          SUM(EXTRACT(EPOCH FROM (end_date - start_date)) / 86400) + 180
        ) || ' days'::INTERVAL
      FROM csed_tolling_events
      WHERE tax_year_id = $1
        AND event_type = 'bankruptcy'
        AND is_open = false
    )
  END as adjusted_csed;
```

**Database Table/Column:**
- Source: `account_activity` (codes 520, 521)
- Intermediate: `csed_tolling_events` (bankruptcy events)
- Output: `tax_years.adjusted_csed_date`
- Function: `calculate_csed_with_tolling(UUID)`

**Validation:**
- Open bankruptcy → CSED = NULL/OPEN
- Closed bankruptcy → Base CSED + (interval + 180 days)

---

#### 1.3 CSED Tolling - OIC (Offer in Compromise)

**Excel Formula Pattern:**
```excel
=IF(
  AND(start_code = "480", end_code IN ("481", "482")),
  base_csed + interval_days + 30,  // Add 30 days for accepted OIC
  IF(
    end_code = "483",
    base_csed + interval_days,  // Withdrawn, no extra days
    base_csed
  )
)
```

**Business Logic:**
- OIC Pending (Code 480): Add interval days while pending
- OIC Accepted (Codes 481, 482): Add interval + 30 additional days
- OIC Rejected/Withdrawn (Code 483): Add interval only, no extra days

**Database Equivalent:**
```sql
SELECT 
  base_csed + (
    SUM(
      CASE 
        WHEN end_code IN ('481', '482') THEN 
          EXTRACT(EPOCH FROM (end_date - start_date)) / 86400 + 30
        ELSE 
          EXTRACT(EPOCH FROM (end_date - start_date)) / 86400
      END
    )
  ) || ' days'::INTERVAL
FROM csed_tolling_events
WHERE tax_year_id = $1
  AND event_type = 'oic'
  AND is_open = false;
```

**Database Table/Column:**
- Source: `account_activity` (codes 480, 481, 482, 483)
- Output: Tolling days added to base CSED
- Function: `calculate_csed_with_tolling(UUID)`

**Validation:**
- Accepted OIC → +30 extra days
- Rejected/Withdrawn → No extra days

---

#### 1.4 CSED Tolling - CDP (Collection Due Process)

**Excel Formula Pattern:**
```excel
=IF(
  start_code = "971" AND end_code = "971",
  base_csed + interval_days,  // Add duration of CDP process
  base_csed
)
```

**Business Logic:**
- CDP Request (Code 971): Add interval days while CDP is pending
- Same code (971) used for both start and end (different explanations)

**Database Equivalent:**
```sql
SELECT 
  base_csed + (
    SUM(EXTRACT(EPOCH FROM (end_date - start_date)) / 86400)
  ) || ' days'::INTERVAL
FROM csed_tolling_events
WHERE tax_year_id = $1
  AND event_type = 'cdp'
  AND is_open = false;
```

**Database Table/Column:**
- Source: `account_activity` (code 971 with different explanations)
- Output: Tolling days added to base CSED
- Function: `calculate_csed_with_tolling(UUID)`

---

#### 1.5 CSED Tolling - Penalties

**Excel Formula Pattern:**
```excel
=IF(
  code = "276" OR code = "196",
  base_csed + 30,  // Add 1 month for penalty
  IF(
    code = "971",
    base_csed,  // No extra days
    base_csed
  )
)
```

**Business Logic:**
- Penalty Code 276 (Delinquency): Base CSED + 30 days
- Penalty Code 196 (Estimated Tax): Base CSED + 30 days
- Code 971 (Notice): No extra days (just tolls during process)

**Database Equivalent:**
```sql
SELECT 
  base_csed + (
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM account_activity 
        WHERE code IN ('276', '196') 
          AND tax_year_id = $1
      ) THEN 30
      ELSE 0
    END
  ) || ' days'::INTERVAL;
```

**Database Table/Column:**
- Source: `account_activity` (codes 276, 196)
- Output: Tolling days added to base CSED
- Function: `calculate_csed_with_tolling(UUID)`

---

#### 1.6 Adjusted CSED (Final)

**Excel Formula Pattern:**
```excel
=MAX(
  base_csed,
  base_csed + bankruptcy_tolling,
  base_csed + oic_tolling,
  base_csed + cdp_tolling,
  base_csed + penalty_tolling
)
```

**Business Logic:**
- Final CSED = Maximum of all possible CSED dates (base + each tolling event)
- Take the latest date to ensure all tolling is accounted for

**Database Equivalent:**
```sql
-- Function: calculate_adjusted_csed(tax_year_id)
CREATE OR REPLACE FUNCTION calculate_adjusted_csed(p_tax_year_id UUID)
RETURNS DATE AS $$
DECLARE
  v_base_csed DATE;
  v_adjusted_csed DATE;
  v_max_csed DATE;
  v_tolling_event RECORD;
BEGIN
  -- Get base CSED
  SELECT calculate_base_csed(p_tax_year_id) INTO v_base_csed;
  
  IF v_base_csed IS NULL THEN
    RETURN NULL;  -- CSED is OPEN or no filed date
  END IF;
  
  v_max_csed := v_base_csed;
  
  -- Check each tolling event type and calculate adjusted CSED
  FOR v_tolling_event IN
    SELECT * FROM csed_tolling_events
    WHERE tax_year_id = p_tax_year_id
      AND is_open = false
      AND total_toll_days > 0
    ORDER BY start_date
  LOOP
    v_adjusted_csed := v_base_csed + (v_tolling_event.total_toll_days || ' days')::INTERVAL;
    
    IF v_adjusted_csed > v_max_csed THEN
      v_max_csed := v_adjusted_csed;
    END IF;
  END LOOP;
  
  RETURN v_max_csed;
END;
$$ LANGUAGE plpgsql;
```

**Database Table/Column:**
- Source: `tax_years.base_csed_date` + `csed_tolling_events`
- Output: `tax_years.adjusted_csed_date`
- Function: `calculate_adjusted_csed(UUID)`

**Validation:**
- Adjusted CSED >= Base CSED
- Adjusted CSED accounts for all tolling events
- Returns NULL if bankruptcy is open

---

#### 1.7 Days Until CSED Expires

**Excel Formula Pattern:**
```excel
=IF(
  adjusted_csed = "",
  "",
  adjusted_csed - TODAY()
)
```

**Business Logic:**
- Calculate days remaining until CSED expiration
- Negative values = CSED has expired
- Empty if CSED is OPEN

**Database Equivalent:**
```sql
SELECT 
  CASE 
    WHEN adjusted_csed_date IS NULL THEN NULL
    ELSE EXTRACT(EPOCH FROM (adjusted_csed_date - CURRENT_DATE)) / 86400
  END as days_until_csed
FROM tax_years
WHERE id = tax_year_id;
```

**Database Table/Column:**
- Source: `tax_years.adjusted_csed_date`
- Output: Calculated field (days)
- Function: Can be computed in SELECT or view

**Validation:**
- Positive = days remaining
- Negative = expired
- NULL = OPEN/undefined

---

## 2. Tax Projection Calculations

### Purpose
Calculate projected tax liability for a tax year based on income, deductions, and tax brackets.

### Equation Types

#### 2.1 Taxpayer Income Aggregation

**Excel Formula Pattern:**
```excel
=SUMIFS(
  income_amounts,
  recipient_ssn_range,
  taxpayer_ssn,
  tax_year_range,
  current_year
)
```

**Business Logic:**
- Sum all income documents where recipient SSN matches taxpayer SSN
- Filter by tax year
- Includes: W-2, 1099-NEC, 1099-MISC, 1099-R, etc.

**Database Equivalent:**
```sql
SELECT 
  COALESCE(SUM(gross_amount), 0) as tp_income
FROM income_documents
WHERE tax_year_id = $1
  AND recipient_ssn = (SELECT primary_ssn FROM cases WHERE id = case_id)
  AND is_excluded = false;
```

**Database Table/Column:**
- Source: `income_documents.gross_amount`
- Filter: `income_documents.recipient_ssn = taxpayer_ssn`
- Output: `tax_projections.tp_income`

**Validation:**
- Sum should match sum of all income documents for taxpayer
- Verify SSN matching logic

---

#### 2.2 Spouse Income Aggregation

**Excel Formula Pattern:**
```excel
=SUMIFS(
  income_amounts,
  recipient_ssn_range,
  spouse_ssn,
  tax_year_range,
  current_year
)
```

**Business Logic:**
- Same as taxpayer income, but filtered by spouse SSN
- Only applies to Married Filing Jointly (MFJ) returns

**Database Equivalent:**
```sql
SELECT 
  COALESCE(SUM(gross_amount), 0) as spouse_income
FROM income_documents
WHERE tax_year_id = $1
  AND recipient_ssn = (SELECT spouse_ssn FROM cases WHERE id = case_id)
  AND is_excluded = false;
```

**Database Table/Column:**
- Source: `income_documents.gross_amount`
- Filter: `income_documents.recipient_ssn = spouse_ssn`
- Output: `tax_projections.spouse_income`

---

#### 2.3 Self-Employment Income (Taxpayer)

**Excel Formula Pattern:**
```excel
=SUMIFS(
  income_amounts,
  recipient_ssn_range,
  taxpayer_ssn,
  form_type_range,
  {"1099-NEC", "1099-MISC Box 7"},
  tax_year_range,
  current_year
)
```

**Business Logic:**
- Sum income documents where:
  - Recipient SSN = Taxpayer SSN
  - Form type indicates self-employment (from AI Glossary rules)
- Includes: 1099-NEC, 1099-MISC Box 7 (pre-2020), 1099-K

**Database Equivalent:**
```sql
SELECT 
  COALESCE(SUM(gross_amount), 0) as tp_se_income
FROM income_documents id
JOIN wi_type_rules wtr ON id.form_type = wtr.form_code
WHERE id.tax_year_id = $1
  AND id.recipient_ssn = (SELECT primary_ssn FROM cases WHERE id = case_id)
  AND wtr.is_self_employment = true
  AND id.is_excluded = false;
```

**Database Table/Column:**
- Source: `income_documents.gross_amount`
- Filter: `income_documents.is_self_employment = true` (from business rules)
- Output: `tax_projections.tp_se_income`

**Validation:**
- Verify business rule lookup (WI type rules)
- Check form type categorization

---

#### 2.4 Self-Employment Tax Calculation

**Excel Formula Pattern:**
```excel
=SE_Income * 0.153
```

**Business Logic:**
- Self-Employment Tax = 15.3% of SE income
- Split: 12.4% for Social Security + 2.9% for Medicare
- Total = 15.3%

**Database Equivalent:**
```sql
SELECT 
  se_income * 0.153 as se_tax
FROM tax_projections
WHERE id = projection_id;
```

**Database Table/Column:**
- Source: `tax_projections.tp_se_income` or `spouse_se_income`
- Output: `tax_projections.se_tax`
- Calculation: Direct multiplication

**Validation:**
- Verify rate: 15.3% (0.153)
- Check: SE tax = SE income × 0.153

---

#### 2.5 Estimated AGI (Adjusted Gross Income)

**Excel Formula Pattern:**
```excel
=Total_Income - (SE_Income * 0.0765)
```

**Business Logic:**
- Estimated AGI = Total Income - SE Tax Adjustment
- SE Tax Adjustment = SE Income × 7.65% (half of SE tax rate)
- This accounts for the employer portion of payroll taxes

**Database Equivalent:**
```sql
SELECT 
  total_income - (se_income * 0.0765) as estimated_agi
FROM tax_projections
WHERE id = projection_id;
```

**Database Table/Column:**
- Source: `tax_projections.total_income`, `tax_projections.se_income`
- Output: `tax_projections.estimated_agi`
- Calculation: Total Income - (SE Income × 0.0765)

**Validation:**
- Verify adjustment factor: 7.65% (0.0765)
- Check: AGI = Total Income - (SE Income × 0.0765)

---

#### 2.6 Standard Deduction Lookup

**Excel Formula Pattern:**
```excel
=IFERROR(
  VLOOKUP(
    filing_status & tax_year,
    standard_deduction_table,
    2,
    FALSE
  ),
  ""
)
```

**Business Logic:**
- Lookup standard deduction by filing status and tax year
- Different amounts for Single, MFJ, MFS, HoH, Widow
- Changes annually (IRS updates)

**Database Equivalent:**
```sql
SELECT 
  deduction_amount
FROM standard_deductions
WHERE year = $1
  AND filing_status = $2;
```

**Database Table/Column:**
- Source: `standard_deductions` lookup table
- Filter: `year`, `filing_status`
- Output: `tax_projections.standard_deduction`

**Validation:**
- Verify lookup table has correct values for each year
- Check filing status values match

---

#### 2.7 Taxable Income Calculation

**Excel Formula Pattern:**
```excel
=MAX(0, Estimated_AGI - Standard_Deduction)
```

**Business Logic:**
- Taxable Income = Estimated AGI - Standard Deduction
- Minimum = 0 (can't be negative)

**Database Equivalent:**
```sql
SELECT 
  GREATEST(0, estimated_agi - standard_deduction) as taxable_income
FROM tax_projections
WHERE id = projection_id;
```

**Database Table/Column:**
- Source: `tax_projections.estimated_agi`, `tax_projections.standard_deduction`
- Output: `tax_projections.taxable_income`
- Calculation: MAX(0, AGI - Standard Deduction)

**Validation:**
- Taxable Income >= 0
- Taxable Income = AGI - Standard Deduction (if positive)

---

#### 2.8 Tax Liability (Progressive Tax Brackets)

**Excel Formula Pattern:**
```excel
=IF(taxable_income <= bracket1_max,
  taxable_income * bracket1_rate,
  IF(taxable_income <= bracket2_max,
    bracket1_amount + (taxable_income - bracket1_max) * bracket2_rate,
    // Continue for all brackets...
  )
)
```

**Business Logic:**
- Apply progressive marginal tax rates
- Each bracket: (Income in bracket) × (Bracket rate)
- Example for 2023 MFJ:
  - First $22,000 at 10% = $2,200
  - Next $67,050 at 12% = $8,046
  - Remaining at 22% = (taxable_income - $89,050) × 22%

**Database Equivalent:**
```sql
-- Function: calculate_tax_liability(taxable_income, filing_status, year)
CREATE OR REPLACE FUNCTION calculate_tax_liability(
  p_taxable_income DECIMAL,
  p_filing_status TEXT,
  p_year INTEGER
)
RETURNS DECIMAL AS $$
DECLARE
  v_tax DECIMAL := 0;
  v_remaining_income DECIMAL := p_taxable_income;
  v_bracket RECORD;
BEGIN
  -- Loop through tax brackets in order
  FOR v_bracket IN
    SELECT * FROM tax_brackets
    WHERE year = p_year
      AND filing_status = p_filing_status
    ORDER BY income_min
  LOOP
    IF v_remaining_income <= 0 THEN
      EXIT;
    END IF;
    
    DECLARE
      v_bracket_income DECIMAL;
    BEGIN
      -- Calculate income in this bracket
      v_bracket_income := LEAST(
        v_remaining_income,
        COALESCE(v_bracket.income_max, 999999999) - v_bracket.income_min
      );
      
      -- Add tax for this bracket
      v_tax := v_tax + (v_bracket_income * v_bracket.tax_rate);
      
      -- Reduce remaining income
      v_remaining_income := v_remaining_income - v_bracket_income;
    END;
  END LOOP;
  
  RETURN v_tax;
END;
$$ LANGUAGE plpgsql;
```

**Database Table/Column:**
- Source: `tax_brackets` lookup table
- Parameters: `taxable_income`, `filing_status`, `year`
- Output: `tax_projections.tax_liability`
- Function: `calculate_tax_liability(DECIMAL, TEXT, INTEGER)`

**Validation:**
- Verify tax bracket table has correct rates for each year
- Test with known income amounts
- Verify progressive calculation (marginal rates)

---

#### 2.9 Total Tax Calculation

**Excel Formula Pattern:**
```excel
=Tax_Liability + SE_Tax
```

**Business Logic:**
- Total Tax = Tax Liability (income tax) + SE Tax (self-employment tax)

**Database Equivalent:**
```sql
SELECT 
  tax_liability + se_tax as total_tax
FROM tax_projections
WHERE id = projection_id;
```

**Database Table/Column:**
- Source: `tax_projections.tax_liability`, `tax_projections.se_tax`
- Output: `tax_projections.total_tax`

---

#### 2.10 Federal Withholding Aggregation

**Excel Formula Pattern:**
```excel
=SUMIFS(
  withholding_amounts,
  recipient_ssn_range,
  taxpayer_ssn,
  tax_year_range,
  current_year
)
```

**Business Logic:**
- Sum all federal withholding from income documents
- Filter by recipient SSN (taxpayer or spouse)
- Includes: W-2 withholding, 1099-R withholding, etc.

**Database Equivalent:**
```sql
SELECT 
  COALESCE(SUM(federal_withholding), 0) as tp_withholding
FROM income_documents
WHERE tax_year_id = $1
  AND recipient_ssn = (SELECT primary_ssn FROM cases WHERE id = case_id)
  AND is_excluded = false;
```

**Database Table/Column:**
- Source: `income_documents.federal_withholding`
- Output: `tax_projections.tp_withholding` or `spouse_withholding`

---

#### 2.11 Projected Balance Calculation

**Excel Formula Pattern:**
```excel
=Total_Tax - Total_Withholding
```

**Business Logic:**
- Projected Balance = Total Tax Owed - Total Withholding Paid
- Positive = Owed to IRS
- Negative = Refund due

**Database Equivalent:**
```sql
SELECT 
  total_tax - (tp_withholding + COALESCE(spouse_withholding, 0)) as projected_balance
FROM tax_projections
WHERE id = projection_id;
```

**Database Table/Column:**
- Source: `tax_projections.total_tax`, `tax_projections.tp_withholding`, `spouse_withholding`
- Output: `tax_projections.projected_balance`
- Also stored in: `tax_years.projected_balance` (for lookup)

**Validation:**
- Positive = amount owed
- Negative = refund

---

## 3. Account Balance Calculations

### Purpose
Calculate current IRS account balance for a tax year by summing all balance-affecting transactions.

### Equation Types

#### 3.1 Current Balance (Sum Balance-Affecting Transactions)

**Excel Formula Pattern:**
```excel
=SUMIFS(
  transaction_amounts,
  transaction_codes_range,
  affects_balance_codes,
  tax_year_range,
  current_year
)
```

**Business Logic:**
- Sum all transactions where `affects_balance = true` (from AI Glossary rules)
- Include: Code 150 (Return Filed), Code 806 (Withholding Credit), Code 420 (Audit), etc.
- Exclude: Code 670 (Levy - doesn't affect balance)

**Database Equivalent:**
```sql
SELECT 
  COALESCE(SUM(aa.amount), 0) as current_balance
FROM account_activity aa
JOIN at_transaction_rules atr ON aa.code = atr.code
WHERE aa.tax_year_id = $1
  AND atr.affects_balance = true;
```

**Database Table/Column:**
- Source: `account_activity.amount`
- Filter: `at_transaction_rules.affects_balance = true`
- Output: `tax_years.current_balance`
- Function: `calculate_account_balance(UUID)`

**Validation:**
- Verify business rule lookup (transaction rules)
- Check: Only transactions with `affects_balance = true` are included
- Test with known transaction sets

---

#### 3.2 Return Filed Date (Code 150)

**Excel Formula Pattern:**
```excel
=IFERROR(
  MINIFS(
    transaction_dates,
    transaction_codes_range,
    "150",
    tax_year_range,
    current_year
  ),
  ""
)
```

**Business Logic:**
- Find earliest transaction date where code = '150' (Return Filed)
- This is the assessment date that starts the CSED clock

**Database Equivalent:**
```sql
SELECT 
  MIN(activity_date) as return_filed_date
FROM account_activity
WHERE tax_year_id = $1
  AND code = '150';
```

**Database Table/Column:**
- Source: `account_activity.activity_date`
- Filter: `account_activity.code = '150'`
- Output: `tax_years.return_filed_date`

**Validation:**
- Verify: Code 150 exists
- Check: Returns earliest date if multiple Code 150 transactions

---

## 4. AUR (Automated Underreporter) Calculations

### Purpose
Detect and calculate AUR assessments - additional tax assessed by IRS when income is underreported.

### Equation Types

#### 4.1 AUR Detection

**Excel Formula Pattern:**
```excel
=IF(
  AND(
    return_filed = "Filed",
    EXISTS(transaction_code IN {"420", "424", "430"}),
    account_balance > 0
  ),
  "AUR",
  ""
)
```

**Business Logic:**
- AUR exists if:
  - Return was filed
  - Transaction codes 420, 424, or 430 exist (examination/audit codes)
  - Account balance > 0
- AUR = Automated Underreporter notice

**Database Equivalent:**
```sql
SELECT 
  CASE 
    WHEN ty.return_filed = true
      AND EXISTS (
        SELECT 1 FROM account_activity 
        WHERE tax_year_id = ty.id
          AND code IN ('420', '424', '430')
      )
      AND ty.current_balance > 0
    THEN 'AUR'
    ELSE NULL
  END as aur_indicator
FROM tax_years ty
WHERE ty.id = tax_year_id;
```

**Database Table/Column:**
- Source: `tax_years.return_filed`, `account_activity.code`, `tax_years.current_balance`
- Output: `tax_years.aur_indicator` or `aur_analysis.aur_status`

**Validation:**
- Verify transaction code lookup
- Check: All three conditions must be true

---

#### 4.2 AUR Projected Amount

**Excel Formula Pattern:**
```excel
=IF(
  aur_indicator = "AUR",
  SUMIFS(
    transaction_amounts,
    transaction_codes_range,
    {"420", "424", "430"},
    tax_year_range,
    current_year
  ),
  ""
)
```

**Business Logic:**
- If AUR detected, sum amounts from AUR transaction codes
- Codes 420, 424, 430 represent audit assessments

**Database Equivalent:**
```sql
SELECT 
  CASE 
    WHEN aur_indicator = 'AUR' THEN
      COALESCE(SUM(amount), 0)
    ELSE NULL
  END as aur_projected_amount
FROM account_activity
WHERE tax_year_id = $1
  AND code IN ('420', '424', '430');
```

**Database Table/Column:**
- Source: `account_activity.amount`
- Filter: `account_activity.code IN ('420', '424', '430')`
- Output: `aur_analysis.aur_projected_amount`

---

## 5. SFR (Substitute For Return) Calculations

### Purpose
Detect and calculate SFR assessments - when IRS files a return on taxpayer's behalf.

### Equation Types

#### 5.1 SFR Detection

**Excel Formula Pattern:**
```excel
=IF(
  AND(
    return_filed = "Filed",
    EXISTS(transaction_code = "150"),
    transaction_explanation LIKE "*SFR*" OR transaction_explanation LIKE "*Substitute*"
  ),
  "SFR",
  ""
)
```

**Business Logic:**
- SFR exists if:
  - Return was filed (Code 150 exists)
  - Transaction explanation contains "SFR" or "Substitute"
- SFR = IRS filed return on taxpayer's behalf

**Database Equivalent:**
```sql
SELECT 
  CASE 
    WHEN ty.return_filed = true
      AND EXISTS (
        SELECT 1 FROM account_activity 
        WHERE tax_year_id = ty.id
          AND code = '150'
          AND (explanation ILIKE '%SFR%' OR explanation ILIKE '%Substitute%')
      )
    THEN 'SFR'
    ELSE NULL
  END as sfr_indicator
FROM tax_years ty
WHERE ty.id = tax_year_id;
```

**Database Table/Column:**
- Source: `account_activity.code`, `account_activity.explanation`
- Output: `tax_years.sfr_indicator`

**Validation:**
- Verify explanation text matching
- Check: Code 150 + SFR keywords

---

#### 5.2 SFR Date

**Excel Formula Pattern:**
```excel
=IF(
  sfr_indicator = "SFR",
  MINIFS(
    transaction_dates,
    transaction_codes_range,
    "150",
    transaction_explanation_range,
    "*SFR*"
  ),
  ""
)
```

**Business Logic:**
- Find date of Code 150 transaction where explanation contains "SFR"
- This is the SFR filing date

**Database Equivalent:**
```sql
SELECT 
  MIN(activity_date) as sfr_date
FROM account_activity
WHERE tax_year_id = $1
  AND code = '150'
  AND (explanation ILIKE '%SFR%' OR explanation ILIKE '%Substitute%');
```

**Database Table/Column:**
- Source: `account_activity.activity_date`
- Output: `tax_years.sfr_date`

---

#### 5.3 SFR CSED Calculation

**Excel Formula Pattern:**
```excel
=IF(
  sfr_date <> "",
  sfr_date + 3652,  // 10 years
  ""
)
```

**Business Logic:**
- SFR CSED = SFR Date + 10 years (3652 days)
- May differ from regular CSED if SFR date is different from regular filed date

**Database Equivalent:**
```sql
SELECT 
  CASE 
    WHEN sfr_date IS NOT NULL THEN
      sfr_date + INTERVAL '10 years'
    ELSE NULL
  END as sfr_csed_date
FROM tax_years
WHERE id = tax_year_id;
```

**Database Table/Column:**
- Source: `tax_years.sfr_date`
- Output: `tax_years.sfr_csed_date`

---

## 6. Income Aggregation Calculations

### Purpose
Aggregate income documents by category, SSN, and tax year.

### Equation Types

#### 6.1 Total Income (All Sources)

**Excel Formula Pattern:**
```excel
=SUMIFS(
  income_amounts,
  recipient_ssn_range,
  target_ssn,
  tax_year_range,
  current_year
)
```

**Business Logic:**
- Sum all income documents for a specific recipient SSN
- Includes: W-2, 1099-NEC, 1099-MISC, 1099-R, etc.
- Used for taxpayer and spouse separately

**Database Equivalent:**
```sql
SELECT 
  COALESCE(SUM(gross_amount), 0) as total_income
FROM income_documents
WHERE tax_year_id = $1
  AND recipient_ssn = $2  -- taxpayer_ssn or spouse_ssn
  AND is_excluded = false;
```

---

#### 6.2 Non-Self-Employment Income

**Excel Formula Pattern:**
```excel
=SUMIFS(
  income_amounts,
  recipient_ssn_range,
  target_ssn,
  is_self_employment_range,
  FALSE,
  tax_year_range,
  current_year
)
```

**Business Logic:**
- Sum income where `is_self_employment = false` (from business rules)
- Includes: W-2, 1099-R, Interest, Dividends, etc.

**Database Equivalent:**
```sql
SELECT 
  COALESCE(SUM(gross_amount), 0) as non_se_income
FROM income_documents id
JOIN wi_type_rules wtr ON id.form_type = wtr.form_code
WHERE id.tax_year_id = $1
  AND id.recipient_ssn = $2
  AND wtr.is_self_employment = false
  AND id.is_excluded = false;
```

---

#### 6.3 Self-Employment Income (by Form Type)

**Excel Formula Pattern:**
```excel
=SUMIFS(
  income_amounts,
  form_type_range,
  {"1099-NEC", "1099-MISC"},
  recipient_ssn_range,
  target_ssn,
  tax_year_range,
  current_year
)
```

**Business Logic:**
- Sum income from specific form types that indicate self-employment
- Based on AI Glossary business rules

**Database Equivalent:**
```sql
SELECT 
  COALESCE(SUM(gross_amount), 0) as se_income
FROM income_documents id
JOIN wi_type_rules wtr ON id.form_type = wtr.form_code
WHERE id.tax_year_id = $1
  AND id.recipient_ssn = $2
  AND wtr.is_self_employment = true
  AND id.is_excluded = false;
```

---

#### 6.4 Retirement Income (1099-R)

**Excel Formula Pattern:**
```excel
=SUMIFS(
  income_amounts,
  form_type_range,
  "1099-R",
  recipient_ssn_range,
  target_ssn,
  tax_year_range,
  current_year
)
```

**Business Logic:**
- Sum income from Form 1099-R (retirement distributions)
- May be taxable or non-taxable (check Box 2a)

**Database Equivalent:**
```sql
SELECT 
  COALESCE(SUM(gross_amount), 0) as retirement_income
FROM income_documents
WHERE tax_year_id = $1
  AND recipient_ssn = $2
  AND form_type = '1099-R'
  AND is_excluded = false;
```

---

#### 6.5 Federal Withholding Total

**Excel Formula Pattern:**
```excel
=SUMIFS(
  withholding_amounts,
  recipient_ssn_range,
  target_ssn,
  tax_year_range,
  current_year
)
```

**Business Logic:**
- Sum all federal withholding from income documents
- Includes: W-2 withholding, 1099-R withholding, etc.

**Database Equivalent:**
```sql
SELECT 
  COALESCE(SUM(federal_withholding), 0) as total_withholding
FROM income_documents
WHERE tax_year_id = $1
  AND recipient_ssn = $2
  AND is_excluded = false;
```

---

## 7. Resolution Options Calculations

### Purpose
Calculate eligibility and terms for resolution strategies (IA, OIC, CNC).

### Equation Types

#### 7.1 Total Monthly Income

**Excel Formula Pattern:**
```excel
=SUM(taxpayer_monthly_income, spouse_monthly_income, other_monthly_income)
```

**Business Logic:**
- Sum all sources of monthly income
- From interview data or calculated from annual income

**Database Equivalent:**
```sql
SELECT 
  COALESCE(taxpayer_gross_monthly_income, 0) +
  COALESCE(spouse_gross_monthly_income, 0) +
  COALESCE(other_monthly_income, 0) as total_monthly_income
FROM interview_data
WHERE case_id = $1;
```

---

#### 7.2 Allowable Expenses (IRS Standards vs Actual)

**Excel Formula Pattern:**
```excel
=MAX(irs_standard_expense, actual_expense)
```

**Business Logic:**
- For each expense category, use the higher of:
  - IRS Collection Financial Standards
  - Actual expense from interview
- IRS allows the higher amount

**Database Equivalent:**
```sql
SELECT 
  GREATEST(
    irs_standard_amount,
    COALESCE(actual_expense_amount, 0)
  ) as allowable_expense
FROM expense_categories
WHERE case_id = $1
  AND category = expense_category;
```

---

#### 7.3 Total Allowable Expenses

**Excel Formula Pattern:**
```excel
=SUM(
  MAX(irs_food, actual_food),
  MAX(irs_housing, actual_housing),
  MAX(irs_transportation, actual_transportation),
  MAX(irs_healthcare, actual_healthcare),
  // ... all categories
)
```

**Business Logic:**
- Sum MAX(IRS Standard, Actual) for each expense category
- Categories: Food, Housing, Transportation, Healthcare, etc.

**Database Equivalent:**
```sql
SELECT 
  SUM(
    GREATEST(
      irs_standard_amount,
      COALESCE(actual_expense_amount, 0)
    )
  ) as total_allowable_expenses
FROM monthly_expenses
WHERE case_id = $1;
```

---

#### 7.4 Disposable Income

**Excel Formula Pattern:**
```excel
=Total_Monthly_Income - Total_Allowable_Expenses
```

**Business Logic:**
- Disposable Income = Income - Allowable Expenses
- Used to determine resolution options eligibility

**Database Equivalent:**
```sql
SELECT 
  total_monthly_income - total_allowable_expenses as disposable_income
FROM financial_summary
WHERE case_id = $1;
```

---

#### 7.5 Installment Agreement Monthly Payment

**Excel Formula Pattern:**
```excel
=IF(
  disposable_income > 0,
  disposable_income,
  0
)
```

**Business Logic:**
- IA monthly payment = Disposable Income
- If disposable income <= 0, no payment possible

**Database Equivalent:**
```sql
SELECT 
  GREATEST(0, disposable_income_monthly) as ia_monthly_payment
FROM resolution_options
WHERE case_id = $1;
```

---

#### 7.6 Installment Agreement Payoff Months

**Excel Formula Pattern:**
```excel
=IF(
  monthly_payment > 0,
  total_debt / monthly_payment,
  ""
)
```

**Business Logic:**
- Payoff Months = Total Debt / Monthly Payment
- If no payment, can't pay off

**Database Equivalent:**
```sql
SELECT 
  CASE 
    WHEN ia_monthly_payment > 0 THEN
      CEIL(total_debt / ia_monthly_payment)
    ELSE NULL
  END as ia_payoff_months
FROM resolution_options
WHERE case_id = $1;
```

---

#### 7.7 Installment Agreement Eligibility

**Excel Formula Pattern:**
```excel
=IF(
  AND(
    payoff_months < months_until_csed,
    monthly_payment > 0
  ),
  "Eligible",
  "Not Eligible"
)
```

**Business Logic:**
- IA Eligible if:
  - Can pay off debt before CSED expires
  - Monthly payment > 0

**Database Equivalent:**
```sql
SELECT 
  CASE 
    WHEN ia_payoff_months IS NOT NULL
      AND ia_payoff_months < months_until_csed
      AND ia_monthly_payment > 0
    THEN true
    ELSE false
  END as ia_eligible
FROM resolution_options
WHERE case_id = $1;
```

---

#### 7.8 OIC Quick Sale Value (QSV)

**Excel Formula Pattern:**
```excel
=(Total_Assets - Total_Liabilities) * 0.80
```

**Business Logic:**
- QSV = (Assets - Liabilities) × 80%
- Represents quick sale value of assets (80% of equity)

**Database Equivalent:**
```sql
SELECT 
  (total_assets - total_liabilities) * 0.80 as quick_sale_value
FROM resolution_options
WHERE case_id = $1;
```

---

#### 7.9 OIC Future Income Potential

**Excel Formula Pattern:**
```excel
=Disposable_Income * 24
```

**Business Logic:**
- Future Income Potential = Disposable Income × 24 months
- Represents ability to pay over 2 years

**Database Equivalent:**
```sql
SELECT 
  disposable_income_monthly * 24 as future_income_potential
FROM resolution_options
WHERE case_id = $1;
```

---

#### 7.10 OIC Reasonable Collection Potential (RCP)

**Excel Formula Pattern:**
```excel
=Quick_Sale_Value + Future_Income_Potential
```

**Business Logic:**
- RCP = QSV + Future Income Potential
- Total amount IRS could collect

**Database Equivalent:**
```sql
SELECT 
  quick_sale_value + future_income_potential as rcp
FROM resolution_options
WHERE case_id = $1;
```

---

#### 7.11 OIC Recommended Offer

**Excel Formula Pattern:**
```excel
=RCP * 0.90
```

**Business Logic:**
- Recommended Offer = RCP × 90%
- Standard practice is to offer 90% of RCP

**Database Equivalent:**
```sql
SELECT 
  rcp * 0.90 as recommended_offer
FROM resolution_options
WHERE case_id = $1;
```

---

#### 7.12 OIC Eligibility

**Excel Formula Pattern:**
```excel
=IF(
  AND(
    RCP < Total_Debt * 0.80,
    Disposable_Income >= 0
  ),
  "Eligible",
  "Not Eligible"
)
```

**Business Logic:**
- OIC Eligible if:
  - RCP < 80% of Total Debt (significant hardship)
  - Disposable Income >= 0 (can make payments during OIC)

**Database Equivalent:**
```sql
SELECT 
  CASE 
    WHEN rcp < (total_debt * 0.80)
      AND disposable_income_monthly >= 0
    THEN true
    ELSE false
  END as oic_eligible
FROM resolution_options
WHERE case_id = $1;
```

---

#### 7.13 Currently Not Collectible (CNC) Eligibility

**Excel Formula Pattern:**
```excel
=IF(
  disposable_income <= 0,
  "Eligible",
  "Not Eligible"
)
```

**Business Logic:**
- CNC Eligible if Disposable Income <= 0
- Indicates financial hardship

**Database Equivalent:**
```sql
SELECT 
  CASE 
    WHEN disposable_income_monthly <= 0 THEN true
    ELSE false
  END as cnc_eligible
FROM resolution_options
WHERE case_id = $1;
```

---

## 8. Tax Bracket and Deduction Calculations

### Purpose
Lookup and apply tax brackets and standard deductions by year and filing status.

### Equation Types

#### 8.1 Standard Deduction Lookup

See Section 2.6 for detailed formula.

**Database Table:**
```sql
CREATE TABLE standard_deductions (
  year INTEGER,
  filing_status TEXT,
  deduction_amount DECIMAL(10, 2),
  PRIMARY KEY (year, filing_status)
);
```

---

#### 8.2 Tax Bracket Lookup

See Section 2.8 for detailed formula.

**Database Table:**
```sql
CREATE TABLE tax_brackets (
  year INTEGER,
  filing_status TEXT,
  income_min DECIMAL(15, 2),
  income_max DECIMAL(15, 2),
  tax_rate DECIMAL(5, 4),
  PRIMARY KEY (year, filing_status, income_min)
);
```

---

## 9. Self-Employment Tax Calculations

### Purpose
Calculate self-employment tax on SE income.

### Equation Types

#### 9.1 SE Tax Rate Application

See Section 2.4 for detailed formula.

**Key Points:**
- Rate: 15.3%
- Breakdown: 12.4% Social Security + 2.9% Medicare
- Applied to: SE Income (from business rules)

---

## 10. Disposable Income Calculations

### Purpose
Calculate disposable income for resolution analysis.

### Equation Types

#### 10.1 IRS Standards Lookup

**Excel Formula Pattern:**
```excel
=IFERROR(
  VLOOKUP(
    household_size & location,
    irs_standards_table,
    column_index,
    FALSE
  ),
  ""
)
```

**Business Logic:**
- Lookup IRS Collection Financial Standards by:
  - Household size (1-10+)
  - Location (county/state)
  - Category (Food, Housing, Transportation, Healthcare)
- Updated quarterly by IRS

**Database Equivalent:**
```sql
SELECT 
  monthly_amount
FROM irs_collection_standards
WHERE effective_quarter = $1
  AND category = $2
  AND household_size = $3
  AND (county = $4 OR state = $5)
  AND state = $5;
```

**Database Table:**
```sql
CREATE TABLE irs_collection_standards (
  effective_quarter TEXT,  -- '2024-Q1'
  category TEXT,  -- 'Food_Clothing', 'Housing_Utilities', etc.
  household_size INTEGER,
  county TEXT,
  state TEXT,
  monthly_amount DECIMAL(10, 2),
  PRIMARY KEY (effective_quarter, category, household_size, county, state)
);
```

---

## 11. Lookup and Reference Formulas

### Purpose
Common lookup patterns used throughout TI sheets.

### Formula Types

#### 11.1 VLOOKUP Pattern

**Excel Formula Pattern:**
```excel
=IFERROR(
  VLOOKUP(
    lookup_value,
    table_array,
    column_index,
    FALSE  // Exact match
  ),
  ""  // Default if not found
)
```

**Database Equivalent:**
```sql
SELECT 
  column_value
FROM lookup_table
WHERE lookup_key = lookup_value
LIMIT 1;
```

---

#### 11.2 Cross-Sheet Reference

**Excel Formula Pattern:**
```excel
='Sheet Name'!CellReference
```

**Database Equivalent:**
```sql
-- Join to related table
SELECT 
  related_table.column
FROM main_table
JOIN related_table ON main_table.key = related_table.key;
```

---

## 12. Conditional Logic Formulas

### Purpose
Common IF/conditional patterns.

### Formula Types

#### 12.1 IFERROR Pattern

**Excel Formula Pattern:**
```excel
=IFERROR(
  calculation,
  default_value
)
```

**Database Equivalent:**
```sql
SELECT 
  COALESCE(calculation, default_value);
```

---

#### 12.2 Nested IF Pattern

**Excel Formula Pattern:**
```excel
=IF(
  condition1,
  value1,
  IF(
    condition2,
    value2,
    default_value
  )
)
```

**Database Equivalent:**
```sql
SELECT 
  CASE 
    WHEN condition1 THEN value1
    WHEN condition2 THEN value2
    ELSE default_value
  END;
```

---

## 13. Date and Time Calculations

### Purpose
Date arithmetic for CSED, tolling, etc.

### Formula Types

#### 13.1 Date Addition (Days)

**Excel Formula Pattern:**
```excel
=start_date + days
```

**Database Equivalent:**
```sql
SELECT start_date + (days || ' days')::INTERVAL;
```

---

#### 13.2 Date Difference (Days)

**Excel Formula Pattern:**
```excel
=end_date - start_date
```

**Database Equivalent:**
```sql
SELECT EXTRACT(EPOCH FROM (end_date - start_date)) / 86400;
```

---

## 14. Mathematical Aggregation Formulas

### Purpose
Sum, count, average calculations.

### Formula Types

#### 14.1 SUMIFS Pattern

**Excel Formula Pattern:**
```excel
=SUMIFS(
  sum_range,
  criteria_range1,
  criteria1,
  criteria_range2,
  criteria2
)
```

**Database Equivalent:**
```sql
SELECT 
  SUM(sum_column)
FROM table
WHERE criteria1 = value1
  AND criteria2 = value2;
```

---

#### 14.2 COUNTIFS Pattern

**Excel Formula Pattern:**
```excel
=COUNTIFS(
  criteria_range1,
  criteria1,
  criteria_range2,
  criteria2
)
```

**Database Equivalent:**
```sql
SELECT 
  COUNT(*)
FROM table
WHERE criteria1 = value1
  AND criteria2 = value2;
```

---

## 15. Cross-Sheet Reference Patterns

### Purpose
How data flows between sheets.

### Pattern Types

#### 15.1 Tax Investigation → Tax Projection

**Excel Formula Pattern:**
```excel
='Tax Investigation'!D9  // Tax Period
=VLOOKUP(D9, 'Tax Projection'!A:B, 2, FALSE)  // Lookup projected balance
```

**Database Equivalent:**
```sql
SELECT 
  tp.projected_balance
FROM tax_years ty
JOIN tax_projections tp ON ty.tax_year = tp.tax_period
WHERE ty.id = tax_year_id;
```

---

#### 15.2 WI Raw Data → Tax Investigation

**Excel Formula Pattern:**
```excel
='WI Raw Data 18'!AR7  // Income Block 1 Total
='WI Raw Data 18'!AR8  // Income Block 1 Withholding
```

**Database Equivalent:**
```sql
-- Trigger or function transfers WI data to Tax Investigation
INSERT INTO wi_transfer_data (tax_year_id, q_value, r_value, ...)
SELECT ...
FROM income_documents
WHERE tax_year = ...;
```

---

## Validation Checklist

### For Each Equation Type:

- [ ] Excel formula pattern documented
- [ ] Business logic explained
- [ ] Database equivalent provided
- [ ] Database tables/columns identified
- [ ] Database functions created (if applicable)
- [ ] Validation rules defined
- [ ] Edge cases documented

### Overall:

- [ ] All calculation types covered
- [ ] Formulas match Excel implementation
- [ ] Database implementation matches formulas
- [ ] Business rules integrated
- [ ] Error handling defined

---

## How to Use This Document

1. **For Developers:**
   - Find the equation type you need to implement
   - Review Excel formula pattern
   - Implement database equivalent
   - Validate against checklist

2. **For Testing:**
   - Use Excel formulas as expected results
   - Compare database output to Excel calculations
   - Verify edge cases

3. **For Documentation:**
   - Reference this document for all calculation types
   - Update as new equation patterns are discovered
   - Keep Excel and SQL equivalents in sync

---

**Last Updated:** December 2, 2025  
**Status:** Comprehensive reference - covers all major equation types  
**Next Steps:** Implement database functions based on these patterns


