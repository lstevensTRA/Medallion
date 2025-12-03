# Equation Verification Reports

**Purpose:** This directory contains verification reports from running equation checks against the database.

**Script:** `scripts/verify_all_equations_all_cases.py`  
**Reference:** `docs/developer-handoff/COMPLETE_EQUATION_REFERENCE.md`

---

## Quick Start

### Verify All Equations for All Cases

```bash
python scripts/verify_all_equations_all_cases.py
```

This will:
- Check all cases in the database
- Verify all 5 chunks of equations
- Generate JSON and Markdown reports
- Show summary of what's working vs. what needs fixing

### Verify Specific Chunks

```bash
# Just CSED calculations (Chunk 1)
python scripts/verify_all_equations_all_cases.py --chunk 1

# Tax Projections + Account Balance (Chunks 2 & 3)
python scripts/verify_all_equations_all_cases.py --chunk 2,3
```

### Verify Specific Cases

```bash
# Verify all chunks for specific cases
python scripts/verify_all_equations_all_cases.py --cases 1333562,1273247,941839

# Verify Chunk 1 for specific cases
python scripts/verify_all_equations_all_cases.py --chunk 1 --cases 941839
```

### Quick Test (Limit Cases)

```bash
# Test with just 3 cases (faster)
python scripts/verify_all_equations_all_cases.py --limit 3
```

---

## What Gets Verified

### Chunk 1: CSED Calculations
- ✅ Base CSED (Return Filed Date + 10 years)
- ✅ Bankruptcy Tolling (Codes 520, 521)
- ✅ OIC Tolling (Codes 480, 481, 482, 483)
- ✅ CDP Tolling (Code 971)
- ✅ Penalty Tolling (Codes 276, 196)
- ✅ Adjusted CSED (Final calculation)

### Chunk 2: Tax Projections
- ✅ Taxpayer Income Aggregation
- ✅ Spouse Income Aggregation
- ✅ Self-Employment Income
- ✅ Self-Employment Tax (15.3%)
- ✅ Estimated AGI
- ✅ Standard Deduction Lookup
- ✅ Taxable Income
- ✅ Tax Liability (Progressive Brackets)
- ✅ Total Tax
- ✅ Federal Withholding
- ✅ Projected Balance

### Chunk 3: Account Balance
- ✅ Current Balance (Balance-affecting transactions)
- ✅ Return Filed Date (Code 150)

### Chunk 4: AUR/SFR
- ✅ AUR Detection
- ✅ AUR Projected Amount
- ✅ SFR Detection
- ✅ SFR Date
- ✅ SFR CSED

### Chunk 5: Resolution Options
- ✅ Total Monthly Income
- ✅ Allowable Expenses
- ✅ Disposable Income
- ✅ Installment Agreement (IA) Calculations
- ✅ Offer in Compromise (OIC) Calculations
- ✅ Currently Not Collectible (CNC) Eligibility

---

## Report Files

Reports are saved with timestamps:

- **JSON:** `equation_verification_YYYYMMDD_HHMMSS.json`
- **Markdown:** `equation_verification_YYYYMMDD_HHMMSS.md`

### Report Contents

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

## Interpretation Guide

### Status Symbols

- ✅ **Green Checkmark**: Fully implemented and working correctly
- ⚠️ **Warning**: Partially implemented or needs review
- ❌ **Red X**: Not implemented or has errors

### What to Fix First

1. **❌ Missing Functions**: Create database functions
2. **❌ Missing Tables**: Create tables with required columns
3. **⚠️ Missing Columns**: Add columns to existing tables
4. **❌ Calculation Errors**: Fix calculation logic
5. **⚠️ Partial Implementation**: Complete the implementation

---

## Chunk-by-Chunk Verification Plan

See: `EQUATION_VERIFICATION_PLAN.md` for detailed verification steps for each chunk.

---

## Troubleshooting

### "No cases found in database"
- Check database connection in `backend/.env`
- Verify cases exist: `SELECT * FROM cases LIMIT 5;`

### "Missing SUPABASE_URL or SUPABASE_KEY"
- Check `backend/.env` file exists
- Verify environment variables are set

### "Table does not exist"
- Run migrations: `supabase db push`
- Check table exists in Supabase dashboard

### "Function does not exist"
- Check if function was created in migrations
- Verify function name matches reference document

---

**Last Updated:** December 2, 2025

