# Fixes Applied - Tax Projections & Interview Data

## Date: 2025-01-28

### Issues Fixed

#### 1. ✅ Tax Projections Showing $0.00

**Problem:** Tax projections were being calculated but showing $0.00 for all values (income, tax, refund/owed).

**Root Cause:** The `populate_tax_projections_for_case` function was using incorrect column names when mapping results from `calculate_tax_projection`:
- Expected: `projected_tax_liability` and `projected_refund_or_due`
- Actual: `total_tax` and `projected_balance`

**Fix Applied:**
- Updated `populate_tax_projections_for_case` function in `scripts/fix_tax_projections_mapping.sql`
- Changed column mapping:
  - `projected_tax_liability` → `total_tax`
  - `projected_refund_or_due` → `projected_balance`
- Applied migration via Supabase Management API

**Next Steps:**
1. Re-run case analysis to trigger tax projections recalculation
2. Or manually call: `SELECT refresh_tax_projections('case_id_here')`

---

#### 2. ✅ Interview Data Not Populating

**Problem:** Interview data from CaseHelper API not being fetched or inserted into `bronze_interview_raw`.

**Root Causes:**
1. Missing environment variables (`CASEHELPER_USERNAME`, `CASEHELPER_PASSWORD`)
2. Silent failures - function returns `null` without clear error messages
3. No visibility into why interview fetch is failing

**Fixes Applied:**
1. **Enhanced Logging** in `ingest-case` Edge Function:
   - Added warning if credentials are missing
   - Added detailed error logging with stack traces
   - Added success confirmation when data is inserted
   - Added trigger confirmation message

2. **Better Error Messages:**
   - Clear message if credentials not configured
   - Instructions to set env vars in Supabase Dashboard
   - Detailed error logging for API failures

**Next Steps:**
1. **Verify Credentials:**
   - Go to Supabase Dashboard → Functions → ingest-case → Settings
   - Ensure these environment variables are set:
     - `CASEHELPER_API_URL`
     - `CASEHELPER_USERNAME`
     - `CASEHELPER_PASSWORD`
     - `CASEHELPER_API_KEY` (optional)

2. **Re-run Case:**
   - Click "Rerun Analysis" for the case
   - Check Edge Function logs for interview data fetch status
   - Look for:
     - `✅ Fetched interview data for case X`
     - `✅ Inserted interview data into Bronze`
     - `Trigger should fire: bronze_interview_raw → logiqs_raw_data → Gold tables`

3. **Verify Data Flow:**
   ```sql
   -- Check Bronze
   SELECT COUNT(*) FROM bronze_interview_raw WHERE case_id = 'case_number';
   
   -- Check Silver
   SELECT COUNT(*) FROM logiqs_raw_data WHERE case_id = 'case_id';
   
   -- Check Gold
   SELECT COUNT(*) FROM employment_information WHERE case_id = 'case_id';
   ```

---

### Files Modified

1. `scripts/fix_tax_projections_mapping.sql` - Fixed column mapping
2. `supabase/functions/ingest-case/index.ts` - Enhanced interview data logging
3. `docs/FIXES_APPLIED.md` - This documentation

---

### Testing Checklist

- [ ] Tax projections show non-zero values after rerun
- [ ] Interview data appears in `bronze_interview_raw` after rerun
- [ ] Silver `logiqs_raw_data` populated from interview trigger
- [ ] Gold `employment_information` populated from Silver trigger
- [ ] Edge Function logs show clear success/error messages

---

### Known Issues

1. **Some cases still showing $0.00:**
   - May need income documents to exist first
   - Check if `income_documents` table has data for the case
   - Verify `tax_years` table has correct `owner` and `filing_status`

2. **Interview data not triggering:**
   - Verify credentials are set correctly
   - Check Edge Function logs for authentication errors
   - Verify CaseHelper API is accessible
   - Check if trigger `trigger_bronze_interview_to_silver` is enabled

---

### Related Migrations

- `supabase/migrations/20250128000018_populate_tax_projections_trigger.sql` - Original trigger
- `supabase/migrations/20250128000007_add_ssn_filter_to_tax_projection.sql` - Tax projection function
- `supabase/migrations/002_bronze_to_silver_triggers.sql` - Interview trigger

