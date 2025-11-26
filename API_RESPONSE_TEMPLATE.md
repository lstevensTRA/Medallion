# API Response Template

When Cursor asks for API responses during Phase 1, copy this template and fill it in with your actual API data.

---

## TiParser AT (Account Transcript) Response

**Endpoint:** `https://tiparser.com/api/at`  
**Method:** POST  
**Request Body:**
```json
{
  "case_id": "your-case-id-here"
}
```

**Response:**
```json
{
  // PASTE YOUR ACTUAL AT RESPONSE HERE
  // Example structure:
  "case_id": "abc-123",
  "response_date": "2024-01-15",
  "documents": [
    {
      "tax_year": "2023",
      "form": "1040",
      "filed": "Yes",
      "filing_status": "Single",
      "agi": 50000,
      "balance": 5000.00
    }
  ],
  "transactions": [
    {
      "code": "150",
      "description": "Return Filed",
      "date": "2024-04-15",
      "amount": 5000.00
    }
  ]
}
```

---

## TiParser WI (Wage & Income) Response

**Endpoint:** `https://tiparser.com/api/wi`  
**Method:** POST  
**Request Body:**
```json
{
  "case_id": "your-case-id-here"
}
```

**Response:**
```json
{
  // PASTE YOUR ACTUAL WI RESPONSE HERE
  // Example structure:
  "case_id": "abc-123",
  "tax_period": "2023",
  "forms": [
    {
      "form_type": "W-2",
      "employer_name": "ACME Corp",
      "employer_ein": "12-3456789",
      "wages": 50000.00,
      "federal_withholding": 5000.00,
      "state_withholding": 2000.00
    },
    {
      "form_type": "1099-NEC",
      "payer_name": "Freelance Co",
      "payer_ein": "98-7654321",
      "nonemployee_compensation": 10000.00
    }
  ]
}
```

---

## CaseHelper Interview Response

**Endpoint:** `https://casehelper.com/api/interview`  
**Method:** POST  
**Request Body:**
```json
{
  "case_id": "your-case-id-here"
}
```

**Response:**
```json
{
  // PASTE YOUR ACTUAL INTERVIEW RESPONSE HERE
  // Example structure (Logiqs Raw Data):
  "case_id": "abc-123",
  "employment": {
    "b3": "ACME Corp",           // Taxpayer employer
    "b4": "2020-01-15",          // Start date
    "b5": 50000,                 // Gross annual
    "b6": 45000,                 // Net annual
    "b7": "monthly",             // Pay frequency
    "c3": "Other Corp",          // Spouse employer
    "c4": "2019-06-01",
    "c5": 40000,
    "c6": 36000,
    "c7": "biweekly",
    "al7": 4166.67,              // Taxpayer monthly income
    "al8": 3333.33               // Spouse monthly income
  },
  "household": {
    "b10": 2,                    // Household size
    "b11": "Joint",              // Filing status
    "b50": 2,                    // Under 65
    "b51": 0,                    // Over 65
    "b52": "California",         // State
    "b53": "Orange"              // County
  },
  "assets": {
    "b18": 5000,                 // Bank accounts total
    "b19": 500,                  // Cash on hand
    "b20": 10000,                // Investments
    "b23": 300000,               // Real estate value
    "b24": 25000,                // Vehicle 1 value
    "b25": 15000                 // Vehicle 2 value
  },
  "income": {
    "b33": 50000,                // Taxpayer wages
    "b34": 0,                    // TP social security
    "b36": 40000,                // Spouse wages
    "b40": 2000,                 // Rental income gross
    "b41": 500                   // Rental expenses
  },
  "expenses": {
    "b56": 800,                  // Food
    "b57": 100,                  // Housekeeping
    "b64": 2000,                 // Mortgage/rent
    "b79": 500,                  // Health insurance
    "b87": 0,                    // Court payments
    "b88": 0,                    // Child care
    "b90": 50,                   // Term life insurance
    "ak7": 350,                  // Auto payment 1
    "ak8": 250                   // Auto payment 2
  },
  "irs_standards": {
    "c56": 850,                  // Food standard
    "c57": 110,                  // Housekeeping standard
    "c58": 150,                  // Apparel standard
    "c59": 80,                   // Personal care standard
    "c60": 250,                  // Misc standard
    "al4": 250,                  // Public transportation
    "al5": 850,                  // Food (calculated)
    "c76": 2100,                 // Housing standard
    "c80": 200                   // Health OOP standard
  }
}
```

---

## Notes for Filling This Out

### Where to Get Your API Responses

1. **From Existing Tests/Fixtures:**
   - Look in `tests/fixtures/` or `__tests__/` directories
   - Look for files like `sample_at_response.json`

2. **From API Client Code:**
   - Find where you call the APIs
   - Add a `console.log()` or `print()` to capture response
   - Run the code and copy the output

3. **From API Documentation:**
   - Check API docs for example responses
   - These should be close to real responses

4. **From Network Tab:**
   - Open browser DevTools → Network
   - Trigger API call in your app
   - Copy response from Network tab

### What to Include

**Include:**
- ✅ Actual field names (exact casing)
- ✅ Actual data types (strings, numbers, booleans)
- ✅ Nested structures (objects, arrays)
- ✅ All variations you've seen (if field names differ)
- ✅ Real examples of values
- ✅ Edge cases (missing fields, null values)

**Don't Include:**
- ❌ Sensitive real data (use anonymized/fake data)
- ❌ API keys or tokens
- ❌ Real SSNs, names, addresses
- ❌ Made-up structures (use actual responses)

### Field Name Variations

If you've seen different field names for the same data, document them:

```json
{
  "tax_year": "2023",  // Sometimes "taxYear" or "period"
  "filed": "Yes",      // Sometimes "return_filed" or "status"
  "balance": 5000.00   // Sometimes "amount_owed" or "total"
}
```

This helps Cursor write proper COALESCE logic:
```sql
COALESCE(
  doc->>'tax_year',
  doc->>'taxYear',
  doc->>'period'
) as tax_year
```

---

## Example: How to Provide to Cursor

Once you've filled in the template, provide it to Cursor like this:

```
Here are the actual API responses for Phase 1 analysis:

[Paste the filled-in template here]

Please analyze these in docs/01_API_ANALYSIS.md with:
1. Complete field extraction mapping
2. COALESCE logic for all variations
3. Business rules to apply
4. Trigger design for Bronze → Silver transformations

Start with TiParser AT, then WI, then CaseHelper Interview.
```

---

## Validation Checklist

Before sending to Cursor, verify:

- [ ] JSON is valid (use jsonlint.com)
- [ ] All sensitive data removed/anonymized
- [ ] Field names are exactly as they appear in API
- [ ] Data types are correct (not all strings)
- [ ] Nested structures preserved
- [ ] Arrays shown (even if just one item)
- [ ] Variations documented
- [ ] Edge cases included (nulls, missing fields)

---

## What Cursor Will Do With This

Cursor will:

1. **Analyze structure** - Document all field paths
2. **Map to Bronze** - Plan JSONB storage
3. **Design triggers** - Extract to typed Silver columns
4. **Handle variations** - Write COALESCE for inconsistencies
5. **Apply business rules** - Join with lookup tables
6. **Generate tests** - Use your examples as test data

The better your examples, the better the implementation!
