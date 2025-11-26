# 🚀 Apply Migration & Test - Quick Guide

## ✅ Current Status

- ✅ Gold tables exist (`employment_information`, etc.)
- ✅ Silver tables exist (`logiqs_raw_data`, etc.)
- ✅ Bronze tables exist
- ⏳ Silver → Gold trigger: **Ready to apply**

---

## 📋 STEP 1: Apply Silver → Gold Migration (5 minutes)

### Quick Steps:

1. **Open Supabase SQL Editor:**
   ```
   https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql
   ```

2. **Click "New query" button**

3. **Open the migration file:**
   ```
   /Users/lindseystevens/Medallion/APPLY_SILVER_TO_GOLD_TRIGGERS.sql
   ```

4. **Copy ALL contents:**
   - Cmd+A (select all)
   - Cmd+C (copy)

5. **Paste into Supabase SQL Editor**

6. **Click "Run" button** (or press Cmd+Enter)

7. **Verify success:**
   - Should see: "✅ Silver → Gold triggers created!"
   - No errors

### Verify Migration Applied:

Run this in Supabase SQL Editor:
```sql
SELECT tgname, tgrelid::regclass 
FROM pg_trigger 
WHERE tgname = 'trigger_silver_to_gold';
```

Should return 1 row with `trigger_silver_to_gold` and `logiqs_raw_data`.

---

## 🧪 STEP 2: Test Complete Pipeline (10 minutes)

### Run Test Script:

```bash
cd /Users/lindseystevens/Medallion
python3 test_complete_pipeline.py 1295022
```

### What Happens:

1. **Checks migration status** ✅
2. **Asks if you want to trigger Bronze ingestion** (type `y`)
3. **Triggers Dagster assets:**
   - `bronze_at_data` → Fetches AT from TiParser
   - `bronze_wi_data` → Fetches WI from TiParser
   - `bronze_interview_data` → Fetches Interview from CaseHelper
4. **Waits 5 seconds** for SQL triggers to process
5. **Verifies all layers:**
   - 🥉 Bronze Layer (raw JSONB)
   - 🥈 Silver Layer (typed + enriched)
   - 🥇 Gold Layer (normalized entities)
6. **Shows summary** of results

### Expected Results:

```
🥉 Bronze Layer: 3-4 records
   ✅ bronze_at_raw: 1
   ✅ bronze_wi_raw: 1
   ✅ bronze_interview_raw: 1

🥈 Silver Layer: 20-30 records
   ✅ tax_years: 3-5
   ✅ account_activity: 10-20
   ✅ income_documents: 5-10
   ✅ logiqs_raw_data: 1

🥇 Gold Layer: 40-50 records
   ✅ employment_information: 2 (taxpayer + spouse)
   ✅ household_information: 1
   ✅ monthly_expenses: 20-30
   ✅ income_sources: 10-15
   ✅ financial_accounts: 2-5
   ✅ vehicles_v2: 1-4
   ✅ real_property_v2: 0-1
```

---

## 🎯 Success Criteria

✅ **All layers populated:**
- Bronze has raw API responses
- Silver has typed + enriched data
- Gold has normalized business entities

✅ **Triggers working:**
- Bronze → Silver: Automatic
- Silver → Gold: Automatic

✅ **Data accuracy:**
- Gold tables match Excel cell values
- SQL functions work correctly

---

## 🔧 Troubleshooting

### Issue: Migration fails to apply
**Solution:** 
- Check for syntax errors in SQL Editor
- Make sure all Gold tables exist first
- Try running in smaller chunks

### Issue: Bronze populated but Silver empty
**Solution:** Check Bronze → Silver triggers:
```sql
SELECT tgname FROM pg_trigger WHERE tgname LIKE 'trigger_bronze%';
```

### Issue: Silver populated but Gold empty
**Solution:** 
- Verify Silver → Gold trigger is applied
- Check `logiqs_raw_data` has data
- Verify trigger function exists:
```sql
SELECT proname FROM pg_proc WHERE proname = 'process_silver_to_gold';
```

### Issue: Dagster assets failing
**Solution:**
- Check Dagster UI: http://localhost:3000
- Verify API keys in `.env`
- Check Supabase project is not paused

---

## 📊 After Testing

Once all tests pass:

1. ✅ **Validate data accuracy** - Compare Excel vs Gold tables
2. ✅ **Test SQL functions** - `calculate_total_monthly_income()`, etc.
3. ✅ **Activate case sensor** - For automatic case detection
4. ✅ **Add monitoring** - Alert on failed triggers

---

## 🎉 Complete!

Once migration is applied and tests pass, your **Medallion Architecture is 100% complete!**

**Pipeline Flow:**
```
Dagster (API calls)
    ↓
🥉 Bronze (raw JSONB)
    ↓ [SQL Triggers - ✅ ACTIVE]
🥈 Silver (typed + enriched)
    ↓ [SQL Trigger - ✅ ACTIVE]
🥇 Gold (normalized entities)
```

**All automatic! No Excel needed!** 🚀

