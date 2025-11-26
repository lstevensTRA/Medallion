# Phase 0: Discovery Report

**Date:** November 14, 2024  
**Project:** Tax Resolution Medallion Architecture  
**Status:** ✅ Complete

---

## Executive Summary

This discovery phase analyzed the existing Tax Resolution data processing system to determine how to integrate a Bronze → Silver → Gold medallion architecture using Supabase and Dagster. The system currently processes tax transcripts (Account Transcripts, Wage & Income, Tax Return Transcripts) and interview data through external APIs and stores them in a Supabase database.

**Key Finding:** The existing system already has elements of a medallion architecture but needs formalization and enhancement to achieve true data maturity.

---

## 1. Tech Stack Analysis

### Backend Framework
**Framework:** FastAPI (Python)  
**Version:** 0.109.0  
**Location:** `/ExistingDocs/TI Revamp 1.0/backend/`

**Key Dependencies:**
```python
fastapi==0.109.0
uvicorn[standard]==0.27.0
supabase==2.3.4
pydantic==2.5.3
pydantic-settings==2.1.0
python-dotenv==1.0.0
httpx==0.26.0
python-multipart==0.0.6
```

**Database Client:** Supabase Python SDK (`supabase==2.3.4`)  
**HTTP Client:** httpx (for async API calls)  
**Configuration:** Pydantic Settings (type-safe environment variables)

**Architecture Pattern:** 
- FastAPI with router-based endpoints
- Dependency injection for database client
- Async/await patterns throughout
- Service layer separation

### Frontend Framework
**Framework:** React with TypeScript  
**Location:** `/ExistingDocs/TI Revamp 1.0/frontend/`

**Key Dependencies:**
```json
{
  "@supabase/supabase-js": "^2.39.0",
  "axios": "^1.6.5",
  "ag-grid-react": "^31.1.0",
  "react": "^18.2.0",
  "react-router-dom": "^6.21.3",
  "typescript": "^4.9.5"
}
```

**Database Client:** @supabase/supabase-js (direct client-side queries)  
**Data Grid:** AG Grid (for tabular data display)

---

## 2. Existing Supabase Tables

### Core Entity Tables

#### `clients`
**Purpose:** Store client information (taxpayers)  
**Schema:**
```sql
CREATE TABLE clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    primary_taxpayer_ssn TEXT NOT NULL UNIQUE,
    primary_taxpayer_name TEXT NOT NULL,
    spouse_ssn TEXT,
    spouse_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

#### `cases`
**Purpose:** Store individual tax resolution cases  
**Schema:**
```sql
CREATE TABLE cases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_number TEXT NOT NULL UNIQUE,
    client_id UUID REFERENCES clients(id) ON DELETE CASCADE,
    status_code TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

#### `tax_years`
**Purpose:** Store tax year information per case  
**Schema:**
```sql
CREATE TABLE tax_years (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    year INTEGER NOT NULL,
    filing_status TEXT,
    return_filed BOOLEAN DEFAULT FALSE,
    return_filed_date DATE,
    base_csed_date DATE,
    calculated_agi DECIMAL(15, 2),
    calculated_tax_liability DECIMAL(15, 2),
    calculated_account_balance DECIMAL(15, 2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(case_id, year)
);
```

### Transaction Data Tables (Current "Silver" Layer)

#### `income_documents`
**Purpose:** Store W-2, 1099, and other income forms (WI data)  
**Schema:**
```sql
CREATE TABLE income_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tax_year_id UUID REFERENCES tax_years(id) ON DELETE CASCADE,
    document_type TEXT NOT NULL,
    gross_amount DECIMAL(15, 2) DEFAULT 0,
    federal_withholding DECIMAL(15, 2) DEFAULT 0,
    calculated_category TEXT, -- SE, Non-SE, Neither
    is_self_employment BOOLEAN DEFAULT FALSE,
    include_in_projection BOOLEAN DEFAULT TRUE,
    fields JSONB, -- Additional form-specific fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```
**Data Source:** TiParser WI API  
**Current State:** Stores typed/parsed data (similar to Silver layer)

#### `account_activity`
**Purpose:** Store IRS account transcript transactions (AT data)  
**Schema:**
```sql
CREATE TABLE account_activity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tax_year_id UUID REFERENCES tax_years(id) ON DELETE CASCADE,
    activity_date DATE NOT NULL,
    irs_transaction_code TEXT NOT NULL,
    explanation TEXT,
    amount DECIMAL(15, 2),
    calculated_transaction_type TEXT,
    affects_balance BOOLEAN DEFAULT FALSE,
    affects_csed BOOLEAN DEFAULT FALSE,
    indicates_collection_action BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```
**Data Source:** TiParser AT API  
**Current State:** Stores typed/parsed data with enrichment

#### `trt_records`
**Purpose:** Tax Return Transcript data (expenses, deductions, schedules)  
**Schema:**
```sql
CREATE TABLE trt_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    tax_year_id UUID REFERENCES tax_years(id) ON DELETE CASCADE,
    response_date DATE,
    form_number TEXT, -- e.g., "1040", "Schedule A", "Schedule C"
    tax_period_ending DATE,
    primary_ssn TEXT,
    spouse_ssn TEXT,
    type TEXT, -- "General", "Form", "Schedule"
    category TEXT, -- "Income", "Expenses", "Summary", etc.
    sub_category TEXT,
    data TEXT, -- Raw field value
    numeric_value DECIMAL(15, 2), -- Parsed numeric value
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```
**Data Source:** TiParser TRT API  
**Current State:** Stores typed/parsed data

#### `logiqs_raw_data`
**Purpose:** Interview data from CaseHelper (employment, assets, income, expenses)  
**Schema:** 
```sql
CREATE TABLE logiqs_raw_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    
    -- Structured JSONB sections
    employment JSONB,
    household JSONB,
    assets JSONB,
    income JSONB,
    expenses JSONB,
    irs_standards JSONB,
    
    -- Individual cell reference columns (Excel mapping)
    -- Employment (Taxpayer)
    b3 TEXT, -- employer_name
    b4 DATE, -- employment_start_date
    b5 DECIMAL(15, 2), -- gross_income
    b6 DECIMAL(15, 2), -- net_income
    b7 TEXT, -- pay_frequency
    
    -- Employment (Spouse)
    c3 TEXT, -- spouse_employer_name
    c4 DATE, -- spouse_employment_start_date
    c5 DECIMAL(15, 2), -- spouse_gross_income
    c6 DECIMAL(15, 2), -- spouse_net_income
    c7 TEXT, -- spouse_pay_frequency
    
    -- ... 100+ additional Excel cell reference columns
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```
**Data Source:** CaseHelper Interview API  
**Current State:** Hybrid approach - JSONB + Excel cell reference columns  
**⚠️ Issue:** Cell references (b3, c61, al7) are not semantic

### Business Rule Tables

#### `wi_type_rules`
**Purpose:** Categorize income form types (SE vs Non-SE)  
**Schema:**
```sql
CREATE TABLE wi_type_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    form_code TEXT NOT NULL UNIQUE, -- "W-2", "1099-NEC", etc.
    category TEXT NOT NULL, -- "SE", "Non-SE", "Neither"
    is_self_employment BOOLEAN DEFAULT FALSE,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```
**Purpose in Medallion:** Silver layer enrichment

#### `at_transaction_rules`
**Purpose:** Classify IRS transaction codes  
**Schema:**
```sql
CREATE TABLE at_transaction_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_code TEXT NOT NULL UNIQUE, -- "150", "420", "430", etc.
    transaction_type TEXT NOT NULL, -- "Assessment", "Payment", "Interest"
    affects_balance BOOLEAN DEFAULT FALSE,
    affects_csed BOOLEAN DEFAULT FALSE,
    indicates_collection_action BOOLEAN DEFAULT FALSE,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```
**Purpose in Medallion:** Silver layer enrichment

#### `csed_calculation_rules`
**Purpose:** Rules for Collection Statute Expiration Date calculations  
**Schema:**
```sql
CREATE TABLE csed_calculation_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_name TEXT NOT NULL UNIQUE,
    tolling_type TEXT NOT NULL, -- "Bankruptcy", "OIC", "Installment Agreement"
    calculation_method TEXT,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```
**Purpose in Medallion:** Business logic for Gold layer

### Normalized "Gold" Tables (Recently Added)

#### `employment_information`
**Purpose:** Semantic employment data (replaces logiqs_raw_data Excel columns)  
**Schema:**
```sql
CREATE TABLE employment_information (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    person_type TEXT NOT NULL CHECK (person_type IN ('taxpayer', 'spouse')),
    
    -- Semantic columns
    employer_name TEXT, -- Replaces b3/c3
    employment_start_date DATE, -- Replaces b4/c4
    gross_monthly_income DECIMAL(15, 2), -- Replaces b5/c5
    net_monthly_income DECIMAL(15, 2), -- Replaces b6/c6
    pay_frequency TEXT, -- Replaces b7/c7
    
    is_self_employed BOOLEAN DEFAULT FALSE,
    excel_reference_map JSONB, -- Tracks Excel → DB mapping
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(case_id, person_type)
);
```
**Migration Status:** Schema created, not fully populated  
**Purpose in Medallion:** True Gold layer with semantic naming

#### `household_information`
**Purpose:** Household composition and residency  
**Schema:**
```sql
CREATE TABLE household_information (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    total_household_members INTEGER DEFAULT 1,
    members_under_65 INTEGER DEFAULT 0,
    members_over_65 INTEGER DEFAULT 0,
    state TEXT,
    county TEXT,
    excel_reference_map JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(case_id)
);
```

#### Additional Gold Tables (Schema Created)
- `household_members` - Individual household member records
- `financial_accounts` - Bank accounts, investments, etc.
- `vehicles` - Vehicle assets
- `real_estate` - Real property
- `monthly_expenses` - Categorized expenses
- `income_sources` - Non-employment income

**Status:** These tables exist but are not actively populated yet

### Supporting Tables

#### `tax_projections`
**Purpose:** Future tax liability projections  
**Fields:** tp_income, spouse_income, projected_tax, estimated_refund

#### `csed_tolling_events`
**Purpose:** Track events that pause/extend CSED  
**Fields:** event_type, start_date, end_date, days_tolled

#### `resolution_options`
**Purpose:** Store resolution recommendations (OIC, IA, CNC)  
**Fields:** recommendation_type, monthly_payment, duration_months

#### `extraction_progress`
**Purpose:** Track API extraction job status  
**Fields:** step, progress (0-100), message, details

---

## 3. API Client Code

### TiParser API Client

**Location:** 
- Service: `/backend/app/services/transcript_pipeline.py`
- Called from: `/backend/app/routers/extraction.py`

**Implementation:**
```python
class TranscriptPipeline:
    async def parse_pdf_with_tiparser(
        self,
        pdf_bytes: Optional[bytes],
        transcript_type: str,  # 'AT', 'WI', 'TRT'
        case_id: str
    ) -> Dict[str, Any]:
        """
        Parse transcripts using tiparser API
        tiparser downloads files from CaseHelper and parses them
        """
        from app.config import settings
        
        endpoint = f"{settings.tiparser_url}/analysis/{transcript_type.lower()}/{case_id}"
        
        async with httpx.AsyncClient(timeout=300.0) as client:
            headers = {
                "Content-Type": "application/json"
            }
            if settings.tiparser_api_key:
                headers["x-api-key"] = settings.tiparser_api_key
            
            response = await client.get(endpoint, headers=headers)
            
            if response.status_code != 200:
                raise Exception(f"Parsing failed: {response.status_code}")
            
            return response.json()
```

**Endpoints:**
- AT: `GET https://tiparser.onrender.com/analysis/at/{case_id}`
- WI: `GET https://tiparser.onrender.com/analysis/wi/{case_id}`
- TRT: `GET https://tiparser.onrender.com/analysis/trt/{case_id}`

**Current Flow:**
```
TiParser API → parse_pdf_with_tiparser() → save_at_data() / save_wi_data() / save_trt_data()
                                         ↓
                          Directly inserts into income_documents / account_activity / trt_records
```

**⚠️ Observation:** Currently skips Bronze layer - data goes directly to what we'd call "Silver" tables

### CaseHelper API Client

**Location:**
- Auth Service: `/backend/app/services/casehelper_auth.py`
- Fetcher Service: `/backend/app/services/interview_fetcher.py`

**Authentication Implementation:**
```python
class CaseHelperAuth:
    """Cookie-based authentication with CaseHelper API"""
    
    async def authenticate(self) -> dict:
        """Login and get cookies"""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.base_url}/v2/auth/login",
                json={
                    "credentials": {
                        "username": os.getenv("CASEHELPER_USERNAME"),
                        "password": os.getenv("CASEHELPER_PASSWORD"),
                        "appType": "transcript_pipeline"
                    }
                }
            )
            
            cookies = response.json().get("cookies", {})
            self.cookies = cookies
            self.cookie_expiry = datetime.now() + timedelta(hours=1)
            return cookies
```

**Interview Data Fetcher:**
```python
class InterviewFetcher:
    """Fetches interview data from CaseHelper API"""
    
    async def fetch_interview_data(self, case_id: str) -> Dict[str, Any]:
        """
        Fetch interview data from CaseHelper API
        Endpoint: GET /api/cases/{case_id}/interview
        """
        headers = await self.auth.get_auth_headers()
        
        api_key = os.getenv("CASEHELPER_API_KEY")
        if api_key:
            headers["X-API-Key"] = api_key
        
        endpoint = f"{self.base_url}/api/cases/{case_id}/interview"
        
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.get(endpoint, headers=headers)
            return response.json()
```

**Endpoint:**
- Interview: `GET https://casehelper-backend.onrender.com/api/cases/{case_id}/interview`

**Current Flow:**
```
CaseHelper API → fetch_interview_data() → save_logiqs_raw_data()
                                        ↓
                          Directly inserts into logiqs_raw_data (hybrid JSONB + columns)
```

**Authentication Pattern:** Cookie-based with 1-hour expiration, cached in memory

### Document Downloader

**Location:** `/backend/app/services/casehelper_downloader.py`

**Purpose:** Downloads transcript PDFs from CaseHelper  
**Current Usage:** TiParser handles downloads directly, so this is primarily for backup/verification

---

## 4. Authentication Patterns

### Supabase Access

**Backend Pattern:**
```python
# Location: /backend/app/database.py
from supabase import create_client, Client

def get_supabase_client() -> Client:
    """Singleton pattern for Supabase client"""
    global _supabase_client
    
    if _supabase_client is None:
        _supabase_client = create_client(
            settings.supabase_url,
            settings.supabase_key  # Service role key
        )
    
    return _supabase_client
```

**Frontend Pattern:**
```typescript
// Location: /frontend/src/lib/supabase.ts
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.REACT_APP_SUPABASE_URL;
const supabaseAnonKey = process.env.REACT_APP_SUPABASE_ANON_KEY;

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
```

**Key Types:**
- **Backend:** Uses `supabase_key` (Service Role Key) - full access
- **Frontend:** Uses `REACT_APP_SUPABASE_ANON_KEY` (Anon Key) - RLS protected

### Environment Variables

**Backend (.env):**
```bash
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-service-role-key

# TiParser API
TIPARSER_URL=https://tiparser.onrender.com
TIPARSER_API_KEY=optional-api-key

# CaseHelper API
CASEHELPER_API_URL=https://casehelper-backend.onrender.com
CASEHELPER_API_KEY=optional-api-key
CASEHELPER_USERNAME=lindsey.stevens@tra.com
CASEHELPER_PASSWORD=Secret#5986

# Application
FRONTEND_URL=http://localhost:3000
ENVIRONMENT=development
DEBUG=false
```

**Frontend (.env):**
```bash
REACT_APP_SUPABASE_URL=https://your-project.supabase.co
REACT_APP_SUPABASE_ANON_KEY=your-anon-key
```

**Configuration Loading:**
- Backend: Pydantic Settings with type validation
- Frontend: process.env (Create React App pattern)

### API Key Storage

**Current Pattern:**
- Environment variables (`.env` file locally)
- Loaded via `python-dotenv` and Pydantic Settings
- No secrets management system currently (plain text in .env)

**Security Notes:**
- `.env` is gitignored ✅
- Production uses Render.com environment variables ✅
- CaseHelper password is hardcoded in auth service ⚠️ (should be env var only)
- TiParser API key is optional (may be open endpoint) ✅

---

## 5. Current Data Flow Architecture

### Data Journey Visualization

```
┌─────────────────┐
│   TiParser API  │
│   (External)    │
└────────┬────────┘
         │ GET /analysis/{type}/{case_id}
         │
         v
┌─────────────────────────────────────┐
│  transcript_pipeline.py             │
│  - parse_pdf_with_tiparser()        │
└────────┬────────────────────────────┘
         │
         v
┌─────────────────────────────────────┐
│  data_saver.py                      │
│  - save_at_data()                   │
│  - save_wi_data()                   │
│  - save_trt_data()                  │
└────────┬────────────────────────────┘
         │
         v
┌─────────────────────────────────────┐
│  Supabase Tables (Current State)    │
│  ├─ account_activity (AT data)      │
│  ├─ income_documents (WI data)      │
│  └─ trt_records (TRT data)          │
└─────────────────────────────────────┘
         │
         │ (Manual queries / Frontend reads)
         v
┌─────────────────────────────────────┐
│  Resolution Calculations            │
│  - resolution_calculator.py         │
│  - schedule_calculator.py           │
└─────────────────────────────────────┘
```

```
┌─────────────────┐
│ CaseHelper API  │
│   (External)    │
└────────┬────────┘
         │ GET /api/cases/{id}/interview
         │
         v
┌─────────────────────────────────────┐
│  interview_fetcher.py               │
│  - fetch_interview_data()           │
└────────┬────────────────────────────┘
         │
         v
┌─────────────────────────────────────┐
│  data_saver.py                      │
│  - save_logiqs_raw_data()           │
└────────┬────────────────────────────┘
         │
         v
┌─────────────────────────────────────┐
│  Supabase: logiqs_raw_data          │
│  (Hybrid: JSONB + Excel columns)    │
└─────────────────────────────────────┘
         │
         │ (Not yet implemented)
         v
┌─────────────────────────────────────┐
│  Normalized Gold Tables             │
│  ├─ employment_information          │
│  ├─ household_information           │
│  └─ financial_accounts              │
└─────────────────────────────────────┘
```

### Current State Assessment

**What Works Well:**
1. ✅ Clear separation of API clients (TiParser, CaseHelper)
2. ✅ Reusable authentication services (CaseHelper cookies)
3. ✅ Business rule tables for enrichment (wi_type_rules, at_transaction_rules)
4. ✅ Type-safe data models (Pydantic)
5. ✅ Async/await throughout for performance

**What Needs Improvement:**
1. ⚠️ **No Bronze Layer:** Raw API responses are not stored (can't replay transformations)
2. ⚠️ **Inconsistent Naming:** logiqs_raw_data uses Excel cell references (b3, c61, al7)
3. ⚠️ **Gold Layer Not Active:** Normalized tables exist but not populated
4. ⚠️ **No Orchestration:** Manual API calls, no scheduling/automation
5. ⚠️ **No Data Lineage:** Can't trace data from API → Bronze → Silver → Gold
6. ⚠️ **Manual Transformations:** Python code handles all transformations (should be SQL triggers)

---

## 6. Integration Recommendations

### Where Bronze Layer Should Fit

**New Tables to Create:**
```sql
-- Bronze Layer: Store raw API responses as-is
CREATE TABLE bronze_at_raw (
  bronze_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES cases(id),
  raw_response JSONB NOT NULL, -- Entire TiParser AT response
  api_source TEXT DEFAULT 'tiparser',
  api_endpoint TEXT,
  inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE bronze_wi_raw (
  bronze_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES cases(id),
  raw_response JSONB NOT NULL, -- Entire TiParser WI response
  api_source TEXT DEFAULT 'tiparser',
  api_endpoint TEXT,
  inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE bronze_trt_raw (
  bronze_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES cases(id),
  raw_response JSONB NOT NULL, -- Entire TiParser TRT response
  api_source TEXT DEFAULT 'tiparser',
  api_endpoint TEXT,
  inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE bronze_interview_raw (
  bronze_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES cases(id),
  raw_response JSONB NOT NULL, -- Entire CaseHelper interview response
  api_source TEXT DEFAULT 'casehelper',
  api_endpoint TEXT,
  inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**Why Bronze is Critical:**
1. **Replay Transformations:** If Silver/Gold logic changes, reprocess from Bronze
2. **Audit Trail:** Know exactly what the API returned
3. **Data Recovery:** If bug in transformation, raw data is preserved
4. **Cost Savings:** Don't re-call expensive APIs, reprocess from Bronze
5. **Historical Analysis:** See how API responses changed over time

### How to Reuse Existing API Clients

**Recommended Integration Pattern:**

**Current:**
```python
# Current: API → Python → Silver (account_activity, income_documents)
parsed_data = await tiparser.parse_pdf_with_tiparser('AT', case_id)
await save_at_data(supabase, case_id, parsed_data)  # Direct to Silver
```

**Proposed (Dagster Asset):**
```python
@asset(
    description="Fetch AT data from TiParser and store in Bronze",
    group_name="bronze"
)
def bronze_at_data(
    context: AssetExecutionContext,
    tiparser_client: TiParserResource,
    supabase: SupabaseResource
) -> Dict[str, Any]:
    """
    Reuse existing TiParser client, but store raw response in Bronze
    SQL trigger will automatically populate Silver
    """
    case_id = context.op_config["case_id"]
    
    # 1. Call EXISTING TiParser client (no changes needed)
    raw_response = await tiparser_client.parse_pdf_with_tiparser('AT', case_id)
    
    # 2. Insert into Bronze (NEW - store raw response)
    result = supabase.table('bronze_at_raw').insert({
        'case_id': case_id,
        'raw_response': raw_response,
        'api_source': 'tiparser',
        'api_endpoint': f'/analysis/at/{case_id}'
    }).execute()
    
    bronze_id = result.data[0]['bronze_id']
    
    # 3. SQL trigger fires automatically:
    #    bronze_at_raw → account_activity (Silver)
    #    account_activity → tax_years_summary (Gold)
    
    # 4. Return metadata for Dagster
    return {
        "bronze_id": bronze_id,
        "case_id": case_id,
        "record_count": len(raw_response.get('records', []))
    }
```

**Key Advantages:**
- ✅ Reuse existing `transcript_pipeline.py` and `interview_fetcher.py`
- ✅ Minimal code changes (just add Bronze insert before save_*_data)
- ✅ SQL triggers handle Bronze → Silver transformation
- ✅ Dagster tracks lineage and metadata
- ✅ No disruption to existing endpoints

### What Existing Endpoints to Preserve

**Keep These FastAPI Endpoints (Wrap with Dagster):**

1. **`POST /api/extraction/trigger`** - Trigger transcript extraction
   - **Change:** Call Dagster asset materialization instead of direct processing
   - **Keep:** Progress tracking, error handling

2. **`GET /api/extraction/progress/{case_id}`** - Check extraction status
   - **Keep:** As-is, Dagster can update same progress table

3. **`POST /api/process/case/{case_id}`** - Process single case
   - **Keep:** For backward compatibility with frontend
   - **Change:** Internally triggers Dagster run

**Deprecate These (Move to Dagster):**
- Direct calls to `save_at_data()`, `save_wi_data()`, etc.
- Manual transformation logic in Python (move to SQL triggers)

**New Dagster Assets to Create:**
```
bronze_at_data
bronze_wi_data
bronze_trt_data
bronze_interview_data
  ↓
monitor_silver_population (check triggers worked)
  ↓
validate_gold_completeness (ensure Gold populated)
```

### Recommended Phased Approach

**Phase 1: Add Bronze Layer (Non-Breaking)**
1. Create bronze_* tables
2. Modify existing API clients to INSERT into Bronze first
3. Keep existing save_*_data() calls (temporary - for safety)
4. Verify Bronze data is captured correctly

**Phase 2: Add SQL Triggers (Bronze → Silver)**
1. Create trigger: bronze_at_raw → account_activity
2. Create trigger: bronze_wi_raw → income_documents
3. Create trigger: bronze_trt_raw → trt_records
4. Create trigger: bronze_interview_raw → logiqs_raw_data
5. Remove manual save_*_data() calls

**Phase 3: Normalize Gold Layer**
1. Create trigger: logiqs_raw_data → employment_information, household_information, etc.
2. Create trigger: account_activity → tax_years (aggregate)
3. Replace Excel cell references with semantic queries

**Phase 4: Orchestrate with Dagster**
1. Wrap API clients as Dagster resources
2. Create Dagster assets for Bronze ingestion
3. Add monitoring assets for Silver/Gold health
4. Schedule periodic materializations

**Phase 5: Deprecate Legacy**
1. Remove direct FastAPI → Silver writes
2. Remove Excel cell reference columns (use Gold tables)
3. Archive old Python transformation code

---

## 7. Current State Mapping to Medallion Layers

### What Exists Today

| Current Table          | Closest Medallion Layer | Issues                                    |
|------------------------|-------------------------|-------------------------------------------|
| `income_documents`     | Silver                  | ✅ Typed columns, ✅ Enriched with WI rules |
| `account_activity`     | Silver                  | ✅ Typed columns, ✅ Enriched with AT rules |
| `trt_records`          | Silver                  | ✅ Typed columns, ⚠️ No enrichment yet    |
| `logiqs_raw_data`      | Bronze-ish / Silver-ish | ⚠️ Has JSONB (Bronze) + typed columns (Silver) - HYBRID |
| `employment_information` | Gold                 | ✅ Semantic names, ⚠️ Not populated      |
| `household_information` | Gold                  | ✅ Semantic names, ⚠️ Not populated      |
| `financial_accounts`   | Gold                    | ✅ Semantic names, ⚠️ Not populated      |
| `wi_type_rules`        | Business Rules          | ✅ Lookup table for Silver enrichment    |
| `at_transaction_rules` | Business Rules          | ✅ Lookup table for Silver enrichment    |
| ❌ **Missing**         | **Bronze**              | **No raw API response storage**          |

### Proposed Target State

```
BRONZE LAYER (New)
├─ bronze_at_raw          (raw TiParser AT responses)
├─ bronze_wi_raw          (raw TiParser WI responses)
├─ bronze_trt_raw         (raw TiParser TRT responses)
└─ bronze_interview_raw   (raw CaseHelper interview responses)

        ↓ SQL Triggers (JSONB extraction + typing)

SILVER LAYER (Existing + Enhance)
├─ account_activity       (typed AT transactions) ✅ EXISTS
├─ income_documents       (typed WI forms) ✅ EXISTS
├─ trt_records           (typed TRT records) ✅ EXISTS
└─ silver_interview_data  (typed interview responses) ⚠️ NEEDS NORMALIZATION

        ↓ SQL Triggers (business logic + aggregation)

GOLD LAYER (Existing + Populate)
├─ tax_years             (aggregated tax year summaries) ✅ EXISTS
├─ employment_information (semantic employment data) ✅ SCHEMA EXISTS, needs population
├─ household_information (semantic household data) ✅ SCHEMA EXISTS, needs population
├─ financial_accounts    (semantic asset data) ✅ SCHEMA EXISTS, needs population
├─ monthly_expenses      (semantic expense data) ✅ SCHEMA EXISTS, needs population
└─ resolution_options    (final recommendations) ✅ EXISTS

BUSINESS RULES (Existing)
├─ wi_type_rules         ✅ EXISTS
├─ at_transaction_rules  ✅ EXISTS
└─ csed_calculation_rules ✅ EXISTS
```

---

## 8. Risks & Considerations

### Technical Risks

1. **Data Loss Risk During Migration**
   - **Mitigation:** Add Bronze layer FIRST, keep existing flow until validated

2. **Performance Impact of Triggers**
   - **Mitigation:** Index foreign keys, test with large datasets, use async patterns

3. **Breaking Frontend**
   - **Mitigation:** Keep FastAPI endpoints, change internals only

4. **API Response Changes**
   - **Mitigation:** Bronze layer captures raw responses, can handle variations

### Business Risks

1. **Excel Cell References in Production**
   - **Risk:** logiqs_raw_data has b3, c61, al7 columns (not self-documenting)
   - **Impact:** Developers must reference Excel file to understand data
   - **Mitigation:** Phase 3 replaces with Gold tables (semantic names)

2. **No Data Lineage**
   - **Risk:** Can't trace errors back to API source
   - **Impact:** Debugging is difficult
   - **Mitigation:** Bronze layer + Dagster lineage tracking

3. **Manual Orchestration**
   - **Risk:** Extraction jobs triggered manually via API
   - **Impact:** Scaling requires custom infrastructure
   - **Mitigation:** Dagster Cloud for scheduling/monitoring

---

## 9. Next Steps for Phase 1

### Immediate Actions

1. **Get Sample API Responses** (Required for Phase 1: API Analysis)
   - Request actual TiParser AT response JSON
   - Request actual TiParser WI response JSON
   - Request actual TiParser TRT response JSON
   - Request actual CaseHelper Interview response JSON

2. **Document Field Variations** (Phase 1: API Analysis)
   - Map all field names in API responses
   - Document nested structures
   - Identify optional vs required fields
   - Plan COALESCE strategies for variations

3. **Design Bronze Tables** (Phase 3: Bronze Layer)
   - Finalize bronze_* table schemas
   - Plan indexes for case_id lookups
   - Determine retention policies

4. **Create SQL Triggers** (Phase 4: Silver Layer)
   - Trigger: bronze_at_raw → account_activity
   - Trigger: bronze_wi_raw → income_documents
   - Trigger: bronze_trt_raw → trt_records
   - Trigger: bronze_interview_raw → logiqs_raw_data

5. **Set Up Dagster** (Phase 6: Dagster Orchestration)
   - Install Dagster locally
   - Create Supabase resource
   - Create TiParser resource (wrap existing client)
   - Create CaseHelper resource (wrap existing client)

---

## 10. Key Contacts & Resources

### Code Locations
- **Backend API:** `/ExistingDocs/TI Revamp 1.0/backend/`
- **Frontend UI:** `/ExistingDocs/TI Revamp 1.0/frontend/`
- **Supabase Migrations:** `/ExistingDocs/TI Revamp 1.0/supabase/migrations/`
- **API Documentation:** `/ExistingDocs/TI Revamp 1.0/tax-sheet-extraction/`

### External APIs
- **TiParser:** https://tiparser.onrender.com
- **CaseHelper:** https://casehelper-backend.onrender.com
- **Supabase:** Configured via SUPABASE_URL environment variable

### Documentation
- **API Keys:** `/ExistingDocs/TI Revamp 1.0/tax-sheet-extraction/configs/api-keys.md`
- **Environment Variables:** `/ExistingDocs/TI Revamp 1.0/tax-sheet-extraction/configs/environment-vars.md`
- **Schema Proposal:** `/ExistingDocs/TI Revamp 1.0/SUPABASE_SCHEMA_PROPOSAL.md`
- **Field Inventory:** `/ExistingDocs/TI Revamp 1.0/COMPLETE_UNIFIED_FIELD_INVENTORY.md`

---

## 11. Conclusion

The existing system has a **strong foundation** for a medallion architecture:
- ✅ Clean API client abstractions
- ✅ Type-safe data models
- ✅ Business rule tables for enrichment
- ✅ Normalized Gold schema (partially implemented)

**Missing pieces:**
- ❌ Bronze layer (raw API response storage)
- ❌ SQL triggers (automated transformations)
- ❌ Orchestration (Dagster for scheduling/monitoring)
- ❌ Data lineage (traceability from API → Gold)

**Recommended Strategy:**
1. Add Bronze layer (non-breaking, captures raw data)
2. Create SQL triggers (move transformation logic from Python to SQL)
3. Populate Gold layer (replace Excel cell references with semantic tables)
4. Introduce Dagster (orchestrate Bronze ingestion, monitor Silver/Gold health)

**Estimated Effort:**
- Phase 1 (API Analysis): 1-2 days
- Phase 2 (Business Rules): 1 day
- Phase 3 (Bronze Layer): 2-3 days
- Phase 4 (Silver Triggers): 3-4 days
- Phase 5 (Gold Normalization): 4-5 days
- Phase 6 (Dagster Integration): 3-4 days
- **Total: ~3-4 weeks for full implementation**

---

**Phase 0 Complete ✅**  
**Next:** Phase 1 - API Response Analysis (need sample JSON responses from APIs)

