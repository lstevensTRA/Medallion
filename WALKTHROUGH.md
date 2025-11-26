# 🎯 Hybrid Architecture Walkthrough

## What You Have Now

A complete **FastAPI + Dagster** hybrid architecture for tax resolution data processing!

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER LAYER                               │
│                                                                  │
│  ┌─────────────┐                                                │
│  │   React     │                                                │
│  │  Frontend   │                                                │
│  └──────┬──────┘                                                │
│         │ HTTP Requests                                         │
└─────────┼──────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                       FASTAPI BACKEND                            │
│                    (Your Existing App)                           │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ NEW: /api/dagster/extract                                 │ │
│  │      Triggers → dagster_trigger.py                        │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ Existing: /api/cases, /api/calculations, etc.            │ │
│  │           User auth, CRUD operations                      │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                  │
└──────────────────────────┬───────────────────────────────────────┘
                           │ Triggers Python script
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      DAGSTER ORCHESTRATION                       │
│                    (New Data Pipeline Layer)                     │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Bronze Assets (Data Ingestion)                         │   │
│  │  • bronze_at_data    → TiParser AT API                 │   │
│  │  • bronze_wi_data    → TiParser WI API                 │   │
│  │  • bronze_trt_data   → TiParser TRT API                │   │
│  │  • bronze_interview  → CaseHelper API                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                      │
│                           │ Stores raw JSON                      │
│                           ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Monitoring Assets                                       │   │
│  │  • monitor_bronze_silver_health                         │   │
│  │  • monitor_silver_gold_health                           │   │
│  │  • monitor_business_functions                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└──────────────────────────┬───────────────────────────────────────┘
                           │ Writes to database
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      SUPABASE DATABASE                           │
│                    (Medallion Architecture)                      │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  BRONZE LAYER (Raw Data)                                │   │
│  │  • bronze_at_raw         (JSON from TiParser)          │   │
│  │  • bronze_wi_raw         (JSON from TiParser)          │   │
│  │  • bronze_trt_raw        (JSON from TiParser)          │   │
│  │  • bronze_interview_raw  (JSON from CaseHelper)        │   │
│  │  • bronze_pdf_raw        (PDF metadata)                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                      │
│                           │ SQL Triggers fire automatically       │
│                           ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  SILVER LAYER (Typed & Enriched)                        │   │
│  │  • tax_years             (extracted & typed)           │   │
│  │  • income_documents      (with wi_type_rules)          │   │
│  │  • account_activity      (with at_transaction_rules)   │   │
│  │  • csed_tolling_events   (calculated dates)            │   │
│  │  • logiqs_raw_data       (structured interview data)   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                      │
│                           │ SQL Triggers fire automatically       │
│                           ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  GOLD LAYER (Normalized & Semantic)                     │   │
│  │  • employment_information  (semantic columns)          │   │
│  │  • household_information   (semantic columns)          │   │
│  │  • financial_accounts      (semantic columns)          │   │
│  │  • tax_projections         (business logic)            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Complete Data Flow Example

### User clicks "Extract Data" for case 1295022

```
1. Frontend (React)
   ↓
   POST /api/dagster/cases/1295022/extract

2. FastAPI Receives Request
   ↓
   • dagster_extraction.py router handles it
   • Calls dagster_trigger.py service
   • Returns immediately: {"status": "triggered"}

3. User sees: "✅ Extraction started! Check Dagster UI"

4. Meanwhile, Dagster runs in background:
   ↓
   a) bronze_at_data asset executes
      - Calls TiParser: GET https://tiparser.onrender.com/analysis/at/1295022
      - Gets JSON response with account transcript data
      - Inserts into bronze_at_raw table
      - SQL trigger fires → populates tax_years, account_activity
   
   b) bronze_wi_data asset executes
      - Calls TiParser: GET https://tiparser.onrender.com/analysis/wi/1295022
      - Gets JSON response with wage/income data
      - Inserts into bronze_wi_raw table
      - SQL trigger fires → populates income_documents
   
   c) bronze_trt_data asset executes
      - Calls TiParser: GET https://tiparser.onrender.com/analysis/trt/1295022
      - Gets JSON response with tax return data
      - Inserts into bronze_trt_raw table
      - SQL trigger fires → populates trt_records
   
   d) bronze_interview_data asset executes
      - Calls CaseHelper: GET https://casehelper-backend.onrender.com/api/cases/1295022/interview
      - Gets JSON response with interview data
      - Inserts into bronze_interview_raw table
      - SQL trigger fires → populates logiqs_raw_data
      - Another trigger fires → populates employment_information, household_information

5. All Silver → Gold triggers complete automatically

6. User polls: GET /api/dagster/status/1295022
   ↓
   Response: {
     "status": "complete",
     "bronze": {"at": true, "wi": true, "trt": true, "interview": true},
     "silver": {"tax_years": 5, "income_documents": 12},
     "gold": {"employment": 2, "household": 1}
   }

7. Frontend refreshes data grid
   ↓
   Shows all the extracted tax data!
```

---

## 📂 File Structure

```
/Users/lindseystevens/Medallion/
│
├── backend/                           # FastAPI Backend
│   └── app/
│       ├── main.py                    # FastAPI app (add router here!)
│       ├── routers/
│       │   ├── dagster_extraction.py  # ✨ NEW: Dagster endpoints
│       │   ├── extraction.py          # Old extraction (can keep or remove)
│       │   └── cases.py               # Existing endpoints
│       └── services/
│           ├── dagster_trigger.py     # ✨ NEW: Triggers Dagster
│           └── data_saver.py          # Old parsing logic (now in SQL triggers)
│
├── dagster_pipeline/                  # ✨ NEW: Dagster Orchestration
│   ├── __init__.py                    # Dagster definitions
│   ├── assets/
│   │   ├── bronze_assets.py           # 4 Bronze ingestion assets
│   │   └── monitoring_assets.py       # 3 Monitoring assets
│   ├── resources/
│   │   ├── supabase_resource.py       # Supabase connection
│   │   ├── tiparser_resource.py       # TiParser API client
│   │   └── casehelper_resource.py     # CaseHelper API client
│   ├── sensors/
│   │   └── case_sensor.py             # Auto-trigger on new cases
│   └── schedules/
│       └── health_check_schedule.py   # Daily health checks
│
├── supabase/migrations/               # Database Schema
│   ├── 001_create_bronze_tables.sql   # Bronze layer
│   ├── 002_bronze_to_silver_triggers.sql  # Bronze → Silver transforms
│   ├── 003_silver_to_gold_triggers.sql    # Silver → Gold transforms
│   ├── 004_create_pdf_storage_bucket.sql  # PDF storage setup
│   └── 005_bronze_pdf_metadata_table.sql  # PDF metadata
│
├── trigger_case_ingestion.py          # ✨ Script FastAPI calls
├── test_hybrid_integration.sh         # ✨ Test script
├── HYBRID_ARCHITECTURE_GUIDE.md       # ✨ This guide
└── .env                               # Config (API keys, etc.)
```

---

## 🚀 How to Use It

### Step 1: Start Both Services

**Terminal 1 - Start Dagster:**
```bash
cd /Users/lindseystevens/Medallion
export DAGSTER_HOME=/Users/lindseystevens/Medallion/dagster_home
dagster dev -m dagster_pipeline
```
→ Opens at http://localhost:3000

**Terminal 2 - Start FastAPI:**
```bash
cd /Users/lindseystevens/Medallion/backend
uvicorn app.main:app --reload
```
→ Opens at http://localhost:8000

### Step 2: Add Router to FastAPI

Edit `backend/app/main.py`:
```python
from app.routers import dagster_extraction

app.include_router(dagster_extraction.router)
```

Restart FastAPI.

### Step 3: Test It!

**Option A: Using the test script:**
```bash
./test_hybrid_integration.sh
```

**Option B: Manual test:**
```bash
# Trigger extraction
curl -X POST http://localhost:8000/api/dagster/cases/1295022/extract

# Check status
curl http://localhost:8000/api/dagster/status/1295022

# Watch in Dagster UI
open http://localhost:3000
```

---

## 🎨 Update Your Frontend

### Before (Old Way):
```typescript
// Called old extraction endpoint
POST /api/extraction/trigger/1295022
// Waited for response (slow, could timeout)
```

### After (New Way):
```typescript
// Call new Dagster endpoint
const response = await fetch('/api/dagster/cases/1295022/extract', {
  method: 'POST'
});

// Returns immediately!
toast.success('Extraction started!');

// Poll for updates
setInterval(async () => {
  const status = await fetch(`/api/dagster/status/1295022`);
  const data = await status.json();
  
  if (data.status === 'complete') {
    toast.success('Data ready!');
    refreshGrid();
  }
}, 5000);
```

---

## ✅ What You Get

### 1. **Better User Experience**
- No more waiting for long API calls
- Clear progress indicators
- Can monitor multiple cases at once

### 2. **Better Developer Experience**
- Dagster UI shows exactly what's happening
- Easy to debug failed extractions
- Data lineage is visible

### 3. **Better Operations**
- Automatic retries on failure
- Monitoring & alerting built-in
- Can schedule regular refreshes
- Scalable (move Dagster to separate server)

### 4. **Better Data Quality**
- Raw data preserved in Bronze (audit trail)
- Transformations are reproducible
- Can re-run if business logic changes

---

## 🐛 Troubleshooting

### "Cannot reach Dagster"
```bash
# Make sure it's running
curl http://localhost:3000

# If not, start it
dagster dev -m dagster_pipeline
```

### "404 on /api/dagster/extract"
```bash
# Did you add the router to main.py?
# Check backend/app/main.py includes:
app.include_router(dagster_extraction.router)
```

### "TiParser 403 Forbidden"
```bash
# API key invalid/expired
# Update TIPARSER_API_KEY in .env
# Restart Dagster
```

---

## 📊 Monitoring & Observability

### Dagster UI (http://localhost:3000)
- See all runs (past and current)
- View asset lineage
- Check logs for each step
- See which assets succeeded/failed

### FastAPI Logs
```bash
# See API requests
tail -f backend/logs/app.log
```

### Database Queries
```sql
-- Check what was extracted
SELECT * FROM bronze_at_raw WHERE case_id = '1295022';
SELECT * FROM tax_years WHERE case_id = '1295022';
SELECT * FROM employment_information WHERE case_id = '1295022';

-- Monitor health
SELECT * FROM bronze_silver_health;
SELECT * FROM silver_gold_health;
```

---

## 🎯 Next Steps

1. ✅ **Test with your TiParser API key** (once renewed)
2. ✅ **Update your React frontend** to use new endpoints
3. ✅ **Remove old extraction logic** from FastAPI (optional)
4. ✅ **Set up scheduled jobs** for regular refreshes
5. ✅ **Deploy to production** (Dagster Cloud + your FastAPI host)

---

## 🙋 Questions?

- **How does FastAPI trigger Dagster?**  
  Via Python subprocess running `trigger_case_ingestion.py`

- **Can I still use the old extraction endpoint?**  
  Yes! Keep it until you're confident in the new flow

- **Do I need two servers?**  
  Locally: Yes (FastAPI + Dagster)  
  Production: Optional (can run on same server)

- **What if Dagster crashes?**  
  FastAPI still works! Users just can't trigger new extractions

---

## 📚 Reference Documents

- **`HYBRID_ARCHITECTURE_GUIDE.md`** - Complete API reference
- **`dagster_pipeline/README.md`** - Dagster setup details
- **`docs/06_DAGSTER_ORCHESTRATION.md`** - Orchestration design
- **`docs/PDF_STORAGE_IMPLEMENTATION.md`** - PDF blob storage

---

**🎉 You now have a production-ready hybrid architecture!**

