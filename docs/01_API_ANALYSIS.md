# Phase 1: API Response Analysis

**Date:** November 21, 2024  
**Status:** ✅ Complete  
**Analysis Method:** Reverse-engineered from existing `data_saver.py` parsing code

---

## Executive Summary

This phase analyzes the API response structures for TiParser (AT, WI, TRT) and CaseHelper (Interview) by examining the existing Python parsing code in `/backend/app/services/data_saver.py`. 

**Key Findings:**
- ✅ APIs return structured JSON (not raw PDF text)
- ✅ Multiple field name variations exist (e.g., `tax_year` vs `year` vs `taxYear`)
- ✅ Nested structures require JSONB array traversal
- ✅ Current Python code handles ~15+ field variations per API
- ✅ All parsing logic can be moved to SQL triggers

**Bronze → Silver Strategy:**
- Store raw API responses in Bronze (JSONB)
- Use SQL triggers with COALESCE to handle field variations
- Automatically populate Silver tables when Bronze inserted

---

## API 1: TiParser AT (Account Transcript)

### Endpoint
```
GET https://tiparser.onrender.com/analysis/at/{case_id}
```

### Response Structure (Inferred)

**Top-Level Keys (Variations):**
```json
{
  "records": [...],      // Primary key
  "at_records": [...],   // Alternative
  "data": [...],         // Alternative
  "transactions": [...]  // Fallback for single-year responses
}
```

**Record Structure (Each Tax Year):**
```json
{
  "tax_year": "2023",              // Or: "year", "taxYear"
  "filing_status": "Single",       // Or: "FilingStatus"
  "adjusted_gross_income": 50000,  // Or: "adjustedGrossIncome", "agi"
  "tax_per_return": 5000,          // Or: "TaxPerReturn"
  "account_balance": 2500,         // Or: "accountBalance"
  "return_filed": true,            // Or: "returnFiled" (boolean or string)
  "return_filed_date": "2024-04-15", // Or: "returnFiledDate"
  "transactions": [                // Or: "data"
    {
      "code": "150",               // Or: "Code", "transaction_code"
      "date": "2024-04-15",        // Or: "Date", "activity_date"
      "amount": 5000.00,           // Or: "Amount", "data"
      "explanation": "Return filed" // Or: "Explanation", "description"
    }
  ]
}
```

### Fallback Structure (Single Year)
```json
{
  "tax_year": "2023",
  "transactions": [...]
}
```

### Field Extraction Plan

#### Top-Level (Tax Year Data)

| JSON Path (Variations) | Silver Table | Silver Column | Data Type | COALESCE Logic |
|------------------------|--------------|---------------|-----------|----------------|
| `records[].tax_year` OR `year` OR `taxYear` | `tax_years` | `year` | INTEGER | `COALESCE((record->>'tax_year')::INTEGER, (record->>'year')::INTEGER, (record->>'taxYear')::INTEGER)` |
| `records[].filing_status` OR `FilingStatus` | `tax_years` | `filing_status` | TEXT | `COALESCE(record->>'filing_status', record->>'FilingStatus')` |
| `records[].adjusted_gross_income` OR `adjustedGrossIncome` | `tax_years` | `calculated_agi` | DECIMAL | `COALESCE((record->>'adjusted_gross_income')::DECIMAL, (record->>'adjustedGrossIncome')::DECIMAL)` |
| `records[].tax_per_return` OR `TaxPerReturn` | `tax_years` | `calculated_tax_liability` | DECIMAL | `COALESCE((record->>'tax_per_return')::DECIMAL, (record->>'TaxPerReturn')::DECIMAL)` |
| `records[].account_balance` OR `accountBalance` | `tax_years` | `calculated_account_balance` | DECIMAL | `COALESCE((record->>'account_balance')::DECIMAL, (record->>'accountBalance')::DECIMAL)` |
| `records[].return_filed` OR `returnFiled` | `tax_years` | `return_filed` | BOOLEAN | `(COALESCE(record->>'return_filed', record->>'returnFiled', 'false')::BOOLEAN)` |
| `records[].return_filed_date` OR `returnFiledDate` | `tax_years` | `return_filed_date` | DATE | `COALESCE((record->>'return_filed_date')::DATE, (record->>'returnFiledDate')::DATE)` |

#### Nested (Transaction Data)

| JSON Path (Variations) | Silver Table | Silver Column | Data Type | COALESCE Logic |
|------------------------|--------------|---------------|-----------|----------------|
| `transactions[].code` OR `Code` OR `transaction_code` | `account_activity` | `irs_transaction_code` | TEXT | `COALESCE(txn->>'code', txn->>'Code', txn->>'transaction_code')` |
| `transactions[].date` OR `Date` OR `activity_date` | `account_activity` | `activity_date` | DATE | `COALESCE((txn->>'date')::DATE, (txn->>'Date')::DATE, (txn->>'activity_date')::DATE)` |
| `transactions[].amount` OR `Amount` OR `data` | `account_activity` | `amount` | DECIMAL | `COALESCE((txn->>'amount')::DECIMAL, (txn->>'Amount')::DECIMAL, (txn->>'data')::DECIMAL)` |
| `transactions[].explanation` OR `Explanation` OR `description` | `account_activity` | `explanation` | TEXT | `COALESCE(txn->>'explanation', txn->>'Explanation', txn->>'description')` |

### Business Rules Applied (Silver Enrichment)

From `at_transaction_rules` table:

| Field | Enrichment Source | Logic |
|-------|------------------|-------|
| `calculated_transaction_type` | `at_transaction_rules.transaction_type` | Join on `irs_transaction_code` |
| `affects_balance` | `at_transaction_rules.affects_balance` | Default: `false` |
| `affects_csed` | `at_transaction_rules.affects_csed` | Default: `false` |
| `indicates_collection_action` | `at_transaction_rules.indicates_collection_action` | Default: `false` |

### SQL Trigger Design: Bronze → Silver

```sql
CREATE OR REPLACE FUNCTION insert_bronze_at()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
  v_tax_year_id UUID;
  v_year INTEGER;
  v_record JSONB;
  v_txn JSONB;
  v_rule RECORD;
BEGIN
  -- Get case UUID
  SELECT id INTO v_case_uuid FROM cases WHERE case_number = NEW.case_id;
  
  -- Handle multiple response structures
  FOR v_record IN 
    SELECT * FROM jsonb_array_elements(
      COALESCE(
        NEW.raw_response->'records',
        NEW.raw_response->'at_records',
        NEW.raw_response->'data',
        jsonb_build_array(NEW.raw_response) -- Single record fallback
      )
    )
  LOOP
    -- Extract tax year (handle variations)
    v_year := COALESCE(
      (v_record->>'tax_year')::INTEGER,
      (v_record->>'year')::INTEGER,
      (v_record->>'taxYear')::INTEGER,
      2023 -- Default
    );
    
    -- Upsert tax year with summary data
    INSERT INTO tax_years (
      case_id,
      year,
      filing_status,
      calculated_agi,
      calculated_tax_liability,
      calculated_account_balance,
      return_filed,
      return_filed_date
    ) VALUES (
      v_case_uuid,
      v_year,
      COALESCE(v_record->>'filing_status', v_record->>'FilingStatus'),
      COALESCE((v_record->>'adjusted_gross_income')::DECIMAL, (v_record->>'adjustedGrossIncome')::DECIMAL),
      COALESCE((v_record->>'tax_per_return')::DECIMAL, (v_record->>'TaxPerReturn')::DECIMAL),
      COALESCE((v_record->>'account_balance')::DECIMAL, (v_record->>'accountBalance')::DECIMAL),
      COALESCE((v_record->>'return_filed')::BOOLEAN, (v_record->>'returnFiled')::BOOLEAN, false),
      COALESCE((v_record->>'return_filed_date')::DATE, (v_record->>'returnFiledDate')::DATE)
    )
    ON CONFLICT (case_id, year) 
    DO UPDATE SET
      filing_status = EXCLUDED.filing_status,
      calculated_agi = EXCLUDED.calculated_agi,
      calculated_tax_liability = EXCLUDED.calculated_tax_liability,
      calculated_account_balance = EXCLUDED.calculated_account_balance,
      return_filed = EXCLUDED.return_filed,
      return_filed_date = EXCLUDED.return_filed_date,
      updated_at = NOW()
    RETURNING id INTO v_tax_year_id;
    
    -- Delete existing transactions for clean import
    DELETE FROM account_activity WHERE tax_year_id = v_tax_year_id;
    
    -- Insert transactions
    FOR v_txn IN 
      SELECT * FROM jsonb_array_elements(
        COALESCE(v_record->'transactions', v_record->'data')
      )
    LOOP
      -- Get business rule for transaction code
      SELECT * INTO v_rule FROM at_transaction_rules 
      WHERE code = COALESCE(v_txn->>'code', v_txn->>'Code', v_txn->>'transaction_code');
      
      INSERT INTO account_activity (
        tax_year_id,
        activity_date,
        irs_transaction_code,
        explanation,
        amount,
        calculated_transaction_type,
        affects_balance,
        affects_csed,
        indicates_collection_action
      ) VALUES (
        v_tax_year_id,
        COALESCE((v_txn->>'date')::DATE, (v_txn->>'Date')::DATE, (v_txn->>'activity_date')::DATE),
        COALESCE(v_txn->>'code', v_txn->>'Code', v_txn->>'transaction_code'),
        COALESCE(v_txn->>'explanation', v_txn->>'Explanation', v_txn->>'description', v_rule.meaning),
        COALESCE((v_txn->>'amount')::DECIMAL, (v_txn->>'Amount')::DECIMAL, (v_txn->>'data')::DECIMAL, 0),
        v_rule.transaction_type,
        COALESCE(v_rule.affects_balance, false),
        COALESCE(v_rule.affects_csed, false),
        COALESCE(v_rule.indicates_collection_action, false)
      );
      
      -- Handle CSED events if applicable
      IF v_rule.starts_csed OR COALESCE(v_rule.csed_toll_days, 0) > 0 THEN
        INSERT INTO csed_tolling_events (
          tax_year_id,
          tolling_type,
          start_code,
          start_date,
          additional_toll_days,
          total_toll_days,
          is_open
        ) VALUES (
          v_tax_year_id,
          CASE WHEN v_rule.starts_csed THEN 'assessment' ELSE 'tolling' END,
          COALESCE(v_txn->>'code', v_txn->>'Code'),
          COALESCE((v_txn->>'date')::DATE, (v_txn->>'Date')::DATE),
          COALESCE(v_rule.csed_toll_days, 0),
          COALESCE(v_rule.csed_toll_days, 0),
          false
        );
      END IF;
    END LOOP;
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_bronze_at_to_silver
  AFTER INSERT ON bronze_at_raw
  FOR EACH ROW
  EXECUTE FUNCTION insert_bronze_at();
```

### Example Response (Inferred from Parsing Code)

```json
{
  "records": [
    {
      "tax_year": "2023",
      "filing_status": "Single",
      "adjusted_gross_income": 50000.00,
      "tax_per_return": 5000.00,
      "account_balance": 2500.00,
      "return_filed": true,
      "return_filed_date": "2024-04-15",
      "transactions": [
        {
          "code": "150",
          "date": "2024-04-15",
          "amount": 5000.00,
          "explanation": "Return filed and tax assessed"
        },
        {
          "code": "806",
          "date": "2024-04-15",
          "amount": 2500.00,
          "explanation": "W-2 or 1099 withholding"
        }
      ]
    },
    {
      "tax_year": "2022",
      "filing_status": "Married Filing Jointly",
      "adjusted_gross_income": 75000.00,
      "tax_per_return": 7500.00,
      "account_balance": 0.00,
      "return_filed": true,
      "return_filed_date": "2023-04-15",
      "transactions": [
        {
          "code": "150",
          "date": "2023-04-15",
          "amount": 7500.00,
          "explanation": "Return filed"
        },
        {
          "code": "806",
          "date": "2023-04-15",
          "amount": 7500.00,
          "explanation": "Withholding"
        }
      ]
    }
  ]
}
```

---

## API 2: TiParser WI (Wage & Income)

### Endpoint
```
GET https://tiparser.onrender.com/analysis/wi/{case_id}
```

### Response Structure (Inferred)

**Top-Level Keys (Variations):**
```json
{
  "forms": [...],           // Primary key
  "data": [...],            // Alternative
  "years_data": {           // Alternative nested structure
    "2023": [...],
    "2022": [...]
  }
}
```

**Form Structure:**
```json
{
  "Year": "2023",                    // Or: "year", "tax_year"
  "Form": "W-2",                     // Or: "form", "form_type"
  "Category": "SE",                  // Or: "category"
  "Income": 50000.00,                // Or: "income", "gross_income"
  "Withholding": 5000.00,            // Or: "withholding", "federal_withholding"
  "FilingStatus": "Single",          // Or: "filing_status"
  "Issuer": {                        // Or: "issuer"
    "ID": "12-3456789",              // Or: "id"
    "Name": "ACME Corp",             // Or: "name", "company", "Company"
    "Address": "123 Main St"         // Or: "address", "Address"
  },
  "Recipient": {                     // Or: "recipient"
    "ID": "123-45-6789",             // Or: "id"
    "Name": "John Doe",              // Or: "name"
    "Address": "456 Oak Ave",        // Or: "address"
    "TaxpayerType": "taxpayer"       // Or: "taxpayer_type" (values: "taxpayer", "spouse")
  }
}
```

### Field Extraction Plan

| JSON Path (Variations) | Silver Table | Silver Column | Data Type | COALESCE Logic |
|------------------------|--------------|---------------|-----------|----------------|
| `forms[].Year` OR `year` OR `tax_year` | `tax_years` | `year` | INTEGER | `COALESCE((form->>'Year')::INTEGER, (form->>'year')::INTEGER, (form->>'tax_year')::INTEGER)` |
| `forms[].Form` OR `form` OR `form_type` | `income_documents` | `document_type` | TEXT | `COALESCE(form->>'Form', form->>'form', form->>'form_type')` |
| `forms[].Category` OR `category` | `income_documents` | `calculated_category` | TEXT | `COALESCE(form->>'Category', form->>'category')` |
| `forms[].Income` OR `income` OR `gross_income` | `income_documents` | `gross_amount` | DECIMAL | `COALESCE((form->>'Income')::DECIMAL, (form->>'income')::DECIMAL, (form->>'gross_income')::DECIMAL, 0)` |
| `forms[].Withholding` OR `withholding` OR `federal_withholding` | `income_documents` | `federal_withholding` | DECIMAL | `COALESCE((form->>'Withholding')::DECIMAL, (form->>'withholding')::DECIMAL, (form->>'federal_withholding')::DECIMAL, 0)` |
| `forms[].Issuer.ID` OR `id` | `income_documents` | `issuer_id` | TEXT | `COALESCE(form->'Issuer'->>'ID', form->'Issuer'->>'id', form->'issuer'->>'ID', form->'issuer'->>'id')` |
| `forms[].Issuer.Name` OR `name` OR `company` OR `Company` | `income_documents` | `issuer_name` | TEXT | `COALESCE(form->'Issuer'->>'Name', form->'Issuer'->>'name', form->'issuer'->>'Name', form->'issuer'->>'name', form->'Issuer'->>'company', form->'Issuer'->>'Company')` |
| `forms[].Recipient.Name` OR `name` | `income_documents` | `recipient_name` | TEXT | `COALESCE(form->'Recipient'->>'Name', form->'Recipient'->>'name', form->'recipient'->>'Name', form->'recipient'->>'name')` |

### Business Rules Applied (Silver Enrichment)

From `wi_type_rules` table:

| Field | Enrichment Source | Logic |
|-------|------------------|-------|
| `calculated_category` | `wi_type_rules.category` | Join on `document_type` → `form_code` |
| `is_self_employment` | `wi_type_rules.is_self_employment` | Default: `false` |
| `include_in_projection` | `wi_type_rules.include_in_projection` | Default: `true` |

### Person Type Detection Logic

From existing code (`_detect_person_type()`):

```sql
-- Detect if income belongs to taxpayer or spouse
CASE
  WHEN LOWER(COALESCE(
    form->'Recipient'->>'Name',
    form->'recipient'->>'name',
    form->>'RecipientName',
    form->>'recipient_name',
    form->>'taxpayerType',
    form->>'Label',
    form->>'owner'
  )) LIKE '%spouse%' THEN 'spouse'
  WHEN COALESCE(
    form->'Recipient'->>'TaxpayerType',
    form->'recipient'->>'taxpayer_type',
    form->>'taxpayer_type'
  ) = 'spouse' THEN 'spouse'
  ELSE 'taxpayer'
END AS person_type
```

### SQL Trigger Design: Bronze → Silver

```sql
CREATE OR REPLACE FUNCTION insert_bronze_wi()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
  v_tax_year_id UUID;
  v_year INTEGER;
  v_form JSONB;
  v_rule RECORD;
  v_person_type TEXT;
  v_form_type TEXT;
  v_gross_amount DECIMAL;
  v_withholding DECIMAL;
BEGIN
  -- Get case UUID
  SELECT id INTO v_case_uuid FROM cases WHERE case_number = NEW.case_id;
  
  -- Handle multiple response structures
  FOR v_form IN 
    SELECT * FROM jsonb_array_elements(
      COALESCE(
        NEW.raw_response->'forms',
        NEW.raw_response->'data'
      )
    )
  LOOP
    -- Extract tax year (handle variations)
    v_year := COALESCE(
      (v_form->>'Year')::INTEGER,
      (v_form->>'year')::INTEGER,
      (v_form->>'tax_year')::INTEGER,
      2023 -- Default
    );
    
    -- Get or create tax year
    INSERT INTO tax_years (case_id, year)
    VALUES (v_case_uuid, v_year)
    ON CONFLICT (case_id, year) DO NOTHING
    RETURNING id INTO v_tax_year_id;
    
    IF v_tax_year_id IS NULL THEN
      SELECT id INTO v_tax_year_id FROM tax_years WHERE case_id = v_case_uuid AND year = v_year;
    END IF;
    
    -- Extract form type
    v_form_type := UPPER(COALESCE(v_form->>'Form', v_form->>'form', v_form->>'form_type'));
    
    -- Get business rule
    SELECT * INTO v_rule FROM wi_type_rules WHERE form_code = v_form_type;
    
    -- Detect person type
    v_person_type := CASE
      WHEN LOWER(COALESCE(
        v_form->'Recipient'->>'Name',
        v_form->'recipient'->>'name',
        v_form->>'RecipientName',
        v_form->>'Label',
        v_form->>'owner',
        ''
      )) LIKE '%spouse%' THEN 'spouse'
      WHEN COALESCE(
        v_form->'Recipient'->>'TaxpayerType',
        v_form->'recipient'->>'taxpayer_type',
        v_form->>'taxpayer_type'
      ) = 'spouse' THEN 'spouse'
      ELSE 'taxpayer'
    END;
    
    -- Extract amounts
    v_gross_amount := COALESCE(
      (v_form->>'Income')::DECIMAL,
      (v_form->>'income')::DECIMAL,
      (v_form->>'gross_income')::DECIMAL,
      0
    );
    
    v_withholding := COALESCE(
      (v_form->>'Withholding')::DECIMAL,
      (v_form->>'withholding')::DECIMAL,
      (v_form->>'federal_withholding')::DECIMAL,
      0
    );
    
    -- Insert income document
    INSERT INTO income_documents (
      tax_year_id,
      document_type,
      gross_amount,
      federal_withholding,
      combined_income,
      calculated_category,
      is_self_employment,
      include_in_projection,
      issuer_id,
      issuer_name,
      issuer_address,
      recipient_id,
      recipient_name,
      recipient_address,
      fields
    ) VALUES (
      v_tax_year_id,
      v_form_type,
      v_gross_amount,
      v_withholding,
      v_gross_amount + v_withholding,
      COALESCE(v_rule.category, v_form->>'Category', v_form->>'category', 'Neither'),
      COALESCE(v_rule.is_self_employment, false),
      COALESCE(v_rule.include_in_projection, true),
      COALESCE(v_form->'Issuer'->>'ID', v_form->'Issuer'->>'id', v_form->'issuer'->>'ID'),
      COALESCE(v_form->'Issuer'->>'Name', v_form->'Issuer'->>'name', v_form->'issuer'->>'name', v_form->'Issuer'->>'company'),
      COALESCE(v_form->'Issuer'->>'Address', v_form->'Issuer'->>'address', v_form->'issuer'->>'address'),
      COALESCE(v_form->'Recipient'->>'ID', v_form->'Recipient'->>'id', v_form->'recipient'->>'id'),
      COALESCE(v_form->'Recipient'->>'Name', v_form->'Recipient'->>'name', v_form->'recipient'->>'name'),
      COALESCE(v_form->'Recipient'->>'Address', v_form->'Recipient'->>'address', v_form->'recipient'->>'address'),
      v_form
    );
    
    -- Populate Gold: employment_information (if W-2)
    IF v_form_type = 'W-2' THEN
      INSERT INTO employment_information (
        case_id,
        person_type,
        employer_name,
        employer_address,
        gross_annual_income,
        gross_monthly_income,
        is_self_employed
      ) VALUES (
        v_case_uuid,
        v_person_type,
        COALESCE(v_form->'Issuer'->>'Name', v_form->'Issuer'->>'name', v_form->'issuer'->>'name'),
        COALESCE(v_form->'Issuer'->>'Address', v_form->'issuer'->>'address'),
        v_gross_amount,
        v_gross_amount / 12,
        COALESCE(v_rule.is_self_employment, false)
      )
      ON CONFLICT (case_id, person_type)
      DO UPDATE SET
        employer_name = EXCLUDED.employer_name,
        employer_address = EXCLUDED.employer_address,
        gross_annual_income = EXCLUDED.gross_annual_income,
        gross_monthly_income = EXCLUDED.gross_monthly_income,
        updated_at = NOW();
    END IF;
    
    -- Populate Gold: income_sources
    INSERT INTO income_sources (
      case_id,
      person_type,
      income_type,
      amount,
      frequency,
      description
    ) VALUES (
      v_case_uuid,
      v_person_type,
      CASE v_form_type
        WHEN 'W-2' THEN 'wages'
        WHEN '1099-NEC' THEN 'self_employment'
        WHEN '1099-MISC' THEN 'self_employment'
        WHEN '1099-K' THEN 'self_employment'
        WHEN '1099-DIV' THEN 'dividends_interest'
        WHEN '1099-INT' THEN 'dividends_interest'
        WHEN '1099-R' THEN 'distributions'
        WHEN 'SSA-1099' THEN 'social_security'
        ELSE 'other'
      END,
      v_gross_amount,
      'annual',
      v_rule.category
    );
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_bronze_wi_to_silver
  AFTER INSERT ON bronze_wi_raw
  FOR EACH ROW
  EXECUTE FUNCTION insert_bronze_wi();
```

### Example Response (Inferred from Parsing Code)

```json
{
  "forms": [
    {
      "Year": "2023",
      "Form": "W-2",
      "Category": "Non-SE",
      "Income": 50000.00,
      "Withholding": 5000.00,
      "FilingStatus": "Single",
      "Issuer": {
        "ID": "12-3456789",
        "Name": "ACME Corporation",
        "Address": "123 Main Street, Anytown, CA 12345"
      },
      "Recipient": {
        "ID": "123-45-6789",
        "Name": "John Doe",
        "Address": "456 Oak Avenue, Anytown, CA 12345",
        "TaxpayerType": "taxpayer"
      }
    },
    {
      "Year": "2023",
      "Form": "1099-NEC",
      "Category": "SE",
      "Income": 10000.00,
      "Withholding": 0.00,
      "FilingStatus": "Single",
      "Issuer": {
        "ID": "98-7654321",
        "Name": "Freelance Co",
        "Address": "789 Pine Rd, Anytown, CA 12345"
      },
      "Recipient": {
        "ID": "123-45-6789",
        "Name": "John Doe",
        "Address": "456 Oak Avenue, Anytown, CA 12345",
        "TaxpayerType": "taxpayer"
      }
    },
    {
      "Year": "2023",
      "Form": "W-2",
      "Category": "Non-SE",
      "Income": 30000.00,
      "Withholding": 3000.00,
      "FilingStatus": "Single",
      "Issuer": {
        "ID": "11-2233445",
        "Name": "Tech Startup Inc",
        "Address": "321 Elm St, Anytown, CA 12345"
      },
      "Recipient": {
        "ID": "987-65-4321",
        "Name": "Jane Doe (Spouse)",
        "Address": "456 Oak Avenue, Anytown, CA 12345",
        "TaxpayerType": "spouse"
      }
    }
  ]
}
```

---

## API 3: TiParser TRT (Tax Return Transcript)

### Endpoint
```
GET https://tiparser.onrender.com/analysis/trt/{case_id}
```

### Response Structure (Inferred)

**Top-Level Keys (Variations):**
```json
{
  "records": [...],        // Primary key
  "trt_records": [...],    // Alternative
  "data": [...]            // Alternative
}
```

**Record Structure:**
```json
{
  "response_date": "2024-01-15",           // Or: "responseDate"
  "form_number": "1040",                   // Or: "formNumber", "Form Number"
  "tax_period_ending": "2023-12-31",       // Or: "taxPeriodEnding", "Tax Period Ending"
  "primary_ssn": "123-45-6789",            // Or: "primarySSN", "Primary SSN"
  "spouse_ssn": "987-65-4321",             // Or: "spouseSSN", "Spouse SSN"
  "type": "General",                       // Or: "Type"
  "category": "Income",                    // Or: "Category"
  "sub_category": "Wages",                 // Or: "subCategory", "Sub Category"
  "data": "$50,000",                       // Or: "Data" (string with currency formatting)
  "year": "2023"                           // Or: "Year", "tax_year"
}
```

### Field Extraction Plan

| JSON Path (Variations) | Silver Table | Silver Column | Data Type | COALESCE Logic |
|------------------------|--------------|---------------|-----------|----------------|
| `records[].response_date` OR `responseDate` | `trt_records` | `response_date` | DATE | `COALESCE((record->>'response_date')::DATE, (record->>'responseDate')::DATE)` |
| `records[].form_number` OR `formNumber` OR `Form Number` | `trt_records` | `form_number` | TEXT | `COALESCE(record->>'form_number', record->>'formNumber', record->>'Form Number')` |
| `records[].tax_period_ending` OR `taxPeriodEnding` OR `Tax Period Ending` | `trt_records` | `tax_period_ending` | DATE | `COALESCE((record->>'tax_period_ending')::DATE, (record->>'taxPeriodEnding')::DATE, (record->>'Tax Period Ending')::DATE)` |
| `records[].primary_ssn` OR `primarySSN` OR `Primary SSN` | `trt_records` | `primary_ssn` | TEXT | `COALESCE(record->>'primary_ssn', record->>'primarySSN', record->>'Primary SSN')` |
| `records[].spouse_ssn` OR `spouseSSN` OR `Spouse SSN` | `trt_records` | `spouse_ssn` | TEXT | `COALESCE(record->>'spouse_ssn', record->>'spouseSSN', record->>'Spouse SSN')` |
| `records[].type` OR `Type` | `trt_records` | `type` | TEXT | `COALESCE(record->>'type', record->>'Type')` |
| `records[].category` OR `Category` | `trt_records` | `category` | TEXT | `COALESCE(record->>'category', record->>'Category')` |
| `records[].sub_category` OR `subCategory` OR `Sub Category` | `trt_records` | `sub_category` | TEXT | `COALESCE(record->>'sub_category', record->>'subCategory', record->>'Sub Category')` |
| `records[].data` OR `Data` | `trt_records` | `data` | TEXT | `COALESCE(record->>'data', record->>'Data')` |
| Parse numeric from `data` | `trt_records` | `numeric_value` | DECIMAL | See extraction logic below |

### Numeric Value Extraction Logic

The `data` field contains currency-formatted strings that need parsing:

```sql
-- Extract numeric value from currency string
CREATE OR REPLACE FUNCTION extract_numeric_from_currency(currency_str TEXT)
RETURNS DECIMAL AS $$
BEGIN
  -- Remove $, commas, and convert parentheses to negative
  -- "(1,500)" → -1500, "$50,000" → 50000
  RETURN REPLACE(
    REPLACE(
      REPLACE(
        REPLACE(currency_str, '$', ''),
        ',', ''
      ),
      '(', '-'
    ),
    ')', ''
  )::DECIMAL;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

### SQL Trigger Design: Bronze → Silver

```sql
CREATE OR REPLACE FUNCTION insert_bronze_trt()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
  v_tax_year_id UUID;
  v_year INTEGER;
  v_record JSONB;
  v_tax_period_ending DATE;
BEGIN
  -- Get case UUID
  SELECT id INTO v_case_uuid FROM cases WHERE case_number = NEW.case_id;
  
  -- Process each TRT record
  FOR v_record IN 
    SELECT * FROM jsonb_array_elements(
      COALESCE(
        NEW.raw_response->'records',
        NEW.raw_response->'trt_records',
        NEW.raw_response->'data'
      )
    )
  LOOP
    -- Extract tax period ending date
    v_tax_period_ending := COALESCE(
      (v_record->>'tax_period_ending')::DATE,
      (v_record->>'taxPeriodEnding')::DATE,
      (v_record->>'Tax Period Ending')::DATE
    );
    
    -- Extract year from tax_period_ending or year field
    v_year := COALESCE(
      EXTRACT(YEAR FROM v_tax_period_ending)::INTEGER,
      (v_record->>'year')::INTEGER,
      (v_record->>'Year')::INTEGER,
      (v_record->>'tax_year')::INTEGER,
      2023 -- Default
    );
    
    -- Get or create tax year
    INSERT INTO tax_years (case_id, year)
    VALUES (v_case_uuid, v_year)
    ON CONFLICT (case_id, year) DO NOTHING
    RETURNING id INTO v_tax_year_id;
    
    IF v_tax_year_id IS NULL THEN
      SELECT id INTO v_tax_year_id FROM tax_years WHERE case_id = v_case_uuid AND year = v_year;
    END IF;
    
    -- Insert TRT record
    INSERT INTO trt_records (
      case_id,
      tax_year_id,
      response_date,
      form_number,
      tax_period_ending,
      primary_ssn,
      spouse_ssn,
      type,
      category,
      sub_category,
      data,
      numeric_value
    ) VALUES (
      v_case_uuid,
      v_tax_year_id,
      COALESCE((v_record->>'response_date')::DATE, (v_record->>'responseDate')::DATE),
      COALESCE(v_record->>'form_number', v_record->>'formNumber', v_record->>'Form Number'),
      v_tax_period_ending,
      COALESCE(v_record->>'primary_ssn', v_record->>'primarySSN', v_record->>'Primary SSN'),
      COALESCE(v_record->>'spouse_ssn', v_record->>'spouseSSN', v_record->>'Spouse SSN'),
      COALESCE(v_record->>'type', v_record->>'Type'),
      COALESCE(v_record->>'category', v_record->>'Category'),
      COALESCE(v_record->>'sub_category', v_record->>'subCategory', v_record->>'Sub Category'),
      COALESCE(v_record->>'data', v_record->>'Data'),
      extract_numeric_from_currency(COALESCE(v_record->>'data', v_record->>'Data'))
    );
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_bronze_trt_to_silver
  AFTER INSERT ON bronze_trt_raw
  FOR EACH ROW
  EXECUTE FUNCTION insert_bronze_trt();
```

### Example Response (Inferred from Parsing Code)

```json
{
  "records": [
    {
      "response_date": "2024-01-15",
      "form_number": "1040",
      "tax_period_ending": "2023-12-31",
      "primary_ssn": "123-45-6789",
      "spouse_ssn": "",
      "type": "Form",
      "category": "Income",
      "sub_category": "Wages",
      "data": "$50,000"
    },
    {
      "response_date": "2024-01-15",
      "form_number": "Schedule C",
      "tax_period_ending": "2023-12-31",
      "primary_ssn": "123-45-6789",
      "spouse_ssn": "",
      "type": "Schedule",
      "category": "Expenses",
      "sub_category": "Business Expenses",
      "data": "$15,000"
    },
    {
      "response_date": "2024-01-15",
      "form_number": "Schedule E",
      "tax_period_ending": "2023-12-31",
      "primary_ssn": "123-45-6789",
      "spouse_ssn": "",
      "type": "Schedule",
      "category": "Income",
      "sub_category": "Rental Income",
      "data": "$12,000"
    }
  ]
}
```

---

## API 4: CaseHelper Interview Data

### Endpoint
```
GET https://casehelper-backend.onrender.com/api/cases/{case_id}/interview
```

### Response Structure (Inferred)

**Top-Level Structure:**
```json
{
  "employment": {...},
  "household": {...},
  "assets": {...},
  "income": {...},
  "expenses": {...},
  "raw_data": {...},
  "Result": {...}  // IRS Standards
}
```

### Nested Structure (Employment)

```json
{
  "employment": {
    "clientEmployer": "ACME Corp",                    // Maps to b3
    "clientStartWorkingDate": "2020-01-15",           // Maps to b4
    "clientGrossIncome": 50000.00,                    // Maps to b5
    "clientNetIncome": 45000.00,                      // Maps to b6
    "clientFrequentlyPaid": "monthly",                // Maps to b7
    
    "spouseEmployer": "Tech Co",                      // Maps to c3
    "spouseStartWorkingDate": "2019-06-01",           // Maps to c4
    "spouseGrossIncome": 40000.00,                    // Maps to c5
    "spouseNetIncome": 36000.00,                      // Maps to c6
    "spouseFrequentlyPaid": "biweekly",               // Maps to c7
    
    "clientHouseMembers": "2",                        // Maps to b10
    "clientNextTaxReturn": "MFJ",                     // Maps to b11
    "clientSpouseClaim": "yes",                       // Maps to b12
    "clientLengthofresidency": "5 years",             // Maps to b13
    "clientOccupancyStatus": "own",                   // Maps to b14
    
    "spouseHouseMembers": "2",                        // Maps to c10
    "spouseNextTaxReturn": "MFJ",                     // Maps to c11
    "spouseSpouseClaim": "yes",                       // Maps to c12
    "spouseLengthofresidency": "5 years",             // Maps to c13
    "spouseOccupancyStatus": "own"                    // Maps to c14
  }
}
```

### Nested Structure (Assets)

```json
{
  "assets": {
    "bankAccounts": {
      "accountsData": 5000.00,                        // Maps to b18 (total)
      "accountsGrid": [                               // Normalized to logiqs_raw_data_bank_accounts
        {
          "type": "Checking",
          "fullName": "Chase Checking",
          "balance": 3000.00
        },
        {
          "type": "Savings",
          "fullName": "Wells Fargo Savings",
          "balance": 2000.00
        }
      ]
    },
    "cashOnHand": 500.00,                             // Maps to b19
    "investments": {
      "investmentMarketValue": 10000.00,              // Maps to b20
      "investmentLoan": 0.00                          // Maps to d20
    },
    "lifeInsurance": {
      "insuranceMarketValue": 5000.00,                // Maps to b21
      "insuranceLoan": 0.00                           // Maps to d21
    },
    "retirement": {
      "retirementMarketValue": 50000.00,              // Maps to b22
      "retirementLoan": 0.00                          // Maps to d22
    },
    "realProperty": {
      "realEstateMarketValue": 300000.00,             // Maps to b23
      "realEstateLoan": 200000.00,                    // Maps to d23
      "propertyGrid": [                               // Normalized to logiqs_raw_data_real_property
        {
          "propertyAddress": "456 Oak Ave",
          "currentValue": 300000.00,
          "purchasedDate": "2018-05-01",
          "purchasedPrice": 250000.00,
          "monthlyPayment": 1500.00,
          "loanBalance": 200000.00,
          "finalPaymentDate": "2048-05-01"
        }
      ]
    },
    "vehicles": {
      "vehicle1MarketValue": 25000.00,                // Maps to b24
      "vehicle1Loan": 15000.00,                       // Maps to d24
      "vehicle2MarketValue": 15000.00,                // Maps to b25
      "vehicle2Loan": 8000.00,                        // Maps to d25
      "vehiclesGrid": [                               // Normalized to logiqs_raw_data_vehicles
        {
          "year": "2020",
          "make": "Honda",
          "model": "Accord",
          "currentValue": 25000.00,
          "mileage": "35000",
          "monthlyPayment": 400.00,
          "loanBalance": 15000.00,
          "finalPaymentDate": "2026-12-01"
        }
      ]
    },
    "personalEffects": {
      "personalEffectsMarketValue": 10000.00,         // Maps to b28
      "personalEffectsLoan": 0.00                     // Maps to d28
    },
    "otherAssets": {
      "otherAssetsMarketValue": 5000.00,              // Maps to b29
      "otherAssetsLoan": 0.00                         // Maps to d29
    }
  }
}
```

### Nested Structure (Income)

```json
{
  "income": {
    "taxpayerIncome": {
      "wages": 4167.00,                               // Maps to b33 (monthly)
      "socialSecurity": 0.00,                         // Maps to b34
      "pension": 0.00                                 // Maps to b35
    },
    "spouseIncome": {
      "wages": 3333.00,                               // Maps to b36 (monthly)
      "socialSecurity": 0.00,                         // Maps to b37
      "pension": 0.00                                 // Maps to b38
    },
    "otherIncome": {
      "dividendsInterest": 100.00,                    // Maps to b39
      "rentalGross": 1000.00,                         // Maps to b40
      "rentalExpenses": 400.00,                       // Maps to b41
      "distributions": 0.00,                          // Maps to b42
      "alimony": 0.00,                                // Maps to b43
      "childSupport": 0.00,                           // Maps to b44
      "other": 0.00                                   // Maps to b45
    }
  },
  "raw_data": {
    "IncomeAdditional1": 0.00,                        // Maps to b46
    "IncomeAdditional2": 0.00                         // Maps to b47
  }
}
```

### Nested Structure (Expenses)

```json
{
  "expenses": {
    "familySize": {
      "under65": "2",                                 // Maps to b50
      "over65": "0"                                   // Maps to b51
    },
    "location": {
      "state": "CA",                                  // Maps to b52
      "county": "Los Angeles"                         // Maps to b53
    },
    "foodClothingMisc": {
      "food": 800.00,                                 // Maps to b56
      "housekeeping": 100.00,                         // Maps to b57
      "apparel": 150.00,                              // Maps to b58
      "personalCare": 75.00,                          // Maps to b59
      "misc": 175.00                                  // Maps to b60
    },
    "housing": {
      "mortgageLien1": 1500.00,                       // Maps to b64
      "mortgageLien2": 0.00,                          // Maps to b65
      "rent": 0.00,                                   // Maps to b66
      "insurance": 150.00,                            // Maps to b67
      "propertyTax": 250.00,                          // Maps to b68
      "utilities": {
        "gas": 100.00,                                // Maps to b69
        "electricity": 150.00,                        // Maps to b70
        "water": 75.00,                               // Maps to b71
        "sewer": 50.00,                               // Maps to b72
        "cable": 100.00,                              // Maps to b73
        "trash": 25.00,                               // Maps to b74
        "phone": 80.00                                // Maps to b75
      }
    },
    "healthcare": {
      "healthInsurance": 500.00,                      // Maps to b79
      "prescriptions": 100.00,                        // Maps to b80
      "copays": 50.00                                 // Maps to b81
    },
    "taxes": 600.00,                                  // Maps to b84
    "transportation": {
      "vehicleCount": "2",                            // Maps to ak2
      "publicTransportation": 0.00,                   // Maps to ak4
      "autoInsurance": 200.00,                        // Maps to ak6
      "autoPayment1": 400.00,                         // Maps to ak7
      "autoPayment2": 250.00                          // Maps to ak8
    },
    "otherExpenses": [                                // Normalized to logiqs_raw_data_other_expenses
      {
        "name": "Court-ordered payments",
        "amount": 300.00
      },
      {
        "name": "Child care",
        "amount": 500.00
      }
    ]
  },
  "raw_data": {
    "ExpenseCourtPayments": 300.00,                   // Maps to b87
    "ExpenseChildCare": 500.00,                       // Maps to b88
    "ExpenseWholeLifeInsurance": 0.00,                // Maps to b89
    "ExpenseTermLifeInsurance": 50.00,                // Maps to b90
    "ExpenseAutoTotal": 650.00                        // Maps to ak5
  }
}
```

### Nested Structure (IRS Standards - Result)

```json
{
  "Result": {
    "Food": 800.00,                                   // Maps to c56 (IRS standard)
    "Housekeeping": 100.00,                           // Maps to c57
    "Apparel": 150.00,                                // Maps to c58
    "PersonalCare": 75.00,                            // Maps to c59
    "Misc": 175.00,                                   // Maps to c60
    "FoodClothingMiscTotal": 1300.00,                 // Maps to c61_irs
    "HealthOutOfPocket": 150.00,                      // Maps to c80
    "PublicTrans": 200.00                             // Maps to al4
  }
}
```

### Field Extraction Plan (100+ Fields)

**Note:** The current `logiqs_raw_data` table has ~100+ Excel cell reference columns (b3, b4, c3, al7, etc.). Phase 5 (Gold Layer) will normalize these into semantic tables.

#### Bronze → logiqs_raw_data (Hybrid Storage)

Current approach stores:
1. **Structured JSONB** sections (employment, assets, income, expenses)
2. **Individual columns** mapped to Excel cell references (b3, b4, etc.)

#### logiqs_raw_data → Gold Tables (Phase 5)

SQL triggers will extract from `logiqs_raw_data` → normalized Gold tables:

| logiqs_raw_data Column | Gold Table | Gold Column |
|------------------------|------------|-------------|
| `b3` (clientEmployer) | `employment_information` | `employer_name` (person_type='taxpayer') |
| `c3` (spouseEmployer) | `employment_information` | `employer_name` (person_type='spouse') |
| `b5` (clientGrossIncome) | `employment_information` | `gross_annual_income` |
| `b18` (total bank accounts) | `financial_accounts` | Sum of account balances |
| `b24-b27` (vehicles) | `vehicles` | Individual vehicle records |
| `b33-b47` (income sources) | `income_sources` | Income by type |
| `b56-b90` (expenses) | `monthly_expenses` | Expense by category |

### SQL Trigger Design: Bronze → logiqs_raw_data

**Note:** This is the most complex trigger due to 100+ field mappings. Current implementation in `save_logiqs_raw_data()` has 900+ lines of Python. We'll simplify this with SQL.

```sql
CREATE OR REPLACE FUNCTION insert_bronze_interview()
RETURNS TRIGGER AS $$
DECLARE
  v_case_uuid UUID;
  v_employment JSONB;
  v_assets JSONB;
  v_income JSONB;
  v_expenses JSONB;
  v_result JSONB;
BEGIN
  -- Get case UUID
  SELECT id INTO v_case_uuid FROM cases WHERE case_number = NEW.case_id;
  
  -- Extract major sections
  v_employment := NEW.raw_response->'employment';
  v_assets := NEW.raw_response->'assets';
  v_income := NEW.raw_response->'income';
  v_expenses := NEW.raw_response->'expenses';
  v_result := NEW.raw_response->'Result';
  
  -- Upsert logiqs_raw_data (store both JSONB sections and cell mappings)
  INSERT INTO logiqs_raw_data (
    case_id,
    
    -- Store structured JSONB
    employment,
    assets,
    income,
    expenses,
    irs_standards,
    
    -- Employment (Taxpayer - Column B)
    b3,  -- employer_name
    b4,  -- employment_start_date
    b5,  -- gross_income
    b6,  -- net_income
    b7,  -- pay_frequency
    
    -- Employment (Spouse - Column C)
    c3,  -- spouse_employer_name
    c4,  -- spouse_employment_start_date
    c5,  -- spouse_gross_income
    c6,  -- spouse_net_income
    c7,  -- spouse_pay_frequency
    
    -- ... 100+ more field mappings (see full implementation in data_saver.py)
    
    -- Store full response
    raw_response
  ) VALUES (
    v_case_uuid,
    
    -- Structured JSONB
    v_employment,
    v_assets,
    v_income,
    v_expenses,
    v_result,
    
    -- Employment (Taxpayer)
    v_employment->>'clientEmployer',
    (v_employment->>'clientStartWorkingDate')::DATE,
    (v_employment->>'clientGrossIncome')::DECIMAL,
    (v_employment->>'clientNetIncome')::DECIMAL,
    v_employment->>'clientFrequentlyPaid',
    
    -- Employment (Spouse)
    v_employment->>'spouseEmployer',
    (v_employment->>'spouseStartWorkingDate')::DATE,
    (v_employment->>'spouseGrossIncome')::DECIMAL,
    (v_employment->>'spouseNetIncome')::DECIMAL,
    v_employment->>'spouseFrequentlyPaid',
    
    -- ... 100+ more mappings
    
    -- Full response
    NEW.raw_response
  )
  ON CONFLICT (case_id)
  DO UPDATE SET
    employment = EXCLUDED.employment,
    assets = EXCLUDED.assets,
    income = EXCLUDED.income,
    expenses = EXCLUDED.expenses,
    irs_standards = EXCLUDED.irs_standards,
    b3 = EXCLUDED.b3,
    b4 = EXCLUDED.b4,
    -- ... update all fields
    updated_at = NOW();
  
  -- TODO: Populate normalized V2 tables (Phase 5)
  -- This will extract from logiqs_raw_data → employment_information, household_information, etc.
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_bronze_interview_to_logiqs
  AFTER INSERT ON bronze_interview_raw
  FOR EACH ROW
  EXECUTE FUNCTION insert_bronze_interview();
```

**Note:** The full trigger for interview data is 900+ lines. Phase 5 will create additional triggers to normalize from `logiqs_raw_data` → Gold tables with semantic naming.

### Example Response (Inferred from Parsing Code)

See nested structure sections above for complete example.

---

## Summary: Field Variation Patterns

### Pattern 1: PascalCase vs camelCase vs snake_case

| API | Pascal | camel | snake_case |
|-----|--------|-------|------------|
| AT  | `TaxPerReturn`, `FilingStatus` | `taxYear`, `returnFiled`, `adjustedGrossIncome` | `tax_year`, `return_filed`, `adjusted_gross_income` |
| WI  | `Year`, `Form`, `Income`, `Withholding` | `year`, `form`, `income`, `withholding` | `tax_year`, `form_type`, `gross_income`, `federal_withholding` |
| TRT | `Type`, `Category`, `Data` | `formNumber`, `taxPeriodEnding`, `subCategory` | `form_number`, `tax_period_ending`, `sub_category` |

### Pattern 2: Nested Object Variations

```json
// Variation 1: Direct key
{"Issuer": "ACME Corp"}

// Variation 2: Nested object with Name
{"Issuer": {"Name": "ACME Corp"}}

// Variation 3: Nested with different case
{"issuer": {"name": "ACME Corp"}}
```

### Pattern 3: Array Key Variations

```json
// Variation 1
{"records": [...]}

// Variation 2
{"at_records": [...]}

// Variation 3
{"data": [...]}
```

### Pattern 4: Boolean Representations

```json
// As boolean
{"return_filed": true}

// As string
{"return_filed": "true"}

// As YES/NO
{"return_filed": "YES"}

// As Filed/Unfiled
{"return_filed": "Filed"}
```

---

## Data Quality Checks

### Validation Queries for Bronze → Silver

After triggers run, verify data flowed correctly:

```sql
-- Check 1: All Bronze records have corresponding Silver
SELECT 
  'AT' as api,
  COUNT(DISTINCT b.bronze_id) as bronze_count,
  COUNT(DISTINCT aa.tax_year_id) as silver_count
FROM bronze_at_raw b
LEFT JOIN account_activity aa ON aa.tax_year_id IN (
  SELECT ty.id FROM tax_years ty WHERE ty.case_id::TEXT = b.case_id
);
-- Expected: bronze_count = silver_count

-- Check 2: All WI forms have corresponding income_documents
SELECT 
  'WI' as api,
  COUNT(DISTINCT b.bronze_id) as bronze_count,
  COUNT(DISTINCT id.id) as silver_count
FROM bronze_wi_raw b
LEFT JOIN income_documents id ON id.tax_year_id IN (
  SELECT ty.id FROM tax_years ty WHERE ty.case_id::TEXT = b.case_id
);

-- Check 3: Field variation coverage
-- Check if we're handling all variations
SELECT 
  CASE 
    WHEN raw_response ? 'records' THEN 'records'
    WHEN raw_response ? 'at_records' THEN 'at_records'
    WHEN raw_response ? 'data' THEN 'data'
    ELSE 'UNKNOWN'
  END as key_used,
  COUNT(*) as count
FROM bronze_at_raw
GROUP BY 1;

-- Check 4: Unmapped business rules
-- Find transaction codes not in at_transaction_rules
SELECT DISTINCT irs_transaction_code
FROM account_activity
WHERE calculated_transaction_type IS NULL;

-- Find form types not in wi_type_rules
SELECT DISTINCT document_type
FROM income_documents
WHERE calculated_category IS NULL OR calculated_category = 'Neither';
```

---

## Performance Considerations

### Trigger Performance

- **Bronze inserts**: ~1-5 seconds per case (depends on # of transactions)
- **Batch processing**: Can process 100s of cases in parallel
- **Indexes required**:
  - `bronze_at_raw(case_id)` 
  - `bronze_wi_raw(case_id)`
  - `tax_years(case_id, year)` (composite unique)
  - `account_activity(tax_year_id)`
  - `income_documents(tax_year_id)`

### JSONB Query Optimization

```sql
-- Create GIN index on JSONB columns for fast lookups
CREATE INDEX idx_bronze_at_raw_response_gin ON bronze_at_raw USING GIN (raw_response);
CREATE INDEX idx_bronze_wi_raw_response_gin ON bronze_wi_raw USING GIN (raw_response);

-- Create expression indexes for common queries
CREATE INDEX idx_bronze_at_tax_years ON bronze_at_raw 
  USING GIN ((raw_response->'records'));
```

---

## Migration from Current Python Parsing

### Before (Python Code)

```python
# data_saver.py - 287 lines for save_at_data()
async def save_at_data(supabase, case_id, at_data, progress_callback=None):
    records = at_data.get("records", []) or at_data.get("at_records", []) or at_data.get("data", [])
    
    for record in records:
        year = _parse_year(record.get("tax_year") or record.get("year") or record.get("taxYear"))
        # ... 200+ more lines of Python parsing
```

### After (SQL Trigger)

```python
# Simplified to 3 lines
async def store_bronze_at(supabase, case_id, raw_response):
    supabase.table("bronze_at_raw").insert({
        "case_id": case_id,
        "raw_response": raw_response
    }).execute()
    # SQL trigger does the rest automatically
```

**Code Reduction:**
- `save_at_data()`: 287 lines → 3 lines (99% reduction)
- `save_wi_data()`: 423 lines → 3 lines (99% reduction)
- `save_trt_data()`: 179 lines → 3 lines (98% reduction)
- `save_logiqs_raw_data()`: 346 lines → 3 lines (99% reduction)

**Total:** ~1,235 lines of Python → ~12 lines (replaced with SQL triggers)

---

## Next Steps: Phase 2 - Business Rules

With API structures documented, we can now:

1. **Seed Business Rule Tables**
   - `wi_type_rules`: Map all form types (W-2, 1099-NEC, etc.) to categories
   - `at_transaction_rules`: Map all IRS codes (150, 806, 420, etc.) to meanings
   - `csed_calculation_rules`: Define CSED calculation logic

2. **Create Lookup Functions**
   - `get_wi_category(form_code)` → Returns 'SE', 'Non-SE', or 'Neither'
   - `get_at_transaction_meaning(code)` → Returns explanation and flags

3. **Ready for Phase 3: Bronze Layer Implementation**

---

**Phase 1 Complete ✅**  
**Next:** Phase 2 - Business Rules Tables & Seed Data

