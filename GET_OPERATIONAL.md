# 🚀 Get Operational with 10 Test Cases

## Current Status: 95% Complete, Need to Deploy & Test

### ✅ What's Ready
- All code written (Bronze, Silver, Gold layers)
- SQL triggers created
- PDF storage implemented
- Dagster pipeline assets ready
- FastAPI backend configured

### ❌ What's Missing
- 🔴 **Migrations NOT applied** → Database empty
- 🔴 **TiParser API key may be expired** → Need to test
- 🟡 **Never tested end-to-end** → Unknown if it works
- 🟡 **No automation configured** → Manual triggering only

---

## 📋 Action Plan: Get Operational in 3 Hours

### **Step 1: Apply Database Migrations (30 minutes)**

Let's get your database schema in place:

```bash
cd /Users/lindseystevens/Medallion

# Apply all migrations in order
supabase db push
```

**Migrations to apply:**
1. `001_create_bronze_tables.sql` → Bronze layer (raw JSON + PDFs)
2. `002_bronze_to_silver_triggers.sql` → Automatic transformation
3. `003_silver_to_gold_triggers.sql` → Normalized business entities
4. `004_create_pdf_storage_bucket.sql` → PDF blob storage
5. `005_bronze_pdf_metadata_table.sql` → PDF metadata tracking

**If `supabase db push` fails:**

Option A - Apply via Supabase Dashboard:
1. Go to https://supabase.com/dashboard
2. Select your project
3. Go to "SQL Editor"
4. Copy/paste each migration file
5. Execute them in order (001 → 005)

Option B - Apply via Python script:
```bash
python apply_migrations.py
```

---

### **Step 2: Test TiParser API Key (5 minutes)**

```bash
# Test if your API key still works
curl -X GET https://tiparser.onrender.com/analysis/at/1295022 \
  -H "Authorization: Bearer sk_BIWGmwZeahwOyI9ytZNMnZmM_mY1SOcpl4OXlmFpJvA"
```

**Expected:**
- ✅ 200 OK → Key works!
- ❌ 403 Forbidden → Key expired, need new one

---

### **Step 3: Start Your Services (5 minutes)**

```bash
cd /Users/lindseystevens/Medallion

# Start both backend and Dagster
./start_all.sh
```

**Verify:**
- Backend: http://localhost:8000/health
- Dagster: http://localhost:3000
- API Docs: http://localhost:8000/docs

---

### **Step 4: Test with ONE Case First (10 minutes)**

Before batch processing, test with a single case:

```bash
# Trigger extraction for case 1295022
curl -X POST http://localhost:8000/api/dagster/cases/1295022/extract
```

**Expected Response:**
```json
{
  "status": "triggered",
  "case_id": "1295022",
  "message": "Data extraction started...",
  "dagster_ui": "http://localhost:3000/runs"
}
```

**Watch in Dagster UI:**
1. Open http://localhost:3000
2. Click "Runs" in left sidebar
3. You should see your job running

**Check the results:**
```bash
# Wait 2-3 minutes, then check status
curl http://localhost:8000/api/dagster/status/1295022
```

**Expected:**
```json
{
  "case_id": "1295022",
  "bronze": {
    "at": true,
    "wi": true,
    "trt": true,
    "interview": true,
    "total_records": 4
  },
  "silver": {...},
  "gold": {...},
  "status": "complete"
}
```

---

### **Step 5: Verify Data Flow (15 minutes)**

Check each layer in Supabase Dashboard:

**Bronze Layer (Raw Data):**
```sql
-- Check Bronze ingestion
SELECT bronze_id, case_id, api_source, inserted_at 
FROM bronze_at_raw 
WHERE case_id = '1295022';

SELECT bronze_id, case_id, api_source, inserted_at 
FROM bronze_wi_raw 
WHERE case_id = '1295022';

-- Check PDFs stored
SELECT * FROM bronze_pdf_raw 
WHERE case_id = '1295022';
```

**Silver Layer (Typed Data):**
```sql
-- Check automatic transformation
SELECT * FROM tax_years 
WHERE case_id = '1295022';

SELECT * FROM income_documents 
WHERE case_id = '1295022';

SELECT * FROM account_activity 
WHERE case_id = '1295022';
```

**Gold Layer (Business Entities):**
```sql
-- Check normalized data
SELECT * FROM employment_information 
WHERE case_id = '1295022';

SELECT * FROM household_information 
WHERE case_id = '1295022';

SELECT * FROM financial_accounts 
WHERE case_id = '1295022';
```

**PDFs:**
```sql
-- Check PDF metadata
SELECT 
  case_id,
  document_type,
  file_size,
  storage_path,
  downloaded_at
FROM bronze_pdf_raw
WHERE case_id = '1295022';
```

---

### **Step 6: Process Your 10 Test Cases (30 minutes)**

Once ONE case works, batch process 10:

#### Option A: Manual Trigger (Recommended for First Time)

```bash
# Create a list of your 10 test case IDs
CASE_IDS=(
  "1295022"
  "1234567"
  "2345678"
  "3456789"
  "4567890"
  "5678901"
  "6789012"
  "7890123"
  "8901234"
  "9012345"
)

# Trigger extraction for each
for case_id in "${CASE_IDS[@]}"; do
  echo "Processing case $case_id..."
  curl -X POST http://localhost:8000/api/dagster/cases/$case_id/extract
  sleep 5  # Space out requests
done
```

#### Option B: Automated via Python Script

Create `process_batch.py`:

```python
#!/usr/bin/env python3
"""
Process a batch of cases through the medallion pipeline
"""

import requests
import time
from typing import List

BACKEND_URL = "http://localhost:8000"

def process_cases(case_ids: List[str]):
    """Trigger extraction for multiple cases"""
    results = []
    
    for case_id in case_ids:
        print(f"\n🚀 Processing case {case_id}...")
        
        # Trigger extraction
        response = requests.post(
            f"{BACKEND_URL}/api/dagster/cases/{case_id}/extract"
        )
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ Triggered: {result['status']}")
            results.append(result)
        else:
            print(f"❌ Failed: {response.status_code}")
            results.append({"case_id": case_id, "status": "failed"})
        
        # Wait between requests
        time.sleep(3)
    
    return results

def check_status(case_ids: List[str]):
    """Check processing status for all cases"""
    print("\n" + "="*60)
    print("📊 BATCH STATUS REPORT")
    print("="*60)
    
    for case_id in case_ids:
        response = requests.get(
            f"{BACKEND_URL}/api/dagster/status/{case_id}"
        )
        
        if response.status_code == 200:
            status = response.json()
            print(f"\nCase {case_id}: {status['status']}")
            print(f"  Bronze: {status['bronze']['total_records']} records")
            print(f"  Silver: {status['silver']['total_records']} records")
            print(f"  Gold: {status['gold']['total_records']} records")
        else:
            print(f"\nCase {case_id}: ERROR {response.status_code}")

if __name__ == "__main__":
    # Your 10 test cases
    test_cases = [
        "1295022",
        "1234567",
        "2345678",
        "3456789",
        "4567890",
        "5678901",
        "6789012",
        "7890123",
        "8901234",
        "9012345",
    ]
    
    print("🎯 Processing batch of 10 cases...")
    results = process_cases(test_cases)
    
    print("\n⏳ Waiting 5 minutes for processing...")
    time.sleep(300)  # Wait 5 minutes
    
    check_status(test_cases)
    
    print("\n✅ Batch processing complete!")
```

**Run it:**
```bash
chmod +x process_batch.py
python process_batch.py
```

---

### **Step 7: Monitor in Dagster UI (Real-time)**

While your batch runs:

1. Open http://localhost:3000
2. Click "Runs" → See all 10 jobs
3. Click any run → See detailed logs
4. Watch Bronze → Silver → Gold flow

**What you'll see:**
- 📥 API calls to TiParser/CaseHelper
- 💾 Data inserted into Bronze tables
- ⚡ SQL triggers firing automatically
- ✅ Silver/Gold tables populated
- 📄 PDFs downloaded and stored

---

## 🤖 Automation Options (After Manual Testing Works)

Once you've verified 10 cases work, you have automation options:

### **Option 1: Trigger via API Endpoint (Current)**

**How it works:**
- Your frontend/app calls: `POST /api/dagster/cases/{id}/extract`
- Backend triggers Dagster
- Data extracted in background

**Use cases:**
- User clicks "Extract Data" button
- New case created → auto-trigger
- Manual refresh of specific case

---

### **Option 2: Automatic Sensor (When New Case Added)**

Already implemented in `dagster_pipeline/sensors/case_sensor.py`:

**How it works:**
1. Sensor checks `cases` table every 30 seconds
2. Finds cases without Bronze data
3. Automatically triggers extraction

**To enable:**
```bash
# In Dagster UI
# Go to: Sensors → case_ingestion_sensor → Enable
```

**What it does:**
- Monitors: `SELECT * FROM cases WHERE NOT EXISTS (SELECT 1 FROM bronze_at_raw WHERE case_id = cases.case_id)`
- Triggers: Extraction for any new case
- Frequency: Every 30 seconds

---

### **Option 3: Scheduled Batch Processing**

Already implemented in `dagster_pipeline/schedules/health_check_schedule.py`:

**How it works:**
- Runs daily at specified time
- Processes all pending cases
- Sends summary report

**To enable:**
```bash
# In Dagster UI
# Go to: Schedules → daily_health_check → Enable
```

---

### **Option 4: Status-Based Processing**

You can trigger based on case status:

```sql
-- Find all cases with status 'pending_extraction'
SELECT case_id FROM cases 
WHERE status = 'pending_extraction';
```

Then trigger extraction for those cases.

---

## 📊 Monitoring & Observability

### **Real-Time Monitoring**

**Dagster UI** (http://localhost:3000):
- See all running/completed jobs
- View logs for each step
- Check success/failure rates
- Monitor execution time

**FastAPI Status Endpoint**:
```bash
# Check any case
curl http://localhost:8000/api/dagster/status/{case_id}
```

**Supabase Dashboard**:
- View data in Bronze/Silver/Gold tables
- Check PDF storage usage
- Monitor database performance

---

### **Health Checks**

```bash
# Backend health
curl http://localhost:8000/health

# Dagster health
curl http://localhost:8000/api/dagster/health

# Database health
curl http://localhost:8000/config
```

---

## 🎯 Success Criteria (After Processing 10 Cases)

### ✅ Bronze Layer Success
- [ ] 10 cases in `bronze_at_raw`
- [ ] 10 cases in `bronze_wi_raw`
- [ ] 10 cases in `bronze_trt_raw`
- [ ] 10 cases in `bronze_interview_raw`
- [ ] PDFs stored in `bronze_pdf_raw`
- [ ] All raw JSON preserved

### ✅ Silver Layer Success
- [ ] Tax years extracted to `tax_years` table
- [ ] Income documents in `income_documents` table
- [ ] Account activity in `account_activity` table
- [ ] Business rules applied (WI types, AT codes)
- [ ] Data typed correctly (dates, decimals, etc.)

### ✅ Gold Layer Success
- [ ] Employment info in `employment_information` table
- [ ] Household info in `household_information` table
- [ ] Financial accounts in `financial_accounts` table
- [ ] Semantic column names (no Excel cells)
- [ ] Normalized structure

### ✅ PDF Storage Success
- [ ] All PDFs downloaded
- [ ] Metadata tracked in `bronze_pdf_raw`
- [ ] Accessible via Supabase Storage
- [ ] No duplicates (deduplication working)

---

## 🐛 Troubleshooting

### Issue: Migrations won't apply
**Solution:** Apply manually via Supabase Dashboard SQL Editor

### Issue: TiParser API key expired
**Solution:** Get new key, update `.env`, restart services

### Issue: No data in Silver/Gold
**Solution:** Check if SQL triggers exist:
```sql
SELECT trigger_name, event_object_table 
FROM information_schema.triggers 
WHERE trigger_schema = 'public';
```

### Issue: PDFs not downloading
**Solution:** Check CaseHelper credentials in `.env`

### Issue: Dagster job fails
**Solution:** Check logs in Dagster UI → Runs → Click failed run

---

## 📈 Next Steps After 10 Cases Work

1. **Scale Up**: Process 100 cases, then 1000
2. **Enable Automation**: Turn on sensor for new cases
3. **Set Up Monitoring**: Configure alerts for failures
4. **Frontend Integration**: Connect your UI to query Gold tables
5. **Business Functions**: Use Gold layer functions for calculations
6. **Reporting**: Build dashboards on clean data

---

## 🎯 Timeline Estimate

| Step | Time | What Happens |
|------|------|--------------|
| Apply migrations | 30 min | Database schema ready |
| Test API key | 5 min | Verify connectivity |
| Start services | 5 min | Backend + Dagster running |
| Test 1 case | 10 min | End-to-end validation |
| Verify data flow | 15 min | Check Bronze → Silver → Gold |
| Process 10 cases | 30 min | Batch extraction |
| Review results | 20 min | Validate all layers |
| **Total** | **~2 hours** | **Operational system** |

---

## 🚀 Ready to Start?

**Step 1: Apply Migrations**
```bash
cd /Users/lindseystevens/Medallion
supabase db push
```

**Step 2: Start Services**
```bash
./start_all.sh
```

**Step 3: Test One Case**
```bash
curl -X POST http://localhost:8000/api/dagster/cases/1295022/extract
```

---

**Let's get your 10 cases processed!** 🎉

