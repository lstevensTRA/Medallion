# Medallion Architecture Implementation Kit

This directory contains everything you need to implement a production-ready Bronze → Silver → Gold data architecture using Cursor AI as your development assistant.

---

## 📦 What's Included

### 1. `.cursorrules` - Main Configuration File
**Purpose:** Cursor AI's instruction manual for building your medallion architecture

**What it does:**
- Guides Cursor through 8 implementation phases
- Enforces documentation-first approach
- Ensures complete, production-ready code
- Automatically generates documentation at each step
- Handles API response analysis
- Manages progress tracking

**How to use:**
1. Copy to your project root: `cp .cursorrules /your-project/.cursorrules`
2. Restart Cursor/VS Code
3. Start with Phase 0 prompt (see Quick Start Guide)

---

### 2. `QUICK_START_GUIDE.md` - Step-by-Step Implementation
**Purpose:** Your roadmap for the entire implementation

**Contains:**
- Phase-by-phase prompts to give Cursor
- Expected outputs for each phase
- Success criteria
- Timeline estimates (18 days)
- Troubleshooting tips

**How to use:**
1. Read through all phases first
2. Follow phases in order (0 → 8)
3. Use the exact prompts provided
4. Verify expected outputs before moving on

---

### 3. `API_RESPONSE_TEMPLATE.md` - API Data Collection
**Purpose:** Template for providing real API responses to Cursor

**Contains:**
- Templates for TiParser AT responses
- Templates for TiParser WI responses
- Templates for CaseHelper Interview responses
- Instructions on where to get responses
- Validation checklist

**How to use:**
1. Fill in with your actual API responses
2. Remove sensitive data
3. Provide to Cursor during Phase 1
4. Cursor uses this to design extraction logic

---

## 🎯 Implementation Overview

### What You're Building

A complete data pipeline that:

```
API Sources (TiParser, CaseHelper)
         ↓
   Bronze Layer (Raw JSONB storage)
         ↓
   [SQL Triggers]
         ↓
   Silver Layer (Typed & Enriched)
         ↓
   [SQL Triggers]
         ↓
   Gold Layer (Normalized Business Entities)
         ↓
   Business Logic Functions
```

**Key Features:**
- ✅ Non-invasive (doesn't break existing code)
- ✅ Automatic transformations (SQL triggers)
- ✅ Dagster orchestration
- ✅ Complete documentation
- ✅ Comprehensive tests
- ✅ Production-ready

---

## 📅 Timeline

### Week 1: Foundation (Days 1-5)
- **Day 1:** Phase 0 - Discovery
- **Day 2:** Phase 1 - API Analysis
- **Day 3:** Phase 2 - Business Rules
- **Days 4-5:** Phase 3 - Bronze Layer

### Week 2: Transformations (Days 6-12)
- **Days 6-8:** Phase 4 - Silver Layer
- **Days 9-12:** Phase 5 - Gold Layer

### Week 3: Production (Days 13-18)
- **Days 13-14:** Phase 6 - Dagster Orchestration
- **Days 15-16:** Phase 7 - Testing
- **Days 17-18:** Phase 8 - Deployment

**Total: 18 days** (3-4 weeks at normal pace)

---

## 🚀 Getting Started

### Prerequisites

1. **Cursor AI** (or VS Code with Cursor extension)
2. **Supabase project** (with connection details)
3. **Dagster** (or ready to install)
4. **Access to APIs** (TiParser, CaseHelper)
5. **Sample API responses** (see API_RESPONSE_TEMPLATE.md)

### Step 1: Setup

```bash
# 1. Copy .cursorrules to project root
cp .cursorrules /your-project/.cursorrules

# 2. Create docs directory
mkdir -p /your-project/docs

# 3. Restart Cursor/VS Code
```

### Step 2: Start Phase 0

Open Cursor and use this prompt:

```
Let's start Phase 0: Discovery. 

Please analyze this codebase and create docs/00_DISCOVERY_REPORT.md with:

1. **Tech Stack Analysis**
   - What framework is the backend? (Express/FastAPI/Next.js API?)
   - What ORM/database library is used?
   - What's in package.json or requirements.txt?

2. **Existing Supabase Tables**
   - List all current tables
   - Show their schemas
   - Document relationships

3. **API Client Code**
   - Where is the TiParser client?
   - Where is the CaseHelper client?
   - How are they called currently?

4. **Authentication Patterns**
   - How is Supabase accessed?
   - Where are API keys stored?
   - What's the connection pattern?

5. **Integration Recommendations**
   - Where should Bronze layer fit?
   - How to reuse existing API clients?
   - What existing endpoints to preserve?

Start with a full codebase exploration and document everything you find.
```

### Step 3: Follow the Guide

1. Cursor will analyze your codebase
2. Create `docs/00_DISCOVERY_REPORT.md`
3. Ask you questions if needed
4. Provide recommendations
5. Ask "Ready for Phase 1?"

Continue following prompts from `QUICK_START_GUIDE.md`

---

## 📊 What You'll Get

### Documentation (8 Files)

At the end, you'll have:

```
docs/
├── 00_DISCOVERY_REPORT.md       # Existing architecture
├── 01_API_ANALYSIS.md            # API field mappings
├── 02_BUSINESS_RULES.md          # Lookup tables
├── 03_BRONZE_LAYER.md            # Raw storage
├── 04_SILVER_LAYER.md            # Typed data
├── 05_GOLD_LAYER.md              # Normalized entities
├── 06_DAGSTER_ORCHESTRATION.md   # Pipeline orchestration
├── 07_TESTING_STRATEGY.md        # Complete tests
└── 08_DEPLOYMENT_GUIDE.md        # Production deployment
```

### Database Migrations (15+ Files)

```
supabase/migrations/
├── 001_bronze_core_entities.sql
├── 002_bronze_tables.sql
├── 003_business_rules.sql
├── 004_silver_tables.sql
├── 005_bronze_to_silver_triggers.sql
├── 006_gold_core_tables.sql
├── 007_gold_services_tables.sql
├── 008_gold_documents_tables.sql
├── 009_gold_normalized_v2_tables.sql
├── 010_gold_resolution_tables.sql
└── 011_silver_to_gold_triggers.sql
```

### Dagster Pipeline (Complete)

```
dagster_pipeline/
├── __init__.py
├── assets/
│   ├── bronze_assets.py          # API ingestion
│   ├── silver_assets.py          # Monitoring
│   └── gold_assets.py            # Monitoring
├── resources/
│   ├── supabase_resource.py      # Database connection
│   ├── tiparser_resource.py      # API client
│   └── casehelper_resource.py    # API client
├── tests/
│   ├── test_bronze.py            # Bronze tests
│   ├── test_silver.py            # Silver tests
│   ├── test_gold.py              # Gold tests
│   ├── test_end_to_end.py        # Integration tests
│   └── test_performance.py       # Performance tests
└── fixtures/
    ├── sample_at_response.json   # Test data
    ├── sample_wi_response.json   # Test data
    └── sample_interview_response.json
```

### Tables Created (60+ Total)

**Bronze (3):**
- bronze_at_raw
- bronze_wi_raw
- bronze_interview_raw

**Business Rules (4):**
- wi_type_rules
- at_transaction_rules
- csed_calculation_rules
- status_definitions

**Silver (5):**
- silver_tax_years
- silver_account_activity
- silver_income_documents
- silver_csed_events
- silver_logiqs_flattened

**Gold (50+):**
- Core entities (cases, tax_years, etc.)
- Normalized V2 (employment, household, assets, etc.)
- Services (case_services, tax_year_services)
- Documents (documents, signatures, mailings)
- Resolution (resolution_options)

---

## 🎨 Code Quality

### Everything Includes:

**SQL Migrations:**
- ✅ Complete comments
- ✅ Rollback instructions
- ✅ Purpose statements
- ✅ Example usage

**Python Code:**
- ✅ Full docstrings
- ✅ Type hints
- ✅ Error handling
- ✅ Example usage
- ✅ Logging

**Tests:**
- ✅ Given/When/Then format
- ✅ Data quality checks
- ✅ Integration tests
- ✅ Performance benchmarks

**Documentation:**
- ✅ Architecture diagrams
- ✅ Data flow diagrams
- ✅ Field mappings
- ✅ Example data
- ✅ Deployment guides

---

## 🚨 Important Notes

### What Cursor WILL Do:

- ✅ Analyze your existing codebase
- ✅ Generate complete, production-ready code
- ✅ Create comprehensive documentation
- ✅ Write tests for everything
- ✅ Handle field variations and edge cases
- ✅ Integrate with your existing APIs
- ✅ Preserve your existing code

### What Cursor WILL NOT Do:

- ❌ Modify your frontend (unless you ask)
- ❌ Break existing endpoints
- ❌ Skip documentation
- ❌ Leave TODOs or FIXMEs
- ❌ Create shortcuts
- ❌ Guess at API structures

### What You MUST Provide:

1. **Real API responses** (Phase 1)
   - Not descriptions, actual JSON
   - Including variations and edge cases

2. **Business rules data** (Phase 2)
   - WI type rules (form categorization)
   - AT transaction codes
   - CSED calculation rules

3. **Excel column mappings** (Phase 5)
   - If using Logiqs Raw Data
   - Cell references to semantic names

### When to Ask Questions:

Cursor will ask you for input when:
- API response structure unclear
- Business rule clarification needed
- Multiple approaches possible
- Data quality issues found

**Always provide what Cursor asks for** - it needs real data to generate correct code.

---

## 💡 Tips for Success

### 1. Don't Skip Discovery
Understanding your existing code is critical. Let Cursor analyze everything first.

### 2. Provide Real API Responses
The better your example responses, the better the implementation. Include:
- Edge cases
- Field variations
- Null values
- Nested structures

### 3. Follow Phases in Order
Each phase builds on the previous. Don't jump ahead.

### 4. Review Generated Code
Cursor generates complete code, but review it to ensure it fits your needs.

### 5. Test Each Layer
Don't wait until the end to test. Validate each layer works before moving on.

### 6. Ask Questions
If something's unclear, ask Cursor for clarification or alternatives.

---

## 🔍 Troubleshooting

### "Cursor doesn't know what to do"
**Fix:** Make sure you completed the previous phase first

### "API response structure unclear"
**Fix:** Provide actual JSON responses, not descriptions

### "Trigger isn't working"
**Fix:** Check Phase 1 API Analysis - did we miss a field variation?

### "Tests failing"
**Fix:** Verify sample data matches Phase 1 analysis

### "Can't connect to Supabase"
**Fix:** Check environment variables and connection string

### "Dagster assets not running"
**Fix:** Verify resources are configured and dependencies installed

---

## 📞 Getting Help

### In Cursor:

Ask Cursor directly:
```
I'm stuck on [problem]. Here's what I tried:
1. [Attempt 1]
2. [Attempt 2]

What should I do differently?
```

### Common Questions:

**Q: Can I modify the phases?**
A: Yes, but follow the order (Bronze → Silver → Gold)

**Q: Can I use a different database?**
A: Yes, but you'll need to adapt migrations (Cursor can help)

**Q: Can I add more tables to Gold?**
A: Absolutely! Just document them in Phase 5

**Q: How long does this really take?**
A: Depends on:
- Complexity of APIs (simple = faster)
- Number of business rules (more = longer)
- Your API response gathering speed
- Review/testing thoroughness

Estimate: 2-4 weeks at normal pace

---

## ✅ Final Checklist

Before starting, verify you have:

- [ ] Cursor AI installed and working
- [ ] Access to Supabase project
- [ ] Supabase connection string
- [ ] Access to TiParser API
- [ ] Access to CaseHelper API
- [ ] API keys/credentials
- [ ] Ability to get API responses
- [ ] Time to dedicate (2-4 weeks)
- [ ] `.cursorrules` copied to project
- [ ] `docs/` directory created
- [ ] Ready to start Phase 0

---

## 🎉 Ready to Build!

You now have everything you need to build a production-ready medallion architecture with Cursor as your AI development partner.

**Start with this prompt:**

```
Let's start Phase 0: Discovery. 

Please analyze this codebase and create docs/00_DISCOVERY_REPORT.md...
[Use full prompt from QUICK_START_GUIDE.md]
```

Cursor will guide you through the entire implementation, generating complete code and documentation at every step.

**Good luck!** 🚀

---

**Questions or issues?** Ask Cursor - it has the full `.cursorrules` context and can help troubleshoot.
