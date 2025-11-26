# 🚀 Quick Test Guide: Complete Pipeline

## Step 1: Apply Silver → Gold Migration (5 minutes)

### Option A: Via Supabase SQL Editor (Recommended)
1. Open: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql
2. Click "New query"
3. Open file: `APPLY_SILVER_TO_GOLD_TRIGGERS.sql`
4. Copy ALL contents (Cmd+A, Cmd+C)
5. Paste into SQL Editor
6. Click "Run" (or Cmd+Enter)
7. Verify success message

### Option B: Verify Trigger Exists
Run this in Supabase SQL Editor:
```sql
SELECT tgname, tgrelid::regclass 
FROM pg_trigger 
WHERE tgname = 'trigger_silver_to_gold';
```

Should return 1 row with `trigger_silver_to_gold` and `logiqs_raw_data`.

---

## Step 2: Test Complete Pipeline (10 minutes)

### Run Test Script
```bash
cd /Users/lindseystevens/Medallion
python3 test_complete_pipeline.py 1295022
```

### What It Does:
1. ✅ Checks if Silver → Gold trigger is applied
2. ✅ Triggers Bronze ingestion via Dagster
3. ✅ Verifies Bronze layer populated
4. ✅ Verifies Silver layer populated (via triggers)
5. ✅ Verifies Gold layer populated (via triggers)
6. ✅ Shows summary of results

### Expected Output:
```
🧪 COMPLETE PIPELINE TEST: Bronze → Silver → Gold
================================================================================

📋 Testing with case ID: 1295022

STEP 1: Check Silver → Gold Trigger
--------------------------------------------------------------------------------
🔍 Checking Silver → Gold trigger status...

STEP 2: Trigger Bronze Ingestion
--------------------------------------------------------------------------------
🚀 Triggering Bronze ingestion for case: 1295022
...
✅ Bronze ingestion completed!

STEP 3: Verify Bronze Layer
--------------------------------------------------------------------------------
🔍 Verifying Bronze Layer...
   ✅ bronze_at_raw: 1 record(s)
   ✅ bronze_wi_raw: 1 record(s)
   ✅ bronze_interview_raw: 1 record(s)

STEP 4: Verify Silver Layer
--------------------------------------------------------------------------------
🔍 Verifying Silver Layer...
   ✅ tax_years: 3 record(s)
   ✅ account_activity: 15 record(s)
   ✅ income_documents: 8 record(s)
   ✅ logiqs_raw_data: 1 record(s)

STEP 5: Verify Gold Layer
--------------------------------------------------------------------------------
🔍 Verifying Gold Layer...
   ✅ employment_information: 2 record(s)
   ✅ household_information: 1 record(s)
   ✅ monthly_expenses: 25 record(s)
   ✅ income_sources: 12 record(s)
   ✅ financial_accounts: 3 record(s)
   ✅ vehicles_v2: 2 record(s)
   ✅ real_property_v2: 1 record(s)

📊 TEST SUMMARY
================================================================================
🥉 Bronze Layer: 3 total records
🥈 Silver Layer: 27 total records
🥇 Gold Layer: 46 total records

🎉 SUCCESS! Complete pipeline is working!
   Bronze → Silver → Gold (all layers populated)
```

---

## Step 3: Manual Verification (Optional)

### Check Bronze Data
```sql
SELECT 
  'bronze_at_raw' as table_name,
  COUNT(*) as count,
  MAX(inserted_at) as latest
FROM bronze_at_raw
WHERE case_id = '1295022'
UNION ALL
SELECT 
  'bronze_wi_raw',
  COUNT(*),
  MAX(inserted_at)
FROM bronze_wi_raw
WHERE case_id = '1295022'
UNION ALL
SELECT 
  'bronze_interview_raw',
  COUNT(*),
  MAX(inserted_at)
FROM bronze_interview_raw
WHERE case_id = '1295022';
```

### Check Silver Data
```sql
SELECT 
  'tax_years' as table_name,
  COUNT(*) as count
FROM tax_years t
JOIN cases c ON t.case_id = c.id
WHERE c.case_number = '1295022'
UNION ALL
SELECT 
  'logiqs_raw_data',
  COUNT(*)
FROM logiqs_raw_data l
JOIN cases c ON l.case_id = c.id
WHERE c.case_number = '1295022';
```

### Check Gold Data
```sql
SELECT 
  'employment_information' as table_name,
  COUNT(*) as count,
  person_type
FROM employment_information e
JOIN cases c ON e.case_id = c.id
WHERE c.case_number = '1295022'
GROUP BY person_type
UNION ALL
SELECT 
  'monthly_expenses',
  COUNT(*),
  expense_category
FROM monthly_expenses m
JOIN cases c ON m.case_id = c.id
WHERE c.case_number = '1295022'
GROUP BY expense_category;
```

---

## Troubleshooting

### Issue: Silver → Gold trigger not found
**Solution:** Apply migration `APPLY_SILVER_TO_GOLD_TRIGGERS.sql` in Supabase SQL Editor

### Issue: Bronze populated but Silver empty
**Solution:** Check Bronze → Silver triggers are active:
```sql
SELECT tgname, tgrelid::regclass 
FROM pg_trigger 
WHERE tgname LIKE 'trigger_bronze%';
```

### Issue: Silver populated but Gold empty
**Solution:** Check Silver → Gold trigger is active:
```sql
SELECT tgname, tgrelid::regclass 
FROM pg_trigger 
WHERE tgname = 'trigger_silver_to_gold';
```

### Issue: Dagster assets failing
**Solution:** 
1. Check Dagster UI: http://localhost:3000
2. Check API keys in `.env`
3. Verify Supabase project is not paused

---

## Next Steps After Testing

1. ✅ Validate data accuracy (compare Excel vs Gold tables)
2. ✅ Test SQL functions (calculate_total_monthly_income, etc.)
3. ✅ Activate case sensor for automatic case detection
4. ✅ Add monitoring/alerting for failed triggers

---

**🎉 Once all tests pass, your Medallion Architecture is complete!**

