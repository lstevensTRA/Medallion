# Medallion Architecture - Tax Resolution Data Pipeline

A production-ready Bronze → Silver → Gold medallion architecture for tax resolution data processing using Supabase and Dagster.

## 🏗️ Architecture

```
External APIs (TiParser) → Bronze (Raw JSONB) → Silver (Typed & Enriched) → Gold (Normalized Entities)
```

## 📊 Current Status

- ✅ **Bronze Layer**: Operational - Raw API responses stored
- ✅ **Silver Layer**: Operational - Automatic transformation via SQL triggers
- ✅ **Gold Layer**: Operational - Normalized business entities
- ✅ **Dagster Orchestration**: Configured for data ingestion
- ⚠️ **Known Issue**: `income_sources` table needs trigger schema fix

## 🚀 Quick Start

### Prerequisites

- Python 3.8+
- Supabase project with migrations applied
- Dagster installed
- Environment variables configured (`.env`)

### Setup

```bash
# Install dependencies
pip install -r requirements.txt  # If exists
pip install dagster supabase python-dotenv

# Set environment variables
cp .env.example .env
# Edit .env with your credentials

# Apply database migrations
# See supabase/migrations/ for migration files

# Start Dagster UI
dagster dev
```

### Running the Pipeline

```bash
# Trigger data extraction for a case
python3 trigger_case_ingestion.py <case_id>

# Or via API
curl -X POST http://localhost:8000/api/dagster/cases/<case_id>/extract
```

## 📚 Documentation

- [Complete Workflow Guide](./COMPLETE_WORKFLOW_GUIDE.md) - End-to-end pipeline walkthrough
- [Discovery Report](./docs/00_DISCOVERY_REPORT.md) - Initial codebase analysis
- [API Analysis](./docs/01_API_ANALYSIS.md) - API response structures
- [Business Rules](./docs/02_BUSINESS_RULES.md) - Rule tables and logic

## 🗂️ Project Structure

```
Medallion/
├── dagster_pipeline/          # Dagster assets, resources, schedules
│   ├── assets/                # Bronze ingestion assets
│   ├── resources/             # API resources (TiParser, Supabase)
│   └── sensors/               # Event-driven triggers
├── supabase/
│   └── migrations/            # Database migrations (Bronze, Silver, Gold)
├── backend/                   # FastAPI backend integration
├── docs/                      # Comprehensive documentation
└── scripts/                   # Utility scripts for processing
```

## 🔄 Data Flow

1. **Bronze**: Dagster assets call TiParser APIs, store raw JSONB responses
2. **Silver**: SQL triggers automatically extract and type data from Bronze
3. **Gold**: SQL triggers normalize Silver data into business entities

See [COMPLETE_WORKFLOW_GUIDE.md](./COMPLETE_WORKFLOW_GUIDE.md) for detailed workflow.

## 📝 License

Proprietary - Tax Resolution Application

