# ✅ Get Operational Checklist

## 📋 Complete These Steps in Order

### ☐ **Step 1: Apply Database Migrations**

**Options (choose one):**

**Option A - Supabase CLI (Easiest):**
```bash
cd /Users/lindseystevens/Medallion
supabase db push
```

**Option B - Supabase Dashboard (If CLI fails):**
1. Go to https://supabase.com/dashboard
2. Select project: `egxjuewegzdctsfwuslf`
3. Click "SQL Editor"
4. Apply each migration in order:
   - Copy/paste `supabase/migrations/001_create_bronze_tables.sql` → Run
   - Copy/paste `supabase/migrations/002_bronze_to_silver_triggers.sql` → Run
   - Copy/paste `supabase/migrations/003_silver_to_gold_triggers.sql` → Run
   - Copy/paste `supabase/migrations/004_create_pdf_storage_bucket.sql` → Run
   - Copy/paste `supabase/migrations/005_bronze_pdf_metadata_table.sql` → Run

**Option C - Python Helper:**
```bash
python apply_all_migrations.py
```

**Verify:**
```sql
-- Run in Supabase SQL Editor:
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' AND table_name LIKE 'bronze%';
```

---

### ☐ **Step 2: Test TiParser API Key**

```bash
curl -X GET https://tiparser.onrender.com/analysis/at/1295022 \
  -H "Authorization: Bearer sk_BIWGmwZeahwOyI9ytZNMnZmM_mY1SOcpl4OXlmFpJvA"
```

**Expected:**
- ✅ 200 OK with JSON data → Key works!
- ❌ 403 Forbidden → Get new key and update `.env`

---

### ☐ **Step 3: Start Services**

```bash
cd /Users/lindseystevens/Medallion
./start_all.sh
```

**Verify:**
- [ ] Backend running: http://localhost:8000/health
- [ ] Dagster running: http://localhost:3000
- [ ] API docs: http://localhost:8000/docs

---

### ☐ **Step 4: Test with ONE Case**

```bash
# Trigger extraction
curl -X POST http://localhost:8000/api/dagster/cases/1295022/extract

# Wait 2-3 minutes...

# Check status
curl http://localhost:8000/api/dagster/status/1295022
```

**Expected status:**
```json
{
  "status": "complete",
  "bronze": {"total_records": 4},
  "silver": {"total_records": 10+},
  "gold": {"total_records": 5+}
}
```

**Verify in Supabase:**
```sql
-- Check Bronze
SELECT COUNT(*) FROM bronze_at_raw WHERE case_id = '1295022';

-- Check Silver  
SELECT COUNT(*) FROM tax_years WHERE case_id = '1295022';

-- Check Gold
SELECT COUNT(*) FROM employment_information WHERE case_id = '1295022';

-- Check PDFs
SELECT COUNT(*) FROM bronze_pdf_raw WHERE case_id = '1295022';
```

---

### ☐ **Step 5: Process 10 Test Cases**

Edit `process_batch.py` and add your 10 case IDs:
```python
test_cases = [
    "1295022",
    "YOUR_CASE_2",
    "YOUR_CASE_3",
    "YOUR_CASE_4",
    "YOUR_CASE_5",
    "YOUR_CASE_6",
    "YOUR_CASE_7",
    "YOUR_CASE_8",
    "YOUR_CASE_9",
    "YOUR_CASE_10",
]
```

**Run batch:**
```bash
python process_batch.py
```

**Monitor in Dagster UI:** http://localhost:3000/runs

---

### ☐ **Step 6: Verify Results**

```sql
-- Count cases processed
SELECT 
    'Bronze' as layer,
    COUNT(DISTINCT case_id) as cases
FROM bronze_at_raw
UNION ALL
SELECT 
    'Silver' as layer,
    COUNT(DISTINCT case_id) as cases
FROM tax_years
UNION ALL
SELECT 
    'Gold' as layer,
    COUNT(DISTINCT case_id) as cases
FROM employment_information;
```

**Expected:** 10 cases in each layer

---

## 🎯 Success Criteria

- [ ] **Database schema exists** (5 migrations applied)
- [ ] **API key works** (TiParser returns data)
- [ ] **Services running** (Backend + Dagster)
- [ ] **1 case works end-to-end** (Bronze → Silver → Gold)
- [ ] **10 cases processed** (Batch complete)
- [ ] **PDFs downloaded** (Stored in Supabase Storage)
- [ ] **SQL triggers work** (Automatic transformation)
- [ ] **Data queryable** (Gold layer has clean data)

---

## 📊 Current Status

**Completed:**
- ✅ All code written (Bronze, Silver, Gold)
- ✅ SQL triggers created
- ✅ PDF storage implemented
- ✅ Dagster pipeline built
- ✅ FastAPI backend configured
- ✅ Documentation complete

**Remaining:**
- ⏳ Apply database migrations
- ⏳ Test TiParser API key
- ⏳ Test with 1 case
- ⏳ Process 10 cases
- ⏳ Verify all layers

---

## 🐛 Troubleshooting

### Migrations won't apply
→ Use Supabase Dashboard SQL Editor (Option B above)

### TiParser 403 error
→ API key expired, get new one from TiParser

### Dagster job fails
→ Check logs in Dagster UI → Runs → Click failed run

### No data in Silver/Gold
→ Check if triggers exist:
```sql
SELECT trigger_name, event_object_table 
FROM information_schema.triggers 
WHERE trigger_schema = 'public';
```

### Backend won't start
→ Check if dependencies installed:
```bash
pip install -r backend/requirements.txt
```

---

## ⏱️ Time Estimate

| Task | Time |
|------|------|
| Apply migrations | 30 min |
| Test API key | 5 min |
| Start services | 5 min |
| Test 1 case | 10 min |
| Process 10 cases | 30 min |
| Verify results | 20 min |
| **Total** | **~2 hours** |

---

## 📚 Reference Docs

- **GET_OPERATIONAL.md** - Detailed walkthrough
- **READY_TO_START.md** - Quick start guide
- **BACKEND_SETUP_COMPLETE.md** - Backend details
- **WALKTHROUGH.md** - Architecture overview

---

## 🚀 Quick Commands

```bash
# Apply migrations
supabase db push

# Start everything
./start_all.sh

# Test one case
curl -X POST http://localhost:8000/api/dagster/cases/1295022/extract

# Process batch
python process_batch.py

# Check health
curl http://localhost:8000/health
curl http://localhost:8000/api/dagster/health
```

---

**Start with Step 1!** ☝️

