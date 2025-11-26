# Medallion Architecture Backend

Production-ready FastAPI backend for tax resolution data processing with Dagster orchestration.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    FastAPI Backend                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  /api/dagster/cases/{id}/extract                     │   │
│  │  /api/dagster/status/{id}                            │   │
│  │  /api/dagster/health                                 │   │
│  └──────────────────────────────────────────────────────┘   │
│                          ↓                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Dagster Trigger Service                             │   │
│  │  - Spawns Python subprocess                          │   │
│  │  - Calls trigger_case_ingestion.py                   │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                    Dagster Pipeline                         │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Bronze Assets                                       │   │
│  │  - bronze_at_data                                    │   │
│  │  - bronze_wi_data                                    │   │
│  │  - bronze_trt_data                                   │   │
│  │  - bronze_interview_data                             │   │
│  └──────────────────────────────────────────────────────┘   │
│                          ↓                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  TiParser / CaseHelper Resources                     │   │
│  │  - Calls external APIs                               │   │
│  │  - Returns raw JSON                                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                    Supabase Database                        │
│                                                             │
│  Bronze Layer (Raw JSON + PDFs)                             │
│  → bronze_at_raw, bronze_wi_raw, bronze_trt_raw            │
│                          ↓ [SQL Triggers]                   │
│  Silver Layer (Typed + Enriched)                            │
│  → tax_years, income_documents, account_activity           │
│                          ↓ [SQL Triggers]                   │
│  Gold Layer (Normalized Business Entities)                  │
│  → employment_information, household_information           │
└─────────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
backend/
├── app/
│   ├── __init__.py
│   ├── config.py              # Settings and configuration
│   ├── database.py            # Supabase client
│   ├── routers/
│   │   ├── __init__.py
│   │   └── dagster_extraction.py   # API endpoints
│   └── services/
│       ├── __init__.py
│       ├── bronze_storage.py       # Bronze layer storage
│       ├── dagster_trigger.py      # Dagster job trigger
│       └── pdf_storage.py          # PDF blob storage
├── main.py                    # FastAPI application
├── requirements.txt           # Python dependencies
└── README.md                  # This file
```

---

## 🚀 Quick Start

### 1. Install Dependencies

```bash
cd /Users/lindseystevens/Medallion/backend
pip install -r requirements.txt
```

### 2. Set Environment Variables

Make sure your `.env` file is at the project root:

```bash
# Check .env exists
ls /Users/lindseystevens/Medallion/.env

# Required variables:
# SUPABASE_URL
# SUPABASE_SERVICE_ROLE_KEY
# TIPARSER_URL
# TIPARSER_API_KEY
# CASEHELPER_API_URL
# CASEHELPER_USERNAME
# CASEHELPER_PASSWORD
```

### 3. Start the Backend

```bash
cd /Users/lindseystevens/Medallion/backend
python main.py
```

Or with uvicorn directly:

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

**Access:**
- API: http://localhost:8000
- Docs: http://localhost:8000/docs
- Health: http://localhost:8000/health

---

## 📡 API Endpoints

### Trigger Data Extraction

```bash
POST /api/dagster/cases/{case_id}/extract
```

**Example:**
```bash
curl -X POST http://localhost:8000/api/dagster/cases/1295022/extract
```

**Response:**
```json
{
  "status": "triggered",
  "case_id": "1295022",
  "case_number": "CASE-1295022",
  "message": "Data extraction started...",
  "dagster_ui": "http://localhost:3000/runs",
  "process_id": 12345,
  "timestamp": "2025-11-24T10:00:00"
}
```

---

### Check Status

```bash
GET /api/dagster/status/{case_id}
```

**Example:**
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

### Health Check

```bash
GET /api/dagster/health
```

**Response:**
```json
{
  "status": "healthy",
  "dagster_ui": "http://localhost:3000",
  "message": "Dagster is running and accessible"
}
```

---

## 🔧 Configuration

All configuration is managed through environment variables and `app/config.py`.

### Key Settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `HOST` | `0.0.0.0` | Server host |
| `PORT` | `8000` | Server port |
| `ENVIRONMENT` | `development` | Environment name |
| `LOG_LEVEL` | `INFO` | Logging level |
| `SUPABASE_URL` | Required | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Required | Service role key |
| `TIPARSER_URL` | Required | TiParser API URL |
| `TIPARSER_API_KEY` | Required | TiParser API key |

---

## 🧪 Testing

### Test Database Connection

```bash
curl http://localhost:8000/health
```

### Test Configuration

```bash
curl http://localhost:8000/config
```

### Test Dagster Integration

```bash
# Start Dagster first
cd /Users/lindseystevens/Medallion
dagster dev -m dagster_pipeline

# Then test
curl -X POST http://localhost:8000/api/dagster/cases/1295022/extract
```

---

## 📊 Monitoring

### FastAPI Logs

The backend logs all requests and errors to console with structured logging:

```
2025-11-24 10:00:00 - INFO - 🚀 Starting Medallion Architecture API
2025-11-24 10:00:01 - INFO - ✅ Configuration validated successfully
2025-11-24 10:00:02 - INFO - ✅ Database connection successful
2025-11-24 10:00:03 - INFO - 📡 API Server: http://0.0.0.0:8000
```

### Dagster UI

Monitor pipeline execution in Dagster UI:
- http://localhost:3000

---

## 🐛 Troubleshooting

### "Database connection failed"

Check your Supabase credentials:
```bash
echo $SUPABASE_URL
echo $SUPABASE_SERVICE_ROLE_KEY
```

### "Dagster unreachable"

Make sure Dagster is running:
```bash
cd /Users/lindseystevens/Medallion
dagster dev -m dagster_pipeline
```

### "TiParser API error"

Check your API key:
```bash
echo $TIPARSER_API_KEY
```

---

## 🚀 Deployment

### Development

```bash
python main.py
```

### Production

```bash
# Using Gunicorn
gunicorn main:app -w 4 -k uvicorn.workers.UvicornWorker

# Using Uvicorn with multiple workers
uvicorn main:app --workers 4 --host 0.0.0.0 --port 8000
```

---

## 📚 Related Documentation

- **`/Users/lindseystevens/Medallion/WALKTHROUGH.md`** - Complete architecture guide
- **`/Users/lindseystevens/Medallion/HYBRID_ARCHITECTURE_GUIDE.md`** - API integration guide
- **`/Users/lindseystevens/Medallion/docs/`** - Full implementation docs

---

## ✅ Features

- ✅ **RESTful API** - Clean, documented endpoints
- ✅ **Async Operations** - Non-blocking data extraction
- ✅ **Configuration Validation** - Startup checks
- ✅ **Database Health Checks** - Connection monitoring
- ✅ **Structured Logging** - Easy debugging
- ✅ **CORS Enabled** - Frontend integration ready
- ✅ **Auto-reload** - Development mode
- ✅ **OpenAPI Docs** - Interactive API explorer

---

**Need help?** Check the docs or ask! 🚀

