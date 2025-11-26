# 🥈 Silver Layer Setup Guide

## ✅ What We're Creating

### Silver Tables (Typed & Enriched Data)

| Table | Purpose | Source |
|-------|---------|--------|
| `tax_years` | Tax year summaries | Bronze AT data |
| `account_activity` | AT transactions with enrichment | Bronze AT data |
| `income_documents` | WI forms with enrichment | Bronze WI data |
| `trt_records` | TRT data | Bronze TRT data |
| `logiqs_raw_data` | Interview data | Bronze Interview data |

### SQL Triggers (Automatic Transformation)

| Trigger | What It Does |
|---------|--------------|
| `trigger_bronze_at_to_silver` | Extracts AT data → `tax_years` + `account_activity` |
| `trigger_bronze_wi_to_silver` | Extracts WI data → `income_documents` (with WI type rules) |
| `trigger_bronze_interview_to_silver` | Stores interview → `logiqs_raw_data` |

---

## 📋 Step 1: Apply Migration

**The migration is in your clipboard!**

1. **Open:** https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql
2. **Paste:** `Cmd+V`
3. **Click:** RUN

**Takes ~10 seconds to apply**

---

## ✅ Step 2: Verify It Worked

Run this in Supabase SQL Editor:

```sql
-- Check if Silver tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN ('tax_years', 'account_activity', 'income_documents', 'trt_records', 'logiqs_raw_data')
ORDER BY table_name;
```

**Expected:** 5 tables listed ✅

---

## 🎯 Step 3: Test with Existing Bronze Data

The triggers will **automatically process** your existing Bronze data!

### Option A: Manually Trigger (if needed)

If triggers don't fire automatically, you can manually process:

```sql
-- Process existing AT data
SELECT process_bronze_at() FROM bronze_at_raw WHERE case_id = '1295022';

-- Process existing WI data  
SELECT process_bronze_wi() FROM bronze_wi_raw WHERE case_id = '1295022';
```

### Option B: Insert New Bronze Record (triggers fire automatically)

```sql
-- Triggers fire automatically on INSERT
-- Just insert a new Bronze record and watch Silver populate!
```

---

## 📊 Step 4: Check Silver Data

```sql
-- Check tax years extracted
SELECT 
    case_id,
    tax_year,
    return_filed,
    filing_status,
    agi,
    account_balance
FROM tax_years
WHERE case_id = '1295022'
ORDER BY tax_year DESC;

-- Check account activity
SELECT 
    tax_year,
    activity_date,
    irs_transaction_code,
    explanation,
    amount,
    calculated_transaction_type,
    affects_balance,
    affects_csed
FROM account_activity
WHERE case_id = '1295022'
ORDER BY activity_date DESC
LIMIT 10;

-- Check income documents
SELECT 
    tax_year,
    document_type,
    gross_amount,
    issuer_name,
    calculated_category,
    is_self_employment
FROM income_documents
WHERE case_id = '1295022'
ORDER BY tax_year DESC;
```

---

## 🔍 Step 5: Health Check

```sql
-- View Silver layer health
SELECT * FROM silver_health;
```

**Expected output:**
```
table_name        | record_count | unique_cases | last_insert
------------------|--------------|--------------|------------
tax_years         | 10+          | 1            | [timestamp]
account_activity  | 50+          | 1            | [timestamp]
income_documents  | 5+           | 1            | [timestamp]
```

---

## 🎯 What Happens After Migration

### Automatic Processing

1. **New Bronze data inserted** → Triggers fire automatically
2. **JSONB extracted** → Typed columns created
3. **Business rules applied** → Enrichment added
4. **Silver tables populated** → Ready for queries

### Data Flow

```
Bronze (JSONB)
  ↓ [SQL Trigger]
Silver (Typed + Enriched)
  ↓ [Your Queries]
Clean Business Data
```

---

## 🐛 Troubleshooting

### "Table already exists" error

**Solution:** Tables might already exist from previous migrations. The migration uses `CREATE TABLE IF NOT EXISTS` so it's safe to run.

### "Trigger already exists" error

**Solution:** Migration drops and recreates triggers, so it's safe to run.

### No data in Silver after migration

**Check:**
1. Do you have Bronze data? `SELECT COUNT(*) FROM bronze_at_raw WHERE case_id = '1295022';`
2. Are triggers enabled? `SELECT * FROM information_schema.triggers WHERE trigger_name LIKE '%bronze%';`
3. Check trigger logs: Look for errors in Supabase logs

### Manual trigger test

```sql
-- Test AT trigger manually
DO $$
DECLARE
  v_bronze_record RECORD;
BEGIN
  FOR v_bronze_record IN 
    SELECT * FROM bronze_at_raw WHERE case_id = '1295022' LIMIT 1
  LOOP
    PERFORM process_bronze_at() FROM bronze_at_raw WHERE bronze_id = v_bronze_record.bronze_id;
  END LOOP;
END $$;
```

---

## 📚 What's Next?

After Silver layer is working:

1. ✅ **Verify data quality** - Check that all Bronze data transformed correctly
2. ✅ **Test with 10 cases** - Process batch and verify Silver populated
3. ✅ **Add Gold layer** - Normalized business entities (next phase)
4. ✅ **Query clean data** - Use Silver tables for analytics

---

## ✨ Key Features

### ✅ Automatic Transformation
- No Python code needed
- SQL triggers handle everything
- Runs on every Bronze INSERT

### ✅ Business Rule Enrichment
- WI type rules applied automatically
- AT transaction rules applied automatically
- Enriched columns ready for queries

### ✅ Data Lineage
- `bronze_id` links Silver back to Bronze
- Can trace any Silver record to source
- Full audit trail

### ✅ Field Variation Handling
- COALESCE logic handles all API variations
- Robust parsing functions
- Graceful error handling

---

**Ready to apply?** The migration is in your clipboard! 🚀


