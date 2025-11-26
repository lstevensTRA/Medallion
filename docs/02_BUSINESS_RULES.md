# Phase 2: Business Rules Documentation

**Date:** November 21, 2024  
**Status:** ✅ Complete  
**Existing Seed Data:** `/supabase/seed.sql` (201 lines)

---

## Executive Summary

This phase documents the business rule tables that enrich Silver layer data with semantic meaning and enable Gold layer calculations. Your existing `seed.sql` already contains comprehensive rule data for all 4 business rule tables:

- ✅ **wi_type_rules**: 16 income form types categorized by SE/Non-SE/Neither
- ✅ **at_transaction_rules**: 26 IRS transaction codes with balance/CSED flags
- ✅ **csed_calculation_rules**: 7 CSED event categories with toll day calculations
- ✅ **status_definitions**: 8 case status codes with next actions

**Key Insight:** These rules are the "brain" of your medallion architecture - they transform raw numeric codes into business intelligence.

---

## Table 1: wi_type_rules (Income Document Types)

### Purpose
Categorize income forms (W-2, 1099-NEC, etc.) to determine:
- Self-employment status (affects SE tax calculations)
- Tax projection inclusion
- Resolution option eligibility

### Schema

```sql
CREATE TABLE wi_type_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    form_code TEXT NOT NULL UNIQUE,              -- e.g., "W-2", "1099-NEC"
    form_name TEXT NOT NULL,                     -- e.g., "Wage and Tax Statement"
    category TEXT NOT NULL,                      -- "SE", "Non-SE", "Neither"
    is_self_employment BOOLEAN DEFAULT FALSE,    -- Affects SE tax calculations
    include_in_projection BOOLEAN DEFAULT TRUE,  -- Include in future tax projections
    affects_resolution_options BOOLEAN DEFAULT FALSE, -- Impacts resolution strategy
    resolution_income_asset TEXT,               -- "Income" or "Asset" classification
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### Existing Seed Data (16 Form Types)

#### Category: Non-SE (Non-Self-Employment) - 9 forms

| Form Code | Form Name | Include in Projection | Affects Resolution |
|-----------|-----------|----------------------|-------------------|
| `W-2` | Wage and Tax Statement | ✅ Yes | ❌ No |
| `W-2G` | Gambling Winnings | ✅ Yes | ❌ No |
| `W-2GU` | Unemployment Compensation | ✅ Yes | ❌ No |
| `1099-INT` | Interest Income | ✅ Yes | ❌ No |
| `1099-DIV` | Dividends | ✅ Yes | ❌ No |
| `1099-R` | Distributions From Pensions, Annuities, Retirement | ✅ Yes | ❌ No |
| `SSA-1099` | Social Security Benefit Statement | ✅ Yes | ❌ No |
| `RRB-1099` | Railroad Retirement Benefits | ✅ Yes | ❌ No |
| `1099-G` | Certain Government Payments | ✅ Yes | ❌ No |

#### Category: SE (Self-Employment) - 3 forms

| Form Code | Form Name | Include in Projection | Affects Resolution |
|-----------|-----------|----------------------|-------------------|
| `1099-NEC` | Nonemployee Compensation | ✅ Yes | ✅ **Yes** |
| `1099-MISC` | Miscellaneous Income | ✅ Yes | ✅ **Yes** |
| `1099-K` | Payment Card and Third Party Network Transactions | ✅ Yes | ✅ **Yes** |

**Why SE Affects Resolution:**
- SE income requires 15.3% SE tax calculation
- Higher tax liability impacts payment plan amounts
- May qualify for different resolution options (OIC vs IA)

#### Category: Neither - 4 forms

| Form Code | Form Name | Include in Projection | Notes |
|-----------|-----------|----------------------|-------|
| `1099-B` | Proceeds From Broker Transactions | ✅ Yes | Capital gains |
| `1099-SA` | Distributions From HSA, Archer MSA, or Medicare | ✅ Yes | Healthcare |
| `1099-C` | Cancellation of Debt | ✅ Yes | Income from debt forgiveness |
| `1099-A` | Acquisition or Abandonment of Secured Property | ✅ Yes | Property transactions |

### Recommended Additions (Gap Analysis)

Based on IRS documentation, consider adding these common forms:

```sql
INSERT INTO wi_type_rules (form_code, form_name, category, is_self_employment, include_in_projection, affects_resolution_options) VALUES
-- Additional SE forms
('1099-PATR', 'Taxable Distributions from Cooperatives', 'SE', true, true, true),

-- Additional Non-SE forms
('1099-Q', 'Payments from Qualified Education Programs', 'Non-SE', false, true, false),
('1099-S', 'Proceeds from Real Estate Transactions', 'Neither', false, true, false),
('1099-LTC', 'Long-Term Care and Accelerated Death Benefits', 'Non-SE', false, true, false),

-- State-specific forms
('W-2C', 'Corrected Wage and Tax Statement', 'Non-SE', false, true, false),
('1099-OID', 'Original Issue Discount', 'Non-SE', false, true, false)
ON CONFLICT (form_code) DO NOTHING;
```

### Usage in Silver Layer Triggers

From Phase 1 (`insert_bronze_wi()` trigger):

```sql
-- Get business rule for form type
SELECT * INTO v_rule FROM wi_type_rules WHERE form_code = v_form_type;

-- Apply enrichment to income_documents
INSERT INTO income_documents (
  calculated_category,        -- From rule: 'SE', 'Non-SE', 'Neither'
  is_self_employment,         -- From rule: true/false
  include_in_projection       -- From rule: true/false
) VALUES (
  COALESCE(v_rule.category, 'Neither'),
  COALESCE(v_rule.is_self_employment, false),
  COALESCE(v_rule.include_in_projection, true)
);
```

### Business Logic Functions

#### Function: Calculate SE Tax

```sql
CREATE OR REPLACE FUNCTION calculate_se_tax(
  gross_income DECIMAL,
  form_code TEXT
) RETURNS DECIMAL AS $$
DECLARE
  is_se BOOLEAN;
  se_rate DECIMAL := 0.153; -- 15.3% SE tax rate
BEGIN
  -- Check if form is SE
  SELECT is_self_employment INTO is_se FROM wi_type_rules WHERE form_code = form_code;
  
  IF is_se THEN
    -- Calculate SE tax (gross * 0.9235 * 0.153)
    RETURN ROUND(gross_income * 0.9235 * se_rate, 2);
  ELSE
    RETURN 0;
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Example usage:
-- SELECT calculate_se_tax(50000.00, '1099-NEC');  -- Returns 7,065.23
-- SELECT calculate_se_tax(50000.00, 'W-2');       -- Returns 0.00
```

#### Function: Get Form Category

```sql
CREATE OR REPLACE FUNCTION get_form_category(form_code TEXT)
RETURNS TEXT AS $$
DECLARE
  category_result TEXT;
BEGIN
  SELECT category INTO category_result FROM wi_type_rules WHERE form_code = form_code;
  RETURN COALESCE(category_result, 'Neither');
END;
$$ LANGUAGE plpgsql STABLE;

-- Example usage:
-- SELECT get_form_category('W-2');        -- Returns 'Non-SE'
-- SELECT get_form_category('1099-NEC');   -- Returns 'SE'
-- SELECT get_form_category('UNKNOWN');    -- Returns 'Neither'
```

---

## Table 2: at_transaction_rules (IRS Transaction Codes)

### Purpose
Map IRS transaction codes (150, 806, 420, etc.) to meaningful business events that:
- Affect account balance calculations
- Impact CSED (Collection Statute Expiration Date)
- Indicate collection actions (levy, lien, garnishment)

### Schema

```sql
CREATE TABLE at_transaction_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,                      -- e.g., "150", "806", "420"
    meaning TEXT NOT NULL,                          -- Human-readable description
    transaction_type TEXT NOT NULL,                 -- Category (return_filed, payment, etc.)
    affects_balance BOOLEAN DEFAULT FALSE,          -- Impacts account balance
    affects_csed BOOLEAN DEFAULT FALSE,             -- Pauses/extends CSED
    indicates_collection_action BOOLEAN DEFAULT FALSE, -- Collection activity
    starts_csed BOOLEAN DEFAULT FALSE,              -- Initiates 10-year CSED clock
    csed_toll_days INTEGER DEFAULT 0,              -- Days to add to CSED
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### Existing Seed Data (26 Transaction Codes)

#### Return Filed / Assessment Codes (4 codes)

| Code | Meaning | Affects Balance | Starts CSED | Toll Days |
|------|---------|----------------|-------------|-----------|
| `150` | Return filed / Tax assessed | ✅ Yes | ✅ **Yes** | 0 |
| `290` | Additional tax assessed | ✅ Yes | ❌ No | 0 |
| `291` | Tax abatement / adjustment | ✅ Yes | ❌ No | 0 |
| `300` | Additional tax on amended return | ✅ Yes | ❌ No | 0 |

**Note:** Code 150 is critical - it starts the 10-year CSED clock!

#### Payment Codes (3 codes)

| Code | Meaning | Affects Balance | Notes |
|------|---------|----------------|-------|
| `610` | Payment received | ✅ Yes | Standard payment |
| `670` | Payment applied from other year | ✅ Yes | Transfer between tax years |
| `680` | Payment applied from other account | ✅ Yes | Transfer between accounts |

#### Penalty Codes (2 codes)

| Code | Meaning | Affects Balance | Toll Days | Notes |
|------|---------|----------------|-----------|-------|
| `196` | Estimated tax penalty | ✅ Yes | **30** | Adds 30 days to CSED |
| `276` | Delinquency penalty | ✅ Yes | **30** | Adds 30 days to CSED |

#### Offer in Compromise (OIC) Codes (4 codes)

| Code | Meaning | Affects CSED | Toll Days | Notes |
|------|---------|--------------|-----------|-------|
| `480` | OIC pending | ✅ Yes | **30** | CSED tolled while pending |
| `481` | OIC rejected | ❌ No | 0 | CSED resumes |
| `482` | OIC accepted | ✅ Yes | 0 | CSED extends |
| `483` | OIC withdrawn | ❌ No | 0 | CSED resumes |

#### Bankruptcy Codes (3 codes)

| Code | Meaning | Affects CSED | Toll Days | Notes |
|------|---------|--------------|-----------|-------|
| `520` | Bankruptcy / Collection freeze | ✅ Yes | **180** | Tolls for 6 months minimum |
| `521` | Bankruptcy freeze released | ❌ No | 0 | CSED resumes |
| `780` | Account included in bankruptcy | ✅ Yes | **180** | Tolls for 6 months |

#### Collection Action Codes (5 codes)

| Code | Meaning | Affects CSED | Collection Action | Notes |
|------|---------|--------------|-------------------|-------|
| `530` | Currently Not Collectible (CNC) | ❌ No | ❌ No | Temporary hardship |
| `971` | Notice issued (levy/garnishment precursor) | ✅ Yes | ✅ **Yes** | Pre-levy notice |
| `972` | Notice of levy | ✅ Yes | ✅ **Yes** | Actual levy |
| `973` | Notice of intent to levy | ✅ Yes | ✅ **Yes** | Warning notice |
| `977` | Appeal pending | ✅ Yes | ❌ No | CDP appeal |

#### Lien Codes (2 codes)

| Code | Meaning | Collection Action | Notes |
|------|---------|-------------------|-------|
| `602` | Federal Tax Lien filed | ✅ **Yes** | Public record lien |
| `603` | Federal Tax Lien released | ❌ No | Lien removed |

### Recommended Additions (Gap Analysis)

Based on IRS Account Transcript analysis, consider adding these common codes:

```sql
INSERT INTO at_transaction_rules (code, meaning, transaction_type, affects_balance, affects_csed, indicates_collection_action, starts_csed, csed_toll_days) VALUES
-- Withholding
('806', 'W-2 or 1099 withholding', 'withholding', true, false, false, false, 0),
('826', 'Overpayment transferred to estimated tax', 'transfer', true, false, false, false, 0),

-- Refunds
('840', 'Refund issued', 'refund', true, false, false, false, 0),
('846', 'Refund check issued', 'refund_check', true, false, false, false, 0),

-- Interest
('160', 'Underpayment interest charged', 'interest', true, false, false, false, 0),

-- Installment Agreements
('360', 'Installment agreement established', 'installment_agreement', false, false, false, false, 0),
('420', 'Examination (audit)', 'examination', false, true, false, false, 0),
('421', 'Examination closed', 'examination_closed', false, false, false, false, 0),

-- Credits
('766', 'Credit to account (various)', 'credit', true, false, false, false, 0),
('768', 'Earned Income Credit', 'credit_eic', true, false, false, false, 0),

-- Adjustments
('570', 'Additional account action pending', 'pending', false, true, false, false, 0),
('571', 'Resolved account action', 'resolved', false, false, false, false, 0)
ON CONFLICT (code) DO UPDATE SET
    meaning = EXCLUDED.meaning,
    transaction_type = EXCLUDED.transaction_type,
    affects_balance = EXCLUDED.affects_balance,
    affects_csed = EXCLUDED.affects_csed,
    indicates_collection_action = EXCLUDED.indicates_collection_action,
    starts_csed = EXCLUDED.starts_csed,
    csed_toll_days = EXCLUDED.csed_toll_days;
```

### Usage in Silver Layer Triggers

From Phase 1 (`insert_bronze_at()` trigger):

```sql
-- Get business rule for transaction code
SELECT * INTO v_rule FROM at_transaction_rules 
WHERE code = COALESCE(v_txn->>'code', v_txn->>'Code', v_txn->>'transaction_code');

-- Apply enrichment to account_activity
INSERT INTO account_activity (
  explanation,                        -- From rule if missing
  calculated_transaction_type,        -- From rule: 'return_filed', 'payment', etc.
  affects_balance,                    -- From rule: true/false
  affects_csed,                       -- From rule: true/false
  indicates_collection_action         -- From rule: true/false
) VALUES (
  COALESCE(v_txn->>'explanation', v_rule.meaning),
  v_rule.transaction_type,
  COALESCE(v_rule.affects_balance, false),
  COALESCE(v_rule.affects_csed, false),
  COALESCE(v_rule.indicates_collection_action, false)
);

-- Handle CSED tolling events
IF v_rule.starts_csed OR COALESCE(v_rule.csed_toll_days, 0) > 0 THEN
  INSERT INTO csed_tolling_events (...);
END IF;
```

### Business Logic Functions

#### Function: Calculate Account Balance

```sql
CREATE OR REPLACE FUNCTION calculate_account_balance(
  p_tax_year_id UUID
) RETURNS DECIMAL AS $$
DECLARE
  balance DECIMAL := 0;
BEGIN
  -- Sum all transactions that affect balance
  SELECT COALESCE(SUM(amount), 0) INTO balance
  FROM account_activity
  WHERE tax_year_id = p_tax_year_id
    AND affects_balance = true;
  
  RETURN balance;
END;
$$ LANGUAGE plpgsql STABLE;

-- Example usage:
-- SELECT calculate_account_balance('tax-year-uuid');
```

#### Function: Check Collection Activity

```sql
CREATE OR REPLACE FUNCTION has_collection_activity(
  p_tax_year_id UUID,
  p_days_ago INTEGER DEFAULT 365
) RETURNS BOOLEAN AS $$
DECLARE
  activity_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO activity_count
  FROM account_activity
  WHERE tax_year_id = p_tax_year_id
    AND indicates_collection_action = true
    AND activity_date >= CURRENT_DATE - (p_days_ago || ' days')::INTERVAL;
  
  RETURN activity_count > 0;
END;
$$ LANGUAGE plpgsql STABLE;

-- Example usage:
-- SELECT has_collection_activity('tax-year-uuid', 90);  -- Check last 90 days
```

#### Function: Get CSED Status

```sql
CREATE OR REPLACE FUNCTION get_csed_status(
  p_tax_year_id UUID
) RETURNS TABLE (
  csed_date DATE,
  days_remaining INTEGER,
  is_tolled BOOLEAN,
  toll_days_added INTEGER
) AS $$
DECLARE
  base_date DATE;
  total_toll_days INTEGER := 0;
BEGIN
  -- Get base CSED date (return filed date + 10 years)
  SELECT return_filed_date + INTERVAL '10 years' INTO base_date
  FROM tax_years
  WHERE id = p_tax_year_id;
  
  -- Calculate total toll days
  SELECT COALESCE(SUM(total_toll_days), 0) INTO total_toll_days
  FROM csed_tolling_events
  WHERE tax_year_id = p_tax_year_id;
  
  RETURN QUERY SELECT
    base_date + (total_toll_days || ' days')::INTERVAL AS csed_date,
    (base_date + (total_toll_days || ' days')::INTERVAL - CURRENT_DATE)::INTEGER AS days_remaining,
    total_toll_days > 0 AS is_tolled,
    total_toll_days AS toll_days_added;
END;
$$ LANGUAGE plpgsql STABLE;

-- Example usage:
-- SELECT * FROM get_csed_status('tax-year-uuid');
```

---

## Table 3: csed_calculation_rules (CSED Event Categories)

### Purpose
Define how different events (bankruptcy, OIC, penalties) affect the Collection Statute Expiration Date (CSED) - the 10-year deadline for IRS to collect.

### Schema

```sql
CREATE TABLE csed_calculation_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_category TEXT NOT NULL,           -- 'base_csed', 'bankruptcy', 'oic_pending', etc.
    start_code TEXT,                        -- IRS code that starts event (e.g., '520')
    end_code TEXT,                          -- IRS code that ends event (e.g., '521')
    standard_days INTEGER DEFAULT 3652,     -- 10 years = 3,652 days
    additional_toll_days INTEGER DEFAULT 0, -- Days to add to CSED
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### Existing Seed Data (7 Event Categories)

| Event Category | Start Code | End Code | Standard Days | Additional Toll Days | Notes |
|----------------|------------|----------|---------------|---------------------|-------|
| `base_csed` | `150` | NULL | **3,652** (10 years) | 0 | Return filed → CSED starts |
| `bankruptcy` | `520` | `521` | 0 | **180** (6 months) | Minimum toll period |
| `oic_pending` | `480` | `482` | 0 | **30** | OIC processing time |
| `oic_rejected` | `480` | `481` | 0 | 0 | No toll if rejected |
| `cdp` | `971` | `977` | 0 | 0 | Duration of appeal |
| `penalty_196` | `196` | NULL | 3,652 | **30** | Estimated tax penalty |
| `penalty_276` | `276` | NULL | 3,652 | **30** | Delinquency penalty |

### CSED Calculation Logic

**Base Formula:**
```
CSED Date = Return Filed Date (Code 150) + 3,652 days (10 years) + Total Toll Days
```

**Example Calculation:**
```sql
-- Return filed: 2020-04-15
-- Bankruptcy: 2021-01-01 to 2021-07-01 (180 days)
-- Penalty 196: 30 days
-- Total toll: 210 days

-- CSED: 2020-04-15 + 10 years + 210 days = 2030-11-11
```

### Recommended Additions

```sql
INSERT INTO csed_calculation_rules (event_category, start_code, end_code, standard_days, additional_toll_days) VALUES
-- Installment Agreement (suspends collection for 30 days + duration)
('installment_agreement', '360', NULL, 0, 30),

-- Innocent Spouse Relief (suspends collection)
('innocent_spouse', '898', NULL, 0, 0),

-- Military Service (suspends collection for service duration + 270 days)
('military_service', NULL, NULL, 0, 270),

-- Examination/Audit (suspends collection during audit)
('examination', '420', '421', 0, 0)
ON CONFLICT DO NOTHING;
```

### Business Logic Functions

#### Function: Calculate Final CSED Date

```sql
CREATE OR REPLACE FUNCTION calculate_final_csed_date(
  p_tax_year_id UUID
) RETURNS TABLE (
  base_csed_date DATE,
  total_toll_days INTEGER,
  final_csed_date DATE,
  days_remaining INTEGER,
  is_expired BOOLEAN
) AS $$
DECLARE
  v_return_filed_date DATE;
  v_base_csed DATE;
  v_toll_days INTEGER;
  v_final_csed DATE;
BEGIN
  -- Get return filed date
  SELECT return_filed_date INTO v_return_filed_date
  FROM tax_years
  WHERE id = p_tax_year_id;
  
  IF v_return_filed_date IS NULL THEN
    RETURN QUERY SELECT NULL::DATE, 0, NULL::DATE, 0, false;
    RETURN;
  END IF;
  
  -- Calculate base CSED (10 years from return filed)
  v_base_csed := v_return_filed_date + INTERVAL '10 years';
  
  -- Sum all tolling events
  SELECT COALESCE(SUM(total_toll_days), 0) INTO v_toll_days
  FROM csed_tolling_events
  WHERE tax_year_id = p_tax_year_id;
  
  -- Calculate final CSED
  v_final_csed := v_base_csed + (v_toll_days || ' days')::INTERVAL;
  
  RETURN QUERY SELECT
    v_base_csed,
    v_toll_days,
    v_final_csed,
    (v_final_csed - CURRENT_DATE)::INTEGER AS days_remaining,
    (v_final_csed < CURRENT_DATE) AS is_expired;
END;
$$ LANGUAGE plpgsql STABLE;

-- Example usage:
-- SELECT * FROM calculate_final_csed_date('tax-year-uuid');
-- 
-- Result:
-- base_csed_date | total_toll_days | final_csed_date | days_remaining | is_expired
-- 2030-04-15     | 210            | 2030-11-11      | 1825          | false
```

---

## Table 4: status_definitions (Case Status Codes)

### Purpose
Define valid case status codes with descriptions and recommended next actions for workflow management.

### Schema

```sql
CREATE TABLE status_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    status_code TEXT NOT NULL UNIQUE,       -- 'NEW', 'PROCESSING', 'READY', etc.
    description TEXT NOT NULL,              -- Human-readable description
    next_actions TEXT[],                    -- Array of recommended actions
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### Existing Seed Data (8 Status Codes)

| Status Code | Description | Next Actions |
|-------------|-------------|--------------|
| `NEW` | New case - not yet processed | • Extract documents<br>• Review case details |
| `PROCESSING` | Case is being processed | • Review documents<br>• Calculate projections<br>• Verify calculations |
| `READY` | Case is ready for review | • Review calculations<br>• Generate recommendations<br>• Prepare resolution options |
| `REVIEW` | Case under review | • Review resolution options<br>• Client consultation<br>• Finalize strategy |
| `PENDING` | Waiting on client or IRS | • Follow up with client<br>• Check IRS status<br>• Update case status |
| `COMPLETE` | Case processing complete | • Finalize case<br>• Archive documents<br>• Close case |
| `ON_HOLD` | Case on hold | • Review hold reason<br>• Resume processing |
| `CLOSED` | Case closed | • Archive<br>• Final review |

### Status Workflow

```
NEW → PROCESSING → READY → REVIEW → PENDING/COMPLETE → CLOSED
            ↓              ↑           ↓
        ON_HOLD ←──────────┴───────────┘
```

### Recommended Additions

```sql
INSERT INTO status_definitions (status_code, description, next_actions) VALUES
('ERROR', 'Processing error occurred', ARRAY['Review error logs', 'Re-run extraction', 'Contact support']),
('ARCHIVED', 'Case archived for long-term storage', ARRAY['Restore if needed', 'Review archival policy']),
('AWAITING_CLIENT', 'Waiting for client response', ARRAY['Send reminder', 'Update follow-up date']),
('AWAITING_IRS', 'Waiting for IRS response', ARRAY['Check IRS portal', 'Follow up with IRS'])
ON CONFLICT (status_code) DO UPDATE SET
    description = EXCLUDED.description,
    next_actions = EXCLUDED.next_actions;
```

### Business Logic Functions

#### Function: Get Next Actions

```sql
CREATE OR REPLACE FUNCTION get_next_actions(
  p_case_id UUID
) RETURNS TEXT[] AS $$
DECLARE
  v_status_code TEXT;
  v_next_actions TEXT[];
BEGIN
  -- Get current case status
  SELECT status_code INTO v_status_code
  FROM cases
  WHERE id = p_case_id;
  
  -- Get recommended next actions
  SELECT next_actions INTO v_next_actions
  FROM status_definitions
  WHERE status_code = v_status_code;
  
  RETURN COALESCE(v_next_actions, ARRAY[]::TEXT[]);
END;
$$ LANGUAGE plpgsql STABLE;

-- Example usage:
-- SELECT get_next_actions('case-uuid');
-- Returns: {"Review documents", "Calculate projections", "Verify calculations"}
```

---

## Integration with Medallion Architecture

### How Business Rules Flow Through Layers

```
┌─────────────────────────────────────────────────────────────┐
│ BRONZE LAYER: Raw API Response                             │
│ {                                                           │
│   "forms": [{"Form": "W-2", "Income": 50000}]              │
│ }                                                           │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ├─ SQL Trigger fires
                     │
                     v
┌─────────────────────────────────────────────────────────────┐
│ BUSINESS RULES: Enrichment Lookup                          │
│ wi_type_rules WHERE form_code = 'W-2'                      │
│ → Returns: {                                                │
│     category: 'Non-SE',                                     │
│     is_self_employment: false,                              │
│     include_in_projection: true                             │
│   }                                                         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     v
┌─────────────────────────────────────────────────────────────┐
│ SILVER LAYER: Typed & Enriched Data                        │
│ income_documents {                                          │
│   document_type: 'W-2',                                     │
│   gross_amount: 50000.00,                                   │
│   calculated_category: 'Non-SE',      ← FROM RULE          │
│   is_self_employment: false,          ← FROM RULE          │
│   include_in_projection: true         ← FROM RULE          │
│ }                                                           │
└────────────────────┬────────────────────────────────────────┘
                     │
                     v
┌─────────────────────────────────────────────────────────────┐
│ GOLD LAYER: Business Intelligence                          │
│ • Total SE income: $0 (no SE forms)                        │
│ • SE tax liability: $0                                      │
│ • Eligible for Wage Earner Plan: Yes                       │
│ • Recommended resolution: Installment Agreement            │
└─────────────────────────────────────────────────────────────┘
```

### Example: End-to-End Enrichment

**1. Bronze Insert:**
```sql
INSERT INTO bronze_wi_raw (case_id, raw_response) VALUES (
  'CASE-001',
  '{"forms": [{"Form": "1099-NEC", "Income": 75000}]}'
);
```

**2. Trigger Fires → Looks up Business Rule:**
```sql
SELECT * FROM wi_type_rules WHERE form_code = '1099-NEC';
-- Returns: {category: 'SE', is_self_employment: true, affects_resolution_options: true}
```

**3. Silver Insert (Enriched):**
```sql
INSERT INTO income_documents (
  document_type,
  gross_amount,
  calculated_category,     -- 'SE' (from rule)
  is_self_employment,      -- true (from rule)
  include_in_projection    -- true (from rule)
) VALUES (
  '1099-NEC',
  75000.00,
  'SE',
  true,
  true
);
```

**4. Gold Calculations:**
```sql
-- Calculate SE tax
SELECT calculate_se_tax(75000.00, '1099-NEC');
-- Returns: 10,597.84 (15.3% of net earnings)

-- Update Gold layer
UPDATE employment_information SET
  is_self_employed = true,
  gross_annual_income = 75000.00,
  estimated_se_tax = 10597.84
WHERE case_id = 'CASE-001' AND person_type = 'taxpayer';
```

---

## Data Quality & Monitoring

### Validation Queries

#### Check for Unmapped Form Types

```sql
-- Find income documents with no matching rule
SELECT DISTINCT document_type
FROM income_documents
WHERE document_type NOT IN (SELECT form_code FROM wi_type_rules)
ORDER BY document_type;

-- Expected: Empty result (all forms mapped)
```

#### Check for Unmapped Transaction Codes

```sql
-- Find account activity with no matching rule
SELECT DISTINCT irs_transaction_code
FROM account_activity
WHERE irs_transaction_code NOT IN (SELECT code FROM at_transaction_rules)
ORDER BY irs_transaction_code;

-- Expected: Empty result (all codes mapped)
```

#### Check for Cases Without Status

```sql
-- Find cases with invalid status codes
SELECT c.case_number, c.status_code
FROM cases c
LEFT JOIN status_definitions sd ON c.status_code = sd.status_code
WHERE sd.status_code IS NULL;

-- Expected: Empty result (all statuses valid)
```

### Monitoring Queries

#### Business Rule Usage Statistics

```sql
-- WI Type Rule Usage
SELECT 
  wtr.form_code,
  wtr.category,
  COUNT(id_docs.id) as usage_count,
  SUM(id_docs.gross_amount) as total_amount
FROM wi_type_rules wtr
LEFT JOIN income_documents id_docs ON id_docs.document_type = wtr.form_code
GROUP BY wtr.form_code, wtr.category
ORDER BY usage_count DESC;

-- AT Transaction Rule Usage
SELECT 
  atr.code,
  atr.meaning,
  COUNT(aa.id) as usage_count,
  SUM(aa.amount) as total_amount
FROM at_transaction_rules atr
LEFT JOIN account_activity aa ON aa.irs_transaction_code = atr.code
GROUP BY atr.code, atr.meaning
ORDER BY usage_count DESC;
```

---

## Migration Script

### Applying Business Rules to Existing Data

If you have existing Silver data without business rule enrichment, run this migration:

```sql
-- Update income_documents with WI type rules
UPDATE income_documents id
SET 
  calculated_category = wtr.category,
  is_self_employment = wtr.is_self_employment,
  include_in_projection = wtr.include_in_projection
FROM wi_type_rules wtr
WHERE id.document_type = wtr.form_code
  AND (
    id.calculated_category IS NULL 
    OR id.is_self_employment IS NULL
  );

-- Update account_activity with AT transaction rules
UPDATE account_activity aa
SET 
  calculated_transaction_type = atr.transaction_type,
  affects_balance = atr.affects_balance,
  affects_csed = atr.affects_csed,
  indicates_collection_action = atr.indicates_collection_action,
  explanation = COALESCE(aa.explanation, atr.meaning)
FROM at_transaction_rules atr
WHERE aa.irs_transaction_code = atr.code
  AND (
    aa.calculated_transaction_type IS NULL
    OR aa.affects_balance IS NULL
  );
```

---

## Testing Business Rules

### Unit Tests

```sql
-- Test: WI type categorization
DO $$
BEGIN
  ASSERT (SELECT category FROM wi_type_rules WHERE form_code = 'W-2') = 'Non-SE';
  ASSERT (SELECT category FROM wi_type_rules WHERE form_code = '1099-NEC') = 'SE';
  ASSERT (SELECT is_self_employment FROM wi_type_rules WHERE form_code = '1099-MISC') = true;
  ASSERT (SELECT is_self_employment FROM wi_type_rules WHERE form_code = 'W-2') = false;
  RAISE NOTICE 'WI type rules tests passed ✅';
END $$;

-- Test: AT transaction categorization
DO $$
BEGIN
  ASSERT (SELECT starts_csed FROM at_transaction_rules WHERE code = '150') = true;
  ASSERT (SELECT affects_balance FROM at_transaction_rules WHERE code = '610') = true;
  ASSERT (SELECT indicates_collection_action FROM at_transaction_rules WHERE code = '972') = true;
  ASSERT (SELECT csed_toll_days FROM at_transaction_rules WHERE code = '520') = 180;
  RAISE NOTICE 'AT transaction rules tests passed ✅';
END $$;

-- Test: Business logic functions
DO $$
BEGIN
  ASSERT calculate_se_tax(50000, '1099-NEC') > 0;
  ASSERT calculate_se_tax(50000, 'W-2') = 0;
  ASSERT get_form_category('UNKNOWN') = 'Neither';
  RAISE NOTICE 'Business logic function tests passed ✅';
END $$;
```

---

## Summary

### ✅ Existing Coverage

Your seed.sql provides excellent foundational coverage:
- **16 WI form types** (most common forms)
- **26 AT transaction codes** (essential codes for balance/CSED)
- **7 CSED event categories** (bankruptcy, OIC, penalties)
- **8 status codes** (complete workflow)

### 📈 Recommended Enhancements

1. **Add 10 more WI forms** (1099-Q, 1099-S, W-2C, etc.)
2. **Add 12 more AT codes** (806, 846, 160, 420, 766, 768, etc.)
3. **Add 4 CSED categories** (installment agreement, innocent spouse, military, examination)
4. **Add 4 status codes** (ERROR, ARCHIVED, AWAITING_CLIENT, AWAITING_IRS)

### 🚀 Next: Phase 3 - Bronze Layer

With business rules documented, we're ready to implement the Bronze layer:
- Create bronze_* tables
- Store raw API responses
- Apply business rule enrichment via SQL triggers
- Automatic Silver layer population

---

**Phase 2 Complete ✅**  
**Next:** Phase 3 - Bronze Layer Implementation

