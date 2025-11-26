# 🔄 Complete Pipeline Flow: Bronze → Silver → Gold

## Overview

When you trigger a case extraction, here's what happens at each layer:

---

## 🥉 BRONZE LAYER (Raw API Data)

**What Happens:**
1. Dagster calls external APIs:
   - `bronze_at_data` → TiParser `/analysis/at/{case_id}`
   - `bronze_wi_data` → TiParser `/analysis/wi/{case_id}`
   - `bronze_trt_data` → TiParser `/analysis/trt/{case_id}`
   - `bronze_interview_data` → CaseHelper `/api/cases/{case_id}/interview`

2. Raw JSON responses stored in Bronze tables:
   - `bronze_at_raw` - Entire AT response as JSONB
   - `bronze_wi_raw` - Entire WI response as JSONB
   - `bronze_trt_raw` - Entire TRT response as JSONB
   - `bronze_interview_raw` - Entire interview response as JSONB

3. **SQL Triggers Fire Automatically:**
   - `trigger_bronze_at_to_silver` → Extracts to Silver
   - `trigger_bronze_wi_to_silver` → Extracts to Silver
   - `trigger_bronze_trt_to_silver` → Extracts to Silver
   - `trigger_bronze_interview_to_silver` → Extracts to Silver

**Data Stored:**
- Complete raw JSONB (for audit/replay)
- `bronze_id` (for lineage tracking)
- `case_id` (external case identifier)
- `inserted_at` (timestamp)

---

## 🥈 SILVER LAYER (Typed & Enriched Data)

**What Happens (Automatic via Triggers):**

### AT Data → Silver
1. **Trigger:** `process_bronze_at()`
2. **Extracts from JSONB:**
   - Tax years → `tax_years` table
   - Transactions → `account_activity` table
3. **Enrichment:**
   - Joins with `at_transaction_rules` to add:
     - `affects_balance`
     - `affects_csed`
     - `indicates_collection_action`
     - `transaction_type`
4. **Output Tables:**
   - `tax_years` (one row per tax year)
   - `account_activity` (one row per transaction)

### WI Data → Silver
1. **Trigger:** `process_bronze_wi()`
2. **Extracts from JSONB:**
   - Forms array → `income_documents` table
3. **Enrichment:**
   - Joins with `wi_type_rules` to add:
     - `is_self_employment`
     - `calculated_category`
     - `include_in_projection`
4. **Output Table:**
   - `income_documents` (one row per form: W-2, 1099-NEC, etc.)

### TRT Data → Silver
1. **Trigger:** `process_bronze_trt()`
2. **Extracts from JSONB:**
   - TRT records → `trt_records` table
3. **Output Table:**
   - `trt_records` (one row per TRT record)

### Interview Data → Silver
1. **Trigger:** `process_bronze_interview()` (UPDATED - extracts ALL fields!)
2. **Extracts from JSONB:**
   - **Employment:** b3-b7, c3-c7, al7, al8
   - **Household:** b10-b14, c10-c14, b50-b53
   - **Assets:** b18-b29, d20-d29
   - **Income:** b33-b47
   - **Expenses:** b56-b90, ak2-ak8
   - **IRS Standards:** c56-c61, al4-al8, c76, c80
3. **Output Table:**
   - `logiqs_raw_data` (one row per case, ALL fields extracted)

**Data Stored:**
- Typed columns (DATE, NUMERIC, TEXT - not JSONB)
- Business rule enrichments
- `bronze_id` (links back to Bronze source)
- `case_id` (for queries)

---

## 🥇 GOLD LAYER (Normalized Business Entities)

**What Happens (Automatic via Triggers - TO BE IMPLEMENTED):**

### Silver → Gold Transformations

#### From `logiqs_raw_data` → Gold Tables:

1. **Employment Information:**
   - Source: `logiqs_raw_data.b3-b7, c3-c7, al7, al8`
   - Target: `employment_information`
   - Transformation:
     - b3 → `employer_name` (person_type='taxpayer')
     - c3 → `employer_name` (person_type='spouse')
     - b5 → `gross_annual_income` (taxpayer)
     - c5 → `gross_annual_income` (spouse)
     - al7 → `gross_monthly_income` (taxpayer)
     - al8 → `gross_monthly_income` (spouse)

2. **Household Information:**
   - Source: `logiqs_raw_data.b10-b14, c10-c14, b50-b53`
   - Target: `household_information`
   - Transformation:
     - b10 → `total_household_members`
     - b50 → `members_under_65`
     - b51 → `members_over_65`
     - b52 → `state`
     - b53 → `county`

3. **Monthly Expenses:**
   - Source: `logiqs_raw_data.b56-b90, ak2-ak8`
   - Target: `monthly_expenses`
   - Transformation:
     - b56 → `amount` (expense_category='food')
     - b57 → `amount` (expense_category='housekeeping')
     - b64 → `amount` (expense_category='housing', subcategory='mortgage')
     - b79 → `amount` (expense_category='healthcare', subcategory='insurance')
     - b87 → `amount` (expense_category='court_payments')
     - b88 → `amount` (expense_category='child_care')
     - b90 → `amount` (expense_category='insurance', subcategory='term_life')
     - ak7 → `amount` (expense_category='transportation', subcategory='auto_payment')
     - ak8 → `amount` (expense_category='transportation', subcategory='auto_payment')

4. **Income Sources:**
   - Source: `logiqs_raw_data.b33-b47`
   - Target: `income_sources`
   - Transformation:
     - b33 → `amount` (income_type='wages', person_type='taxpayer')
     - b34 → `amount` (income_type='social_security', person_type='taxpayer')
     - b36 → `amount` (income_type='wages', person_type='spouse')
     - b40 → `amount` (income_type='rental_gross')
     - b41 → `amount` (income_type='rental_expenses')

5. **Financial Accounts:**
   - Source: `logiqs_raw_data.b18-b22`
   - Target: `financial_accounts`
   - Transformation:
     - b18 → `current_balance` (account_type='checking' or 'savings')
     - b19 → `current_balance` (account_type='other', description='cash_on_hand')
     - b20 → `current_balance` (account_type='investment')
     - b22 → `current_balance` (account_type='retirement')

6. **Vehicles:**
   - Source: `logiqs_raw_data.b24-b27, d24-d27` (and vehicles grid if exists)
   - Target: `vehicles_v2`
   - Transformation:
     - b24 → `current_value` (vehicle 1)
     - d24 → `loan_balance` (vehicle 1)
     - b25 → `current_value` (vehicle 2)
     - d25 → `loan_balance` (vehicle 2)

7. **Real Estate:**
   - Source: `logiqs_raw_data.b23, d23` (and real property grid if exists)
   - Target: `real_property_v2`
   - Transformation:
     - b23 → `current_market_value`
     - d23 → `mortgage_balance`

**Data Stored:**
- Semantic column names (not Excel cell references)
- Normalized structure (one row per entity)
- Business relationships (foreign keys)
- Ready for queries and reports

---

## 📊 DATA FLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────┐
│                    DAGSTER ORCHESTRATION                    │
│  (bronze_at_data, bronze_wi_data, bronze_interview_data)   │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                    🥉 BRONZE LAYER                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │bronze_at_raw │  │bronze_wi_raw │  │bronze_inter-│      │
│  │  (JSONB)     │  │  (JSONB)     │  │view_raw     │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                  │                  │              │
│         └──────────────────┴──────────────────┘              │
│                        │                                      │
│                        ▼ (SQL Triggers Fire)                 │
└─────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                    🥈 SILVER LAYER                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │tax_years     │  │income_      │  │logiqs_raw_   │      │
│  │account_      │  │documents    │  │data          │      │
│  │activity      │  │             │  │(ALL FIELDS)  │      │
│  └──────┬───────┘  └──────┬──────┘  └──────┬───────┘      │
│         │                  │                  │              │
│         └──────────────────┴──────────────────┘              │
│                        │                                      │
│                        ▼ (SQL Triggers Fire)                 │
└─────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                    🥇 GOLD LAYER                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │employment_   │  │household_    │  │monthly_      │      │
│  │information   │  │information   │  │expenses      │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │income_       │  │financial_   │  │vehicles_v2   │      │
│  │sources       │  │accounts     │  │real_property │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 EXCEL FORMULA REPLACEMENT

**Instead of Excel formulas, you now have SQL functions:**

| Excel Formula | SQL Function |
|--------------|--------------|
| `=SUM('logiqs raw data'!AL7:AL8)` | `calculate_total_monthly_income(case_id)` |
| `=SUM('logiqs raw data'!AK7:AK8)` | `calculate_total_monthly_expenses(case_id)` |
| `D186 - E186` | `calculate_disposable_income(case_id)` |
| `='Logiqs Raw Data'!B56` | `get_cell_value(case_id, 'b56')` |
| Excel Tab "Logiqs Raw Data" | `SELECT * FROM excel_logiqs_raw_data` |
| ResoOptionsPatch macro | `SELECT * FROM excel_reso_options_patch` |

---

## ✅ CURRENT STATUS

**Working:**
- ✅ Bronze → Silver (AT, WI, TRT, Interview)
- ✅ Interview field extraction (ALL fields: expenses, household, employment)
- ✅ Excel formula replacement (SQL functions)

**To Be Implemented:**
- ⏸️ Silver → Gold triggers (populate Gold tables from Silver)
- ⏸️ Gold layer normalization complete

**Next Steps:**
1. Apply migration (extract interview fields + Excel formulas)
2. Test with a case extraction
3. Create Silver → Gold triggers
4. Validate complete flow

