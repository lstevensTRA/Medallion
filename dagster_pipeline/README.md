# Tax Resolution Medallion - Dagster Pipeline

This Dagster pipeline orchestrates the Bronze → Silver → Gold medallion architecture for tax resolution data processing.

## Architecture Overview

```
APIs (TiParser, CaseHelper)
    ↓
DAGSTER ASSETS (Bronze Ingestion)
├─ bronze_at_data
├─ bronze_wi_data
├─ bronze_trt_data
└─ bronze_interview_data
    ↓
BRONZE TABLES (Raw JSON)
├─ bronze_at_raw
├─ bronze_wi_raw
├─ bronze_trt_raw
└─ bronze_interview_raw
    ↓
SQL TRIGGERS (Automatic)
    ↓
SILVER TABLES (Typed, Enriched)
├─ account_activity
├─ income_documents
├─ trt_records
└─ logiqs_raw_data
    ↓
SQL TRIGGERS (Automatic)
    ↓
GOLD TABLES (Semantic, Normalized)
├─ employment_information
├─ household_information
└─ BUSINESS FUNCTIONS
    ├─ calculate_total_monthly_income()
    ├─ calculate_se_tax()
    ├─ calculate_account_balance()
    ├─ calculate_csed_date()
    ├─ calculate_disposable_income()
    └─ get_case_summary()
```

**Dagster's Role:**
- Call APIs and insert into Bronze
- Monitor that SQL triggers work correctly
- Provide data lineage visualization
- Alert on processing failures
- Schedule automated runs

**SQL Triggers' Role:**
- Transform Bronze → Silver → Gold automatically
- Apply business rules
- Handle field variations
- Maintain data quality

---

## Quick Start

### 1. Install Dependencies

```bash
cd /Users/lindseystevens/Medallion

# Install Dagster and dependencies
pip install -e ".[dev]"
```

### 2. Configure Environment

```bash
# Copy example env file
cp .env.example .env

# Edit .env with your credentials
nano .env
```

Required environment variables:
- `SUPABASE_URL` - Your Supabase project URL
- `SUPABASE_KEY` - Service role key
- `TIPARSER_URL` - TiParser API URL
- `TIPARSER_API_KEY` - TiParser API key
- `CASEHELPER_BASE_URL` - CaseHelper API URL
- `CASEHELPER_USERNAME` - CaseHelper username
- `CASEHELPER_PASSWORD` - CaseHelper password

### 3. Start Dagster Dev Server

```bash
dagster dev -m dagster_pipeline
```

Open browser to: **http://localhost:3000**

---

## Assets

### Bronze Ingestion Assets

#### `bronze_at_data`
- **Purpose:** Fetch Account Transcript data from TiParser
- **API:** `TiParser /analysis/at/{case_id}`
- **Bronze Table:** `bronze_at_raw`
- **Triggers:** Automatically populates `account_activity`, `tax_years`, `csed_tolling_events`

**Usage:**
```python
# Config
{
  "ops": {
    "bronze_at_data": {
      "config": {
        "case_id": "uuid-here",
        "case_number": "CASE-001"
      }
    }
  }
}
```

#### `bronze_wi_data`
- **Purpose:** Fetch Wage & Income data from TiParser
- **API:** `TiParser /analysis/wi/{case_id}`
- **Bronze Table:** `bronze_wi_raw`
- **Triggers:** Automatically populates `income_documents` (with `wi_type_rules` enrichment)

#### `bronze_trt_data`
- **Purpose:** Fetch Tax Return Transcript data from TiParser
- **API:** `TiParser /analysis/trt/{case_id}`
- **Bronze Table:** `bronze_trt_raw`
- **Triggers:** Automatically populates `trt_records`

#### `bronze_interview_data`
- **Purpose:** Fetch Interview data from CaseHelper
- **API:** `CaseHelper /api/cases/{case_id}/interview`
- **Bronze Table:** `bronze_interview_raw`
- **Triggers:** Automatically populates `logiqs_raw_data` → `employment_information`, `household_information`

### Monitoring Assets

#### `monitor_bronze_silver_health`
- **Purpose:** Check Bronze → Silver trigger health
- **Checks:**
  - Bronze records processed
  - Silver records created
  - Failed records (alerts if found)
- **View:** `bronze_silver_health`

#### `monitor_silver_gold_health`
- **Purpose:** Check Silver → Gold trigger health
- **Checks:**
  - Silver data populating Gold tables
  - Employment and household entities created
- **View:** `silver_gold_health`

#### `monitor_business_functions`
- **Purpose:** Validate Gold business functions
- **Tests:**
  - `calculate_total_monthly_income()`
  - `calculate_disposable_income()`
  - `get_case_summary()`

---

## Resources

### `SupabaseResource`
Wraps your existing Supabase client from `backend/app/database.py`

**Methods:**
- `get_client()` - Get authenticated Supabase client
- `health_check()` - Check connection

### `TiParserResource`
Wraps your existing TiParser client logic from `backend/app/services/transcript_pipeline.py`

**Methods:**
- `get_at_analysis(case_id)` - Get AT data
- `get_wi_analysis(case_id)` - Get WI data
- `get_trt_analysis(case_id)` - Get TRT data
- `health_check()` - Check API

### `CaseHelperResource`
Wraps your existing CaseHelper client from `backend/app/services/interview_fetcher.py`

**Methods:**
- `get_interview(case_id)` - Get interview data
- `health_check()` - Check API and auth

---

## Sensors

### `new_case_sensor`
Monitors for new cases and automatically triggers Bronze ingestion.

**Runs:** Every 60 seconds  
**Triggers:** All Bronze ingestion assets for new cases

---

## Schedules

### `daily_health_check`
Runs daily health checks on the data pipeline.

**Schedule:** 8:00 AM every day  
**Runs:** All monitoring assets

---

## Local Development

### Run Dagster Dev Server

```bash
dagster dev -m dagster_pipeline
```

### Materialize Single Asset

```bash
dagster asset materialize -m dagster_pipeline --select bronze_at_data
```

### Materialize All Assets

```bash
dagster asset materialize -m dagster_pipeline --select "*"
```

### Run with Config

```bash
dagster asset materialize -m dagster_pipeline \
  --select bronze_at_data \
  --config-json '{"ops": {"bronze_at_data": {"config": {"case_id": "uuid", "case_number": "CASE-001"}}}}'
```

---

## Dagster Cloud Deployment

### 1. Install Dagster Cloud CLI

```bash
pip install dagster-cloud
```

### 2. Authenticate

```bash
dagster-cloud auth login
```

### 3. Deploy

```bash
dagster-cloud deployment deploy \
  --deployment-name prod \
  --location-name tax_resolution_medallion \
  --code-location-file dagster_cloud.yaml
```

### 4. Set Environment Variables in Dagster Cloud UI

Go to: **Deployment Settings → Environment Variables**

Add:
- `SUPABASE_URL`
- `SUPABASE_KEY` (mark as secret)
- `TIPARSER_URL`
- `TIPARSER_API_KEY` (mark as secret)
- `CASEHELPER_BASE_URL`
- `CASEHELPER_USERNAME`
- `CASEHELPER_PASSWORD` (mark as secret)
- `CASEHELPER_APP_TYPE`

### 5. Monitor in Dagster Cloud UI

- View asset graph
- Monitor runs
- View logs
- Set up alerts

---

## Testing

### Test Bronze Ingestion

```python
# Test AT ingestion
from dagster import materialize
from dagster_pipeline.assets.bronze_assets import bronze_at_data

result = materialize(
    [bronze_at_data],
    run_config={
        "ops": {
            "bronze_at_data": {
                "config": {
                    "case_id": "test-uuid",
                    "case_number": "TEST-001"
                }
            }
        }
    }
)

assert result.success
```

### Test Monitoring

```python
from dagster_pipeline.assets.monitoring_assets import monitor_bronze_silver_health

result = materialize([monitor_bronze_silver_health])
assert result.success
```

---

## Troubleshooting

### Issue: Assets not showing in UI

**Solution:**
```bash
# Reload definitions
dagster dev -m dagster_pipeline
```

### Issue: Resource configuration error

**Solution:**
Check `.env` file has all required variables:
```bash
cat .env | grep SUPABASE_URL
cat .env | grep TIPARSER_URL
```

### Issue: SQL trigger not firing

**Solution:**
1. Check Supabase migrations applied: `supabase db diff`
2. Verify triggers exist: Query `information_schema.triggers`
3. Check Bronze record processing_status

### Issue: API authentication failing

**Solution:**
1. Verify API keys in `.env`
2. Test resource health_check():
```python
from dagster_pipeline.resources.tiparser_resource import TiParserResource

tiparser = TiParserResource(
    tiparser_url="...",
    tiparser_api_key="..."
)
print(tiparser.health_check())  # Should be True
```

---

## Data Lineage

Dagster provides automatic data lineage visualization:

```
bronze_at_data
    ↓ (triggers bronze_at_raw INSERT)
    ↓ (SQL trigger fires automatically)
account_activity, tax_years, csed_tolling_events
    ↓
monitor_bronze_silver_health
    ↓
monitor_silver_gold_health
    ↓
monitor_business_functions
```

View in Dagster UI: **Asset Graph** tab

---

## Performance

### Bronze Ingestion
- AT: ~2-5 seconds (API call + Bronze insert)
- WI: ~2-5 seconds
- TRT: ~2-5 seconds
- Interview: ~1-3 seconds

### Trigger Processing
- Bronze → Silver: ~100-500ms per record
- Silver → Gold: ~50-100ms per record

### Total Pipeline
- End-to-end (API → Gold): ~5-10 seconds per case

---

## Next Steps

1. **Apply Supabase Migrations:**
   ```bash
   supabase db push
   ```

2. **Test Locally:**
   ```bash
   dagster dev -m dagster_pipeline
   ```

3. **Deploy to Dagster Cloud:**
   ```bash
   dagster-cloud deployment deploy
   ```

4. **Monitor in Production:**
   - Set up alerts
   - Monitor asset runs
   - Check data quality

---

## Support

For issues or questions:
1. Check logs in Dagster UI
2. Review Phase 6 documentation: `docs/06_DAGSTER_ORCHESTRATION.md`
3. Check Supabase trigger status: `SELECT * FROM bronze_silver_health`

---

**Happy Orchestrating!** 🚀

