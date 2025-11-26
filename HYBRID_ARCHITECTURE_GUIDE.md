# 🏗️ Hybrid Architecture Integration Guide

## Overview

This guide shows you how to integrate FastAPI (your existing backend) with Dagster (new orchestration layer) for the medallion architecture.

---

## 📁 What We've Built

### New Files Created:

1. **`backend/app/services/dagster_trigger.py`** - Service to trigger Dagster from FastAPI
2. **`backend/app/routers/dagster_extraction.py`** - New API endpoints for extraction
3. **`trigger_case_ingestion.py`** - Script that Dagster runs
4. **`dagster_pipeline/`** - Complete Dagster orchestration setup

---

## 🔌 Step-by-Step Integration

### Step 1: Add Router to FastAPI Main App

Edit your main FastAPI file to include the new Dagster router:

**File:** `backend/app/main.py` (or wherever your FastAPI app is)

```python
from fastapi import FastAPI
from app.routers import dagster_extraction  # ← Add this import

app = FastAPI(title="Tax Resolution API")

# ... existing routers ...
# app.include_router(cases.router)
# app.include_router(extraction.router)

# Add Dagster router
app.include_router(dagster_extraction.router)  # ← Add this line

```

**That's it!** The integration is complete.

---

## 🚀 How to Use

### Option A: Async Mode (Recommended)

**Trigger extraction and return immediately:**

```bash
# Using curl
curl -X POST http://localhost:8000/api/dagster/cases/1295022/extract

# Or with full request body
curl -X POST http://localhost:8000/api/dagster/extract \
  -H "Content-Type: application/json" \
  -d '{
    "case_id": "1295022",
    "case_number": "CASE-1295022",
    "async_mode": true
  }'
```

**Response (immediate):**
```json
{
  "status": "triggered",
  "case_id": "1295022",
  "case_number": "CASE-1295022",
  "message": "Data extraction started for case CASE-1295022. Check Dagster UI for progress.",
  "dagster_ui": "http://localhost:3000/runs",
  "process_id": 12345,
  "timestamp": "2025-11-24T10:00:00"
}
```

**Then monitor progress:**
- Open http://localhost:3000 (Dagster UI)
- Or check status: `GET /api/dagster/status/1295022`

---

### Option B: Sync Mode (Wait for Completion)

**Trigger and wait:**

```bash
curl -X POST "http://localhost:8000/api/dagster/cases/1295022/extract?async_mode=false"
```

**Response (after completion):**
```json
{
  "status": "completed",
  "case_id": "1295022",
  "case_number": "CASE-1295022",
  "message": "Data extraction completed for case CASE-1295022",
  "timestamp": "2025-11-24T10:05:00"
}
```

⚠️ **Warning:** This blocks the API until extraction completes (can take minutes).

---

## 📊 Check Extraction Status

**See what data exists for a case:**

```bash
curl http://localhost:8000/api/dagster/status/1295022
```

**Response:**
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
  "silver": {
    "tax_years": 5,
    "income_documents": 12,
    "total_records": 17
  },
  "gold": {
    "employment": 2,
    "household": 1,
    "total_records": 3
  },
  "status": "complete",
  "message": "Data fully processed and ready to use."
}
```

---

## 🎨 Frontend Integration

### React/TypeScript Example

```typescript
// services/extractionService.ts
export const triggerExtraction = async (caseId: string) => {
  const response = await fetch(`/api/dagster/cases/${caseId}/extract`, {
    method: 'POST'
  });
  
  if (!response.ok) {
    throw new Error('Failed to trigger extraction');
  }
  
  return await response.json();
};

export const checkExtractionStatus = async (caseId: string) => {
  const response = await fetch(`/api/dagster/status/${caseId}`);
  return await response.json();
};

// In your component
const handleExtractData = async () => {
  try {
    const result = await triggerExtraction(caseId);
    
    toast.success('Data extraction started!');
    toast.info('Check the Dagster UI for progress', {
      action: {
        label: 'Open Dagster',
        onClick: () => window.open(result.dagster_ui, '_blank')
      }
    });
    
    // Poll for status updates
    const interval = setInterval(async () => {
      const status = await checkExtractionStatus(caseId);
      
      if (status.status === 'complete') {
        clearInterval(interval);
        toast.success('Data extraction completed!');
        refetchData(); // Refresh your data grid
      }
    }, 5000); // Check every 5 seconds
    
  } catch (error) {
    toast.error('Failed to start extraction');
  }
};
```

---

## 🔄 Data Flow

Here's what happens when you trigger extraction:

```
1. User clicks "Extract Data" in React frontend
   ↓
2. Frontend calls: POST /api/dagster/cases/1295022/extract
   ↓
3. FastAPI receives request
   ↓
4. FastAPI triggers Dagster (via dagster_trigger.py)
   ↓
5. FastAPI returns "triggered" response immediately
   ↓
6. Dagster runs Bronze ingestion assets:
   - bronze_at_data (calls TiParser for AT)
   - bronze_wi_data (calls TiParser for WI)
   - bronze_trt_data (calls TiParser for TRT)
   - bronze_interview_data (calls CaseHelper)
   ↓
7. Raw data stored in Bronze tables
   ↓
8. SQL triggers automatically fire:
   - Bronze → Silver transformations
   - Silver → Gold transformations
   ↓
9. Data ready in Gold tables
   ↓
10. Frontend polls /api/dagster/status/1295022
   ↓
11. Shows "complete" status
   ↓
12. Frontend refreshes data grid
```

---

## 🏃 Quick Test

### 1. Start Dagster

```bash
cd /Users/lindseystevens/Medallion
dagster dev -m dagster_pipeline
```

Dagster UI: http://localhost:3000

### 2. Start FastAPI

```bash
cd /Users/lindseystevens/Medallion/backend
uvicorn app.main:app --reload
```

FastAPI: http://localhost:8000

### 3. Test the Integration

```bash
# Health check
curl http://localhost:8000/api/dagster/health

# Trigger extraction
curl -X POST http://localhost:8000/api/dagster/cases/1295022/extract

# Check status
curl http://localhost:8000/api/dagster/status/1295022
```

### 4. Monitor in Dagster UI

Open http://localhost:3000 and watch the pipeline run!

---

## 🎯 Benefits of This Approach

### ✅ **For Users**
- Fast API responses (no waiting)
- Clear progress tracking
- Can monitor multiple extractions

### ✅ **For Developers**
- Separation of concerns (web vs data)
- Better error handling & retries
- Data lineage visibility
- Easy to add new data sources

### ✅ **For Operations**
- Centralized monitoring (Dagster UI)
- Automatic retries on failures
- Scalable (can run on separate servers)
- Scheduled jobs & sensors

---

## 🔧 Configuration

### Environment Variables

Make sure these are set in your `.env`:

```bash
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-key

# TiParser
TIPARSER_URL=https://tiparser.onrender.com
TIPARSER_API_KEY=your-key

# CaseHelper
CASEHELPER_API_URL=https://casehelper-backend.onrender.com
CASEHELPER_USERNAME=your-username
CASEHELPER_PASSWORD=your-password
CASEHELPER_APP_TYPE=transcript_pipeline

# Dagster
DAGSTER_HOME=/Users/lindseystevens/Medallion/dagster_home
```

---

## 📋 API Endpoints Reference

| Endpoint | Method | Description | Response Time |
|----------|--------|-------------|---------------|
| `/api/dagster/extract` | POST | Trigger extraction (async) | Immediate |
| `/api/dagster/cases/{id}/extract` | POST | Trigger extraction by ID | Immediate |
| `/api/dagster/status/{id}` | GET | Check extraction status | Fast |
| `/api/dagster/health` | GET | Check Dagster health | Fast |
| `/api/dagster/ui` | GET | Redirect to Dagster UI | Immediate |

---

## 🐛 Troubleshooting

### "Dagster is unreachable"

**Problem:** FastAPI can't connect to Dagster

**Solution:**
```bash
# Make sure Dagster is running
dagster dev -m dagster_pipeline

# Check if it's accessible
curl http://localhost:3000
```

### "Trigger script not found"

**Problem:** Can't find `trigger_case_ingestion.py`

**Solution:**
```bash
# Make sure script exists
ls -la /Users/lindseystevens/Medallion/trigger_case_ingestion.py

# Make it executable
chmod +x /Users/lindseystevens/Medallion/trigger_case_ingestion.py
```

### "TiParser API Key Invalid"

**Problem:** 403 Forbidden from TiParser

**Solution:**
```bash
# Update your API key in .env
TIPARSER_API_KEY=your-new-key

# Restart Dagster to pick up new env vars
```

---

## 🚀 Next Steps

1. ✅ **Test the integration** with a real case
2. ✅ **Update your frontend** to use new endpoints
3. ✅ **Set up monitoring** in Dagster UI
4. ✅ **Add scheduled jobs** (optional)
5. ✅ **Deploy to production** (Dagster Cloud)

---

## 📚 Additional Resources

- **Dagster UI:** http://localhost:3000
- **FastAPI Docs:** http://localhost:8000/docs
- **Dagster Docs:** https://docs.dagster.io
- **Your Project Docs:** See `docs/` folder

---

**Questions?** Check the `dagster_pipeline/README.md` for more details!

