# 🏗️ Complete Medallion Architecture Workflow

## Overview

This document explains the complete data flow from external APIs → Bronze → Silver → Gold layers in the Tax Resolution Medallion Architecture.

---

## 📊 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     EXTERNAL APIs                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                      │
│  │ TiParser │  │ TiParser │  │ TiParser │                      │
│  │   AT     │  │   WI     │  │Interview │                      │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                      │
└───────┼─────────────┼─────────────┼────────────────────────────┘
        │             │             │
        ▼             ▼             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    BRONZE LAYER                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │bronze_at_raw │  │bronze_wi_raw │  │bronze_interv │         │
│  │  (JSONB)     │  │  (JSONB)     │  │iew_raw(JSONB)│         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
└─────────┼──────────────────┼──────────────────┼─────────────────┘
          │                  │                  │
          │ [SQL Triggers]   │ [SQL Triggers]   │ [SQL Triggers]
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SILVER LAYER                                  │
│  ┌──────────┐ ┌──────────────┐ ┌────────────┐ ┌───────────┐   │
│  │tax_years │ │account_activi│ │income_docum│ │logiqs_raw │   │
│  │          │ │ty            │ │ents        │ │_data      │   │
│  └────┬─────┘ └──────┬───────┘ └─────┬──────┘ └─────┬─────┘   │
└───────┼──────────────┼───────────────┼──────────────┼─────────┘
        │              │               │              │
        │ [SQL Triggers]               │              │
        │                              │              │
        ▼                              ▼              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     GOLD LAYER                                   │
│  ┌──────────────┐ ┌──────────┐ ┌──────────────┐ ┌──────────┐  │
│  │employment_inf│ │monthly_ex│ │household_inf │ │income_sou│  │
│  │ormation      │ │penses    │ │ormation      │ │rces      │  │
│  └──────────────┘ └──────────┘ └──────────────┘ └──────────┘  │
│  ┌──────────────┐ ┌──────────────┐                            │
│  │financial_acco│ │vehicles_v2   │                            │
│  │unts          │ │real_property_│                            │
│  └──────────────┘ └──────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Step-by-Step Workflow

### STEP 1: Trigger Data Extraction

**Method 1: Via Dagster API** (Recommended)
```bash
# Trigger via FastAPI endpoint
curl -X POST http://localhost:8000/api/dagster/cases/1295022/extract
```

**Method 2: Via Dagster CLI**
```bash
# Materialize Bronze assets for a case
dagster asset materialize -m dagster_pipeline \
  --config '{"ops": {"bronze_at_data": {"config": {"case_id": "1295022", "case_number": "1295022"}}}}'
```

**Method 3: Via Python Script**
```python
from dagster import materialize
from dagster_pipeline import defs
from dagster_pipeline.assets import bronze_at_data, bronze_wi_data, bronze_interview_data

# Materialize all Bronze assets
result = materialize(
    [bronze_at_data, bronze_wi_data, bronze_interview_data],
    resources=defs.resources,
    run_config={
        "ops": {
            "bronze_at_data": {"config": {"case_id": "1295022", "case_number": "1295022"}},
            "bronze_wi_data": {"config": {"case_id": "1295022", "case_number": "1295022"}},
            "bronze_interview_data": {"config": {"case_id": "1295022", "case_number": "1295022"}}
        }
    }
)
```

---

### STEP 2: Bronze Layer - Raw Data Ingestion

**Dagster Assets:**
- `bronze_at_data` → Calls TiParser AT API → Stores in `bronze_at_raw`
- `bronze_wi_data` → Calls TiParser WI API → Stores in `bronze_wi_raw`
- `bronze_trt_data` → Calls TiParser TRT API → Stores in `bronze_trt_raw`
- `bronze_interview_data` → Calls TiParser Interview API → Stores in `bronze_interview_raw`

**What Happens:**
1. Dagster asset calls external API (TiParser)
2. Raw JSON response stored in Bronze table as `JSONB`
3. Metadata recorded: `bronze_id`, `case_id`, `inserted_at`

**Example Bronze Record:**
```json
{
  "bronze_id": "uuid-here",
  "case_id": "1295022",
  "raw_response": {
    "at_records": [...],
    "metadata": {...}
  },
  "inserted_at": "2024-01-15T10:30:00Z"
}
```

**SQL Triggers Automatically Fire:**
- When `bronze_at_raw` record inserted → `trigger_bronze_at_to_silver` fires
- When `bronze_wi_raw` record inserted → `trigger_bronze_wi_to_silver` fires
- When `bronze_interview_raw` record inserted → `trigger_bronze_interview_to_silver` fires

---

### STEP 3: Silver Layer - Typed & Enriched Data

**Automatic Transformation (SQL Triggers):**

#### 3.1: AT Data → `tax_years` + `account_activity`

**Trigger:** `process_bronze_at()`

**Process:**
1. Extract tax years from `bronze_at_raw.raw_response`
2. For each tax year:
   - Create/update `tax_years` record
   - Extract account activity transactions
   - Create `account_activity` records with IRS transaction codes

**Example:**
```sql
-- Trigger automatically extracts:
INSERT INTO tax_years (case_id, year, return_filed, filing_status, calculated_agi)
VALUES (case_uuid, 2023, TRUE, 'Married Filing Jointly', 75000.00);

INSERT INTO account_activity (tax_year_id, activity_date, irs_transaction_code, amount)
VALUES (tax_year_uuid, '2023-04-15', '150', 1250.00);
```

#### 3.2: WI Data → `income_documents`

**Trigger:** `process_bronze_wi()`

**Process:**
1. Extract forms from `bronze_wi_raw.raw_response->years_data`
2. For each form:
   - Extract form type (W-2, 1099-NEC, etc.)
   - Extract income, withholding, issuer, recipient
   - Lookup WI type rules (self-employment status)
   - Create `income_documents` record

**Example:**
```sql
-- Trigger automatically extracts:
INSERT INTO income_documents (
  tax_year_id, document_type, gross_amount, federal_withholding,
  issuer_name, issuer_id, calculated_category, is_self_employment
)
VALUES (
  tax_year_uuid, '1099-NEC', 50000.00, 0.00,
  'ABC Company', '12-3456789', 'SE', TRUE
);
```

#### 3.3: Interview Data → `logiqs_raw_data`

**Trigger:** `process_bronze_interview()`

**Process:**
1. Extract all sections from `bronze_interview_raw.raw_response`
2. Store in `logiqs_raw_data` with Excel cell references (b3, c7, etc.)
3. This preserves the original structure for backward compatibility

**Example:**
```sql
-- Trigger automatically extracts:
INSERT INTO logiqs_raw_data (
  case_id, employment, household, assets, income, expenses,
  b3, b4, b5, -- Employment (taxpayer)
  c3, c4, c5, -- Employment (spouse)
  al7, al8    -- Monthly income calculations
)
VALUES (...);
```

**Business Rules Applied:**
- WI Type Rules: `wi_type_rules` table determines if form is self-employment
- AT Transaction Rules: `at_transaction_rules` determines if transaction affects balance/CSED

---

### STEP 4: Gold Layer - Normalized Business Entities

**Automatic Transformation (SQL Triggers):**

#### 4.1: `logiqs_raw_data` → Gold Tables

**Trigger:** `process_silver_to_gold()`

**Process:**
1. Extract employment information → `employment_information`
2. Extract household information → `household_information`
3. Extract expenses → `monthly_expenses`
4. Extract income sources → `income_sources`
5. Extract financial accounts → `financial_accounts`
6. Extract vehicles → `vehicles_v2`
7. Extract real property → `real_property_v2`

**Example:**
```sql
-- Trigger automatically creates:
INSERT INTO employment_information (
  case_id, person_type, employer_name, gross_monthly_income
)
VALUES (
  case_uuid, 'taxpayer', 'ABC Company', 4166.67
);

INSERT INTO monthly_expenses (
  case_id, expense_category, amount, frequency
)
VALUES (
  case_uuid, 'housing', 1500.00, 'monthly'
);
```

#### 4.2: `income_documents` → `income_sources`

**Trigger:** `process_income_to_gold()` (Currently disabled - needs schema fix)

**Process:**
1. Aggregate income documents by type
2. Calculate monthly income from annual amounts
3. Create `income_sources` records

---

## 🔍 Data Flow Example: Case 1295022

### Input
- Case Number: `1295022`
- APIs Called: TiParser AT, WI, Interview

### Bronze Layer
```
bronze_at_raw:      10 records (10 API calls)
bronze_wi_raw:       4 records (4 API calls)
bronze_interview_raw: 1 record (1 API call)
```

### Silver Layer (Automatic via Triggers)
```
tax_years:          11 records (11 tax years found in AT data)
account_activity:   40 records (40 transactions extracted)
income_documents:  100+ records (100+ forms from WI data)
logiqs_raw_data:     1 record (Interview data flattened)
```

### Gold Layer (Automatic via Triggers)
```
employment_information:  2 records (taxpayer + spouse)
monthly_expenses:        5 records (housing, food, etc.)
household_information:   1 record (household composition)
income_sources:          0 records (trigger needs schema fix)
```

---

## 🎯 Key Automation Points

### 1. **SQL Triggers** (Database-Level Automation)
- ✅ Bronze → Silver: Automatic via triggers
- ✅ Silver → Gold: Automatic via triggers
- ⚠️ No manual intervention needed (once triggers are enabled)

### 2. **Dagster Orchestration** (Application-Level Automation)
- Schedules: Can run on schedule (daily, hourly)
- Sensors: Can trigger on events (new case created)
- Monitoring: Tracks pipeline health and failures

### 3. **Business Rules** (Lookup Tables)
- `wi_type_rules`: Determines self-employment status
- `at_transaction_rules`: Categorizes IRS transactions
- Applied automatically during Silver → Gold transformation

---

## 📝 Current Status & Known Issues

### ✅ Working
- Bronze ingestion (all sources)
- Bronze → Silver triggers (AT, WI, Interview)
- Silver → Gold trigger (Interview data)
- Business rules application

### ⚠️ Needs Fix
- `process_income_to_gold()` trigger: Needs schema alignment for `income_sources`
- Bronze → Silver triggers: May need manual triggering for existing data
- Income documents: Currently at 100 records (should be 856 total)

---

## 🚀 How to Run Complete Workflow

### Option 1: Full Pipeline (Recommended)
```bash
# 1. Trigger Bronze ingestion
python3 trigger_case_ingestion.py 1295022

# 2. Verify Bronze data
# (Check bronze_at_raw, bronze_wi_raw, bronze_interview_raw)

# 3. Silver data populated automatically
# (Check tax_years, account_activity, income_documents, logiqs_raw_data)

# 4. Gold data populated automatically
# (Check employment_information, monthly_expenses, household_information)
```

### Option 2: Manual Processing (For Existing Data)
```bash
# Process existing Bronze WI data
python3 process_wi_direct_sql.py 1295022

# Process existing Bronze Interview data
python3 process_interview_to_silver_gold.py 1295022
```

---

## 📊 Data Completeness Checklist

For each case, verify:

- [x] Bronze: AT, WI, Interview data ingested
- [x] Silver: tax_years, account_activity populated
- [x] Silver: income_documents populated
- [x] Silver: logiqs_raw_data populated
- [x] Gold: employment_information populated
- [x] Gold: monthly_expenses populated
- [x] Gold: household_information populated
- [ ] Gold: income_sources populated (needs trigger fix)

---

## 🔧 Troubleshooting

### Issue: Silver tables not populated
**Solution:** Check triggers are enabled:
```sql
SELECT trigger_name, event_object_table, action_statement
FROM information_schema.triggers
WHERE event_object_table IN ('bronze_at_raw', 'bronze_wi_raw', 'bronze_interview_raw');
```

### Issue: Gold tables not populated
**Solution:** Check triggers are enabled:
```sql
SELECT trigger_name, event_object_table, action_statement
FROM information_schema.triggers
WHERE event_object_table IN ('logiqs_raw_data', 'income_documents');
```

### Issue: Income documents not processing
**Solution:** Use direct SQL script:
```bash
python3 process_wi_direct_sql.py <case_id>
```

---

## 📚 Related Files

- **Dagster Assets:** `dagster_pipeline/assets/bronze_assets.py`
- **SQL Triggers:** `supabase/migrations/*_triggers.sql`
- **Processing Scripts:** `process_wi_*.py`, `process_interview_*.py`
- **Trigger Scripts:** `trigger_case_ingestion.py`

---

**Last Updated:** 2025-01-27
**Status:** ✅ Bronze → Silver → Gold pipeline operational (with minor fixes needed)

