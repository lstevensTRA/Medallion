# Equation Verification Plan - Chunk by Chunk

**Purpose:** Systematically verify all equations from `COMPLETE_EQUATION_REFERENCE.md` are implemented and working correctly for all cases in the database.

**Date:** December 2, 2025  
**Reference Document:** `docs/developer-handoff/COMPLETE_EQUATION_REFERENCE.md`

---

## Overview

This plan breaks down the verification process into 5 manageable chunks, each focusing on a major equation category. We'll verify:

1. ✅ Database functions exist
2. ✅ Database tables/columns exist
3. ✅ Calculations match the reference formulas
4. ✅ Actual case data produces correct results

---

## Chunk 1: CSED Calculations ⏱️ ~15 minutes

### Equations to Verify

1. **1.1 Base CSED Calculation**
   - Formula: `return_filed_date + INTERVAL '10 years'`
   - Database Function: `calculate_base_csed(UUID)`
   - Tables: `tax_years.return_filed_date`, `tax_years.base_csed_date`
   - Validation: Check if base_csed_date = return_filed_date + 10 years

2. **1.2 CSED Tolling - Bankruptcy**
   - Codes: 520 (open), 521 (closed)
   - Formula: Base CSED + (interval + 180 days)
   - Tables: `csed_tolling_events`, `account_activity`
   - Validation: Check if bankruptcy tolling is applied

3. **1.3 CSED Tolling - OIC**
   - Codes: 480 (pending), 481/482 (accepted), 483 (withdrawn)
   - Formula: Base CSED + interval + (30 days if accepted)
   - Validation: Check if OIC tolling is applied correctly

4. **1.4 CSED Tolling - CDP**
   - Code: 971 (Collection Due Process)
   - Formula: Base CSED + interval
   - Validation: Check if CDP tolling is applied

5. **1.5 CSED Tolling - Penalties**
   - Codes: 276, 196
   - Formula: Base CSED + 30 days
   - Validation: Check if penalty tolling is applied

6. **1.6 Adjusted CSED (Final)**
   - Formula: MAX of all possible CSED dates
   - Database Function: `calculate_adjusted_csed(UUID)`
   - Validation: Check if adjusted_csed accounts for all tolling

### Verification Steps

```bash
# Run Chunk 1 verification
python scripts/verify_all_equations_all_cases.py --chunk 1
```

### Expected Checks

- [ ] Function `calculate_base_csed` exists
- [ ] Function `calculate_adjusted_csed` exists
- [ ] Table `csed_tolling_events` exists
- [ ] Column `tax_years.base_csed_date` exists
- [ ] Column `tax_years.adjusted_csed_date` exists
- [ ] For each case: base_csed_date is calculated correctly
- [ ] For each case: adjusted_csed_date accounts for tolling

---

## Chunk 2: Tax Projection Calculations ⏱️ ~20 minutes

### Equations to Verify

1. **2.1 Taxpayer Income Aggregation**
   - Formula: `SUM(income_documents.gross_amount WHERE recipient_ssn = taxpayer_ssn)`
   - Tables: `income_documents`, `cases`
   - Validation: Sum matches Excel calculation

2. **2.2 Spouse Income Aggregation**
   - Same as 2.1 but for spouse SSN
   - Validation: Separate totals for taxpayer vs spouse

3. **2.3 Self-Employment Income**
   - Formula: `SUM(income_documents.gross_amount WHERE is_self_employment = true)`
   - Business Rules: Lookup from `wi_type_rules`
   - Validation: SE income matches business rule categorization

4. **2.4 Self-Employment Tax**
   - Formula: `SE_Income * 0.153` (15.3%)
   - Validation: SE tax = SE income × 0.153

5. **2.5 Estimated AGI**
   - Formula: `Total_Income - (SE_Income * 0.0765)`
   - Validation: AGI calculated correctly

6. **2.6 Standard Deduction Lookup**
   - Table: `standard_deductions`
   - Validation: Lookup by year and filing status

7. **2.7 Taxable Income**
   - Formula: `MAX(0, Estimated_AGI - Standard_Deduction)`
   - Validation: Taxable income >= 0

8. **2.8 Tax Liability (Progressive Brackets)**
   - Function: `calculate_tax_liability(taxable_income, filing_status, year)`
   - Table: `tax_brackets`
   - Validation: Progressive brackets applied correctly

9. **2.9 Total Tax**
   - Formula: `Tax_Liability + SE_Tax`
   - Validation: Total tax calculated correctly

10. **2.10 Federal Withholding**
    - Formula: `SUM(income_documents.federal_withholding)`
    - Validation: Withholding totals match

11. **2.11 Projected Balance**
    - Formula: `Total_Tax - Total_Withholding`
    - Tables: `tax_projections.projected_balance`, `tax_years.projected_balance`
    - Validation: Projected balance matches Excel

### Verification Steps

```bash
# Run Chunk 2 verification
python scripts/verify_all_equations_all_cases.py --chunk 2
```

### Expected Checks

- [ ] Table `tax_projections` exists with all required columns
- [ ] Table `income_documents` exists with SE categorization
- [ ] Table `tax_brackets` exists with bracket data
- [ ] Table `standard_deductions` exists
- [ ] Function `calculate_tax_liability` exists
- [ ] For each case: All projection fields populated
- [ ] For each case: Calculations match Excel formulas

---

## Chunk 3: Account Balance Calculations ⏱️ ~10 minutes

### Equations to Verify

1. **3.1 Current Balance**
   - Formula: `SUM(account_activity.amount WHERE affects_balance = true)`
   - Business Rules: Lookup from `at_transaction_rules`
   - Validation: Only balance-affecting transactions included

2. **3.2 Return Filed Date**
   - Formula: `MIN(account_activity.activity_date WHERE code = '150')`
   - Validation: Filed date is earliest Code 150 transaction

### Verification Steps

```bash
# Run Chunk 3 verification
python scripts/verify_all_equations_all_cases.py --chunk 3
```

### Expected Checks

- [ ] Table `account_activity` exists
- [ ] Table `at_transaction_rules` exists with `affects_balance` column
- [ ] Column `tax_years.current_balance` exists
- [ ] Column `tax_years.return_filed_date` exists
- [ ] For each case: Current balance calculated correctly
- [ ] For each case: Return filed date extracted correctly

---

## Chunk 4: AUR/SFR Calculations ⏱️ ~15 minutes

### Equations to Verify

1. **4.1 AUR Detection**
   - Formula: Return filed + Codes 420/424/430 exist + Balance > 0
   - Columns: `tax_years.aur_indicator` or `aur_analysis.aur_status`
   - Validation: AUR detected when conditions met

2. **4.2 AUR Projected Amount**
   - Formula: `SUM(account_activity.amount WHERE code IN ('420', '424', '430'))`
   - Validation: AUR amount matches transaction totals

3. **5.1 SFR Detection**
   - Formula: Code 150 + explanation contains "SFR" or "Substitute"
   - Columns: `tax_years.sfr_indicator`
   - Validation: SFR detected when Code 150 has SFR keywords

4. **5.2 SFR Date**
   - Formula: `MIN(account_activity.activity_date WHERE code = '150' AND explanation LIKE '%SFR%')`
   - Validation: SFR date extracted correctly

5. **5.3 SFR CSED**
   - Formula: `SFR_Date + INTERVAL '10 years'`
   - Validation: SFR CSED calculated correctly

### Verification Steps

```bash
# Run Chunk 4 verification
python scripts/verify_all_equations_all_cases.py --chunk 4
```

### Expected Checks

- [ ] Column `tax_years.aur_indicator` or `aur_analysis.aur_status` exists
- [ ] AUR codes (420, 424, 430) exist in account_activity
- [ ] Column `tax_years.sfr_indicator` exists
- [ ] SFR detection logic works (Code 150 + keywords)
- [ ] For each case: AUR detected when applicable
- [ ] For each case: SFR detected when applicable

---

## Chunk 5: Resolution Options Calculations ⏱️ ~20 minutes

### Equations to Verify

1. **7.1 Total Monthly Income**
   - Formula: `SUM(taxpayer + spouse + other monthly income)`
   - Tables: `interview_data`, `employment_information`
   - Validation: Monthly income totals match

2. **7.2 Allowable Expenses**
   - Formula: `MAX(irs_standard, actual_expense)`
   - Tables: `irs_collection_standards`, `monthly_expenses`
   - Validation: Higher of IRS standard or actual used

3. **7.3 Total Allowable Expenses**
   - Formula: `SUM(MAX(irs_standard, actual) FOR each category)`
   - Validation: All expense categories summed

4. **7.4 Disposable Income**
   - Formula: `Total_Monthly_Income - Total_Allowable_Expenses`
   - Validation: Disposable income calculated correctly

5. **7.5-7.7 Installment Agreement**
   - IA Monthly Payment = Disposable Income
   - IA Payoff Months = Total Debt / Monthly Payment
   - IA Eligible = (Payoff Months < Months Until CSED) AND (Monthly Payment > 0)
   - Validation: IA calculations correct

6. **7.8-7.11 Offer in Compromise**
   - QSV = (Assets - Liabilities) × 0.80
   - Future Income = Disposable Income × 24
   - RCP = QSV + Future Income
   - Recommended Offer = RCP × 0.90
   - Validation: OIC calculations correct

7. **7.12 OIC Eligibility**
   - Formula: RCP < (Total Debt × 0.80) AND Disposable Income >= 0
   - Validation: OIC eligibility logic correct

8. **7.13 Currently Not Collectible**
   - Formula: Disposable Income <= 0
   - Validation: CNC eligibility logic correct

### Verification Steps

```bash
# Run Chunk 5 verification
python scripts/verify_all_equations_all_cases.py --chunk 5
```

### Expected Checks

- [ ] Table `resolution_options` exists with all columns
- [ ] Table `irs_collection_standards` exists
- [ ] Table `monthly_expenses` exists
- [ ] Functions for IA, OIC, CNC calculations exist
- [ ] For each case: Resolution options calculated
- [ ] For each case: Eligibility flags set correctly

---

## Running All Chunks

### Option 1: Run All at Once

```bash
python scripts/verify_all_equations_all_cases.py
```

This will verify all chunks sequentially and generate a comprehensive report.

### Option 2: Run One Chunk at a Time

```bash
# Verify Chunk 1 only
python scripts/verify_all_equations_all_cases.py --chunk 1

# Verify Chunk 2 only
python scripts/verify_all_equations_all_cases.py --chunk 2

# etc...
```

### Option 3: Run for Specific Cases

```bash
# Verify all chunks for specific case numbers
python scripts/verify_all_equations_all_cases.py --cases 1333562,1273247,941839
```

---

## Report Output

After running verification, reports will be generated in:

- **JSON Report:** `docs/verification-reports/equation_verification_YYYYMMDD_HHMMSS.json`
- **Markdown Report:** `docs/verification-reports/equation_verification_YYYYMMDD_HHMMSS.md`

### Report Contents

Each report includes:

1. **Summary by Chunk**
   - Cases tested
   - Cases passed
   - Cases failed

2. **Sub-Equation Status**
   - ✅ Implemented and working
   - ⚠️ Partially implemented
   - ❌ Not implemented or errors

3. **Missing Components**
   - Missing database functions
   - Missing tables/columns
   - Missing business rules

4. **Calculation Errors**
   - Cases with incorrect calculations
   - Discrepancies from Excel formulas

---

## Next Steps After Verification

1. **Review Reports** - Identify what's missing or broken
2. **Prioritize Fixes** - Start with most critical equations
3. **Implement Missing Components** - Create functions/tables as needed
4. **Re-run Verification** - Verify fixes work
5. **Repeat** - Continue until all chunks pass

---

## Success Criteria

All chunks pass when:

- ✅ All required database functions exist
- ✅ All required tables/columns exist
- ✅ All calculations produce correct results
- ✅ All cases have valid data in all equation fields
- ✅ No calculation errors or discrepancies

---

**Last Updated:** December 2, 2025  
**Status:** Ready to run - script created, plan documented

