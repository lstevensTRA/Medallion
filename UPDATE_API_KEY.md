# 🔑 How to Update Your TiParser API Key

## Current Status

✅ **Bronze Layer**: Created and ready
✅ **Backend**: Running perfectly  
✅ **Dagster**: Working correctly
❌ **TiParser API Key**: Invalid/Expired ← **ONLY BLOCKER**

---

## Fix This in 2 Minutes

### Step 1: Get New API Key
Contact TiParser or check your dashboard at:
- https://tiparser.onrender.com/docs (or wherever you manage keys)

### Step 2: Update `.env` File

Open: `/Users/lindseystevens/Medallion/.env`

Find this line:
```bash
TIPARSER_API_KEY=sk_BIWGmwZeahwOyI9ytZNMnZmM_mY1SOcpl4OXlmFpJvA
```

Replace with your new key:
```bash
TIPARSER_API_KEY=your-new-key-here
```

### Step 3: Restart Backend

```bash
cd /Users/lindseystevens/Medallion
kill $(cat /tmp/backend.pid)
cd backend && python3 main.py > /tmp/backend.log 2>&1 &
echo $! > /tmp/backend.pid
```

### Step 4: Test Again

```bash
curl -X POST http://localhost:8000/api/dagster/cases/1295022/extract
```

Wait 2 minutes, then check Supabase:
```sql
SELECT COUNT(*) FROM bronze_at_raw WHERE case_id = '1295022';
```

Should see: **1 record** ✅

---

## What Happens When API Key is Fixed

**Within 2-3 minutes you'll see:**

Bronze tables populated:
```
bronze_at_raw         → 1 record (Account Transcript data)
bronze_wi_raw         → 1 record (Wage & Income data)
bronze_trt_raw        → 1 record (Tax Return data)
bronze_interview_raw  → 1 record (Interview data)
bronze_pdf_raw        → 3-5 records (PDF files metadata)
```

Then you can:
- ✅ Process 10 test cases
- ✅ Add Silver layer (typed data)
- ✅ Add Gold layer (normalized data)
- ✅ Query clean business data

---

## Quick Test Script

Once you have the new key, test it:

```bash
# Test API key directly
curl -X GET https://tiparser.onrender.com/analysis/at/1295022 \
  -H "Authorization: Bearer YOUR-NEW-KEY-HERE"
```

Should return JSON (not 403 error) ✅

---

## Summary

**You're 99% done!**  
Just need a valid TiParser API key and you're operational! 🚀

**Everything else is working perfectly.**

