# 📋 Schema Comparison: Expected vs Actual

**Date:** November 25, 2024

---

## 🥉 BRONZE LAYER

### ✅ Status: COMPLETE

| Table | Expected Schema | Actual Schema | Status |
|-------|----------------|---------------|--------|
| `bronze_at_raw` | `bronze_id, case_id, raw_response, inserted_at` | ✅ Matches | ✅ |
| `bronze_wi_raw` | `bronze_id, case_id, raw_response, inserted_at` | ✅ Matches | ✅ |
| `bronze_trt_raw` | `bronze_id, case_id, raw_response, inserted_at` | ✅ Matches | ✅ |
| `bronze_interview_raw` | `bronze_id, case_id, raw_response, inserted_at` | ✅ Matches | ✅ |
| `bronze_pdf_raw` | `pdf_id, case_id, document_type, storage_path` | ✅ Matches | ✅ |

**Data:** 4 AT records, 1 WI record ✅

---

## 🥈 SILVER LAYER

### ⚠️ Status: SCHEMA MISMATCH

### Issue: Existing Tables Use Different Schema

The Silver tables exist but use the **OLD schema** from previous migrations, not our new migration.

### `tax_years` Table

| Expected (New Migration) | Actual (Existing) | Issue |
|-------------------------|-------------------|-------|
| `case_id TEXT` | `case_id UUID` | Different type |
| `tax_year TEXT` | `year INTEGER` | Different name/type |
| `bronze_id UUID` | ❌ Missing | No lineage tracking |
| `return_filed TEXT` | `return_filed TEXT` | ✅ Matches |
| `filing_status TEXT` | `filing_status TEXT` | ✅ Matches |

**Actual Columns (26 total):**
```
id, case_id (UUID), year (INTEGER), filing_status, return_filed, 
return_filed_date, base_csed_date, calculated_agi, calculated_tax_liability, 
calculated_account_balance, created_at, updated_at, reason, status, 
levy_status, lien_filed, projected_balance, exam_aur_analysis, 
aur_projected, notes, owner, source_file, taxable_income, 
tax_per_return, accrued_interest, accrued_penalty
```

### `account_activity` Table

| Expected (New Migration) | Actual (Existing) | Issue |
|-------------------------|-------------------|-------|
| `case_id TEXT` | ❌ Missing | Uses `tax_year_id UUID` FK |
| `tax_year TEXT` | ❌ Missing | Uses `tax_year_id UUID` FK |
| `bronze_id UUID` | ❌ Missing | No lineage tracking |
| `irs_transaction_code TEXT` | ✅ Matches | ✅ |
| `activity_date DATE` | ✅ Matches | ✅ |

**Actual Columns (12 total):**
```
id, tax_year_id (UUID FK), activity_date, irs_transaction_code, 
explanation, amount, calculated_transaction_type, affects_balance, 
affects_csed, indicates_collection_action, created_at, updated_at
```

### `income_documents` Table

| Expected (New Migration) | Actual (Existing) | Issue |
|-------------------------|-------------------|-------|
| `case_id TEXT` | ❌ Missing | Uses `tax_year_id UUID` FK |
| `tax_year TEXT` | ❌ Missing | Uses `tax_year_id UUID` FK |
| `bronze_id UUID` | ❌ Missing | No lineage tracking |
| `document_type TEXT` | ✅ Matches | ✅ |
| `gross_amount DECIMAL` | ✅ Matches | ✅ |

**Actual Columns (18 total):**
```
id, tax_year_id (UUID FK), document_type, gross_amount, 
federal_withholding, calculated_category, is_self_employment, 
include_in_projection, fields (JSONB), created_at, updated_at, 
issuer_id, issuer_name, issuer_address, recipient_id, 
recipient_name, recipient_address, combined_income
```

### Data Flow Status

✅ **Bronze → Silver IS WORKING** (data exists in both)
- 4 Bronze AT records → 74 Silver tax_years + 123 account_activity
- 1 Bronze WI record → 204 Silver income_documents

⚠️ **But triggers may not be from our new migration** - likely using old triggers

---

## 🥇 GOLD LAYER

### ⚠️ Status: PARTIAL

| Table | Exists | Has Data | Schema Status |
|-------|--------|----------|---------------|
| `employment_information` | ✅ | ❌ Empty | Need to verify schema |
| `household_information` | ✅ | ❌ Empty | Need to verify schema |
| `financial_accounts` | ✅ | ❌ Empty | Need to verify schema |
| `monthly_expenses` | ✅ | ❌ Empty | Need to verify schema |
| `income_sources` | ✅ | ✅ 65 records | ✅ Has data |
| `vehicles` | ❌ Missing | - | Need to create |
| `real_estate` | ❌ Missing | - | Need to create |

---

## 🔍 KEY FINDINGS

### 1. **Schema Mismatch: Silver Layer**

**Problem:**
- Our new migration (`006_create_silver_layer.sql`) expects:
  - `case_id TEXT` (external case ID like "1295022")
  - `tax_year TEXT` (string like "2023")
  - `bronze_id UUID` (lineage tracking)

- Existing tables have:
  - `case_id UUID` (internal UUID)
  - `year INTEGER` (numeric year)
  - `tax_year_id UUID` (FK to tax_years)
  - **No `bronze_id`** (no lineage tracking)

**Impact:**
- Our new triggers won't work with existing schema
- No way to trace Silver records back to Bronze source
- Can't validate Bronze → Silver data flow

### 2. **Gold Layer Not Populated**

**Problem:**
- Gold tables exist but are empty
- No triggers to populate from Silver
- Need Silver → Gold triggers

### 3. **Data Flow Working (But Old Triggers)**

**Good News:**
- Bronze → Silver IS working
- Data exists in both layers
- But using OLD triggers/schema

---

## 🎯 RECOMMENDATIONS

### Option 1: **Align with Existing Schema** (Recommended)

**Keep existing Silver schema, update our triggers:**

1. ✅ Keep existing `tax_years`, `account_activity`, `income_documents` tables
2. ✅ Add `bronze_id` columns to existing tables (ALTER TABLE)
3. ✅ Update triggers to work with existing schema:
   - Use `tax_year_id UUID` instead of `case_id TEXT`
   - Use `year INTEGER` instead of `tax_year TEXT`
   - Add `bronze_id` for lineage

**Pros:**
- ✅ No data migration needed
- ✅ Works with existing data
- ✅ Minimal disruption

**Cons:**
- ⚠️ Need to update trigger logic

### Option 2: **Migrate to New Schema**

**Replace existing tables with new schema:**

1. ❌ Drop existing Silver tables (lose data!)
2. ✅ Create new tables with our schema
3. ✅ Re-run triggers to populate from Bronze

**Pros:**
- ✅ Clean, consistent schema
- ✅ Better lineage tracking

**Cons:**
- ❌ Lose existing Silver data
- ❌ Need to re-process all Bronze data
- ❌ More disruptive

### Option 3: **Hybrid Approach**

**Keep both schemas temporarily:**

1. ✅ Keep existing tables for production
2. ✅ Create new tables with `_v2` suffix
3. ✅ Run both in parallel
4. ✅ Migrate gradually

---

## 📋 NEXT STEPS

1. **Decide on approach** (Option 1 recommended)
2. **Add `bronze_id` columns** to existing Silver tables
3. **Update triggers** to work with existing schema
4. **Create Gold layer triggers** (Silver → Gold)
5. **Validate complete flow** (Bronze → Silver → Gold)
6. **Then activate case sensor**

---

## ✅ VALIDATION CHECKLIST

- [x] Bronze layer: Complete and working
- [x] Silver layer: Tables exist, data flowing
- [ ] Silver layer: Schema aligned (needs decision)
- [ ] Silver layer: `bronze_id` columns added
- [ ] Gold layer: All tables created
- [ ] Gold layer: Triggers created (Silver → Gold)
- [ ] Gold layer: Data populated
- [ ] Complete flow validated (Bronze → Silver → Gold)
- [ ] Case sensor ready to activate

---

**Status:** ⚠️ **SCHEMA ALIGNMENT NEEDED BEFORE AUTOMATION**


