# ✅ Equation Verification Setup Complete

**Date:** December 2, 2025

---

## What's Been Created

### 1. ✅ Verification Script
**File:** `scripts/verify_all_equations_all_cases.py`

A comprehensive Python script that:
- Fetches all cases from the database
- Verifies equations chunk by chunk (5 chunks total)
- Tests calculations with actual case data
- Generates detailed JSON and Markdown reports
- Supports filtering by chunk, case, or limit

### 2. ✅ Verification Plan
**File:** `docs/verification-reports/EQUATION_VERIFICATION_PLAN.md`

Detailed documentation for each chunk:
- What equations to verify
- Expected database functions/tables
- Validation steps
- Success criteria

### 3. ✅ Quick Start Guide
**File:** `docs/verification-reports/README.md`

Quick reference for:
- Running verification
- Interpreting results
- Troubleshooting

---

## How to Run

### Setup (First Time)

1. **Ensure environment variables are set:**
   ```bash
   # Check backend/.env has:
   SUPABASE_URL=your-url
   SUPABASE_KEY=your-key
   ```

2. **Install dependencies (if needed):**
   ```bash
   pip install supabase python-dotenv
   ```

### Run Verification

#### Option 1: Verify Everything
```bash
python3 scripts/verify_all_equations_all_cases.py
```

#### Option 2: Verify One Chunk at a Time
```bash
# Start with Chunk 1 (CSED Calculations)
python3 scripts/verify_all_equations_all_cases.py --chunk 1

# Then Chunk 2 (Tax Projections)
python3 scripts/verify_all_equations_all_cases.py --chunk 2

# etc...
```

#### Option 3: Test with Limited Cases
```bash
# Test with just 3 cases first
python3 scripts/verify_all_equations_all_cases.py --limit 3
```

#### Option 4: Verify Specific Cases
```bash
# Verify all chunks for case 941839
python3 scripts/verify_all_equations_all_cases.py --cases 941839
```

---

## The 5 Chunks

### Chunk 1: CSED Calculations (~15 min)
- Base CSED (Return Filed Date + 10 years)
- Bankruptcy Tolling
- OIC Tolling
- CDP Tolling
- Penalty Tolling
- Adjusted CSED

### Chunk 2: Tax Projections (~20 min)
- Income Aggregation (Taxpayer & Spouse)
- Self-Employment Income & Tax
- Estimated AGI
- Standard Deduction
- Taxable Income
- Tax Liability (Progressive Brackets)
- Projected Balance

### Chunk 3: Account Balance (~10 min)
- Current Balance
- Return Filed Date

### Chunk 4: AUR/SFR (~15 min)
- AUR Detection & Amount
- SFR Detection & Date
- SFR CSED

### Chunk 5: Resolution Options (~20 min)
- Total Monthly Income
- Allowable Expenses
- Disposable Income
- Installment Agreement
- Offer in Compromise
- Currently Not Collectible

**Total Time:** ~80 minutes for all chunks

---

## What Gets Checked

For each chunk, the script verifies:

1. ✅ **Database Functions Exist**
   - Checks if functions like `calculate_base_csed()` exist
   
2. ✅ **Database Tables/Columns Exist**
   - Checks if tables like `tax_years`, `tax_projections` exist
   - Verifies required columns are present
   
3. ✅ **Business Rules Applied**
   - Checks if lookup tables like `at_transaction_rules` exist
   - Verifies business rules are being used
   
4. ✅ **Actual Calculations**
   - Tests with real case data
   - Verifies calculations produce correct results
   - Identifies discrepancies

---

## Report Output

After running, reports are saved to:
- `docs/verification-reports/equation_verification_YYYYMMDD_HHMMSS.json`
- `docs/verification-reports/equation_verification_YYYYMMDD_HHMMSS.md`

### Report Contents

1. **Summary by Chunk**
   - Cases tested: X
   - Cases passed: Y
   - Cases failed: Z

2. **Sub-Equation Status**
   - ✅ Fully implemented
   - ⚠️ Partially implemented
   - ❌ Not implemented

3. **Missing Components**
   - Missing functions
   - Missing tables/columns
   - Missing business rules

4. **Calculation Errors**
   - Cases with errors
   - Discrepancies from Excel formulas

---

## Next Steps

1. **Run First Verification**
   ```bash
   # Quick test with 3 cases
   python3 scripts/verify_all_equations_all_cases.py --limit 3 --chunk 1
   ```

2. **Review Report**
   - Open the generated Markdown report
   - See what's working ✅
   - See what needs fixing ❌

3. **Fix Issues**
   - Start with most critical (❌ errors)
   - Create missing functions/tables
   - Fix calculation logic

4. **Re-run Verification**
   - Verify fixes work
   - Continue until all chunks pass

5. **Repeat for All Chunks**
   - Work through chunks 1-5 systematically
   - Fix issues as you go

---

## Reference Documents

- **Equation Reference:** `docs/developer-handoff/COMPLETE_EQUATION_REFERENCE.md`
  - Complete list of all equations and their database equivalents
  
- **Verification Plan:** `docs/verification-reports/EQUATION_VERIFICATION_PLAN.md`
  - Detailed verification steps for each chunk

- **Quick Start:** `docs/verification-reports/README.md`
  - Quick reference guide

---

## Success Criteria

All chunks pass when:

- ✅ All required database functions exist
- ✅ All required tables/columns exist
- ✅ All calculations produce correct results
- ✅ All cases have valid data in all equation fields
- ✅ No calculation errors or discrepancies

---

**Ready to start?** Run:
```bash
python3 scripts/verify_all_equations_all_cases.py --limit 3 --chunk 1
```

This will test Chunk 1 (CSED Calculations) with 3 cases to get you started! 🚀

