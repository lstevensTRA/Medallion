# How to Migrate Your Code to Use Bronze Layer

This guide shows you exactly how to modify your existing code to add Bronze storage.

## Step 1: Add Bronze Storage Before Silver

### Before (Current Code)

**File:** `/backend/app/services/transcript_pipeline.py`

```python
# Current flow: API → Python parsing → Silver
async def process_case(self, supabase, case_id, progress_callback=None):
    # Call TiParser API
    parsed_at_data = await self.parse_pdf_with_tiparser(None, 'AT', case_id)
    
    # Directly save to Silver layer (account_activity, tax_years)
    saved_count = await save_at_data(
        supabase,
        case_id,
        parsed_at_data,  # Parsed data
        progress_callback
    )
```

### After (With Bronze)

**File:** `/backend/app/services/transcript_pipeline.py` (modified)

```python
from app.services.bronze_storage import BronzeStorage

# New flow: API → Bronze → SQL Trigger → Silver
async def process_case(self, supabase, case_id, progress_callback=None):
    # Call TiParser API (same as before)
    raw_at_response = await self.parse_pdf_with_tiparser(None, 'AT', case_id)
    
    # NEW: Store raw response in Bronze first
    bronze = BronzeStorage(supabase)
    bronze_id = bronze.store_at_response(case_id, raw_at_response)
    
    # SQL trigger automatically populates Silver!
    # No need to call save_at_data() anymore
    
    logger.info(f"✅ AT data stored in Bronze ({bronze_id}), Silver auto-populated by trigger")
```

**That's it!** Your 287-line `save_at_data()` function is replaced by 1 line + SQL trigger!

---

## Step 2: Apply the Same Pattern to WI, TRT, Interview

### WI (Wage & Income)

**Before:**
```python
parsed_wi_data = await self.parse_pdf_with_tiparser(None, 'WI', case_id)
saved_count = await save_wi_data(supabase, case_id, parsed_wi_data, progress_callback)
```

**After:**
```python
raw_wi_response = await self.parse_pdf_with_tiparser(None, 'WI', case_id)
bronze_id = bronze.store_wi_response(case_id, raw_wi_response)
# SQL trigger handles the rest
```

### TRT (Tax Return Transcript)

**Before:**
```python
parsed_trt_data = await self.parse_pdf_with_tiparser(None, 'TRT', case_id)
saved_count = await save_trt_data(supabase, case_id, parsed_trt_data, progress_callback)
```

**After:**
```python
raw_trt_response = await self.parse_pdf_with_tiparser(None, 'TRT', case_id)
bronze_id = bronze.store_trt_response(case_id, raw_trt_response)
```

### Interview (CaseHelper)

**Before:**
```python
interview_data = await self.interview_fetcher.fetch_interview_data(case_id)
await save_logiqs_raw_data(supabase, case_id, interview_data, progress_callback)
```

**After:**
```python
interview_data = await self.interview_fetcher.fetch_interview_data(case_id)
bronze_id = bronze.store_interview_response(case_id, interview_data)
```

---

## Complete Modified File Example

Here's your updated `transcript_pipeline.py`:

```python
# File: backend/app/services/transcript_pipeline.py
from app.services.bronze_storage import BronzeStorage  # NEW IMPORT
import logging

logger = logging.getLogger(__name__)

class TranscriptPipeline:
    def __init__(self):
        self.downloader = TranscriptDownloader()
        self.auth = CaseHelperAuth()
        self.interview_fetcher = InterviewFetcher()
    
    async def process_case(
        self,
        supabase: Client,
        case_id: str,
        progress_callback=None,
        transcript_types: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """
        Main processing function: Download transcripts and store in Bronze layer
        SQL triggers automatically populate Silver layer
        """
        results = {
            'wage_income': [],
            'account_transcripts': [],
            'errors': [],
            'summary': {
                'total_bronze_records': 0,
                'total_saved': 0
            }
        }
        
        # Initialize Bronze storage
        bronze = BronzeStorage(supabase)
        
        try:
            # Process AT files
            at_files = [...]  # Your existing logic to get files
            if at_files:
                if progress_callback:
                    progress_callback(f"Parsing {len(at_files)} AT files...", 20)
                
                try:
                    # Call TiParser API (no changes to this part)
                    raw_at_response = await self.parse_pdf_with_tiparser(
                        None,
                        'AT',
                        case_id
                    )
                    
                    # CHANGE: Store in Bronze instead of calling save_at_data()
                    bronze_id = bronze.store_at_response(case_id, raw_at_response)
                    
                    # SQL trigger automatically populates:
                    # - tax_years
                    # - account_activity
                    # - csed_tolling_events
                    
                    results['account_transcripts'] = [{
                        'bronze_id': bronze_id,
                        'files': len(at_files),
                        'status': 'stored_in_bronze'
                    }]
                    results['summary']['total_bronze_records'] += 1
                    
                    logger.info(f"✅ AT data stored in Bronze: {bronze_id}")
                    
                except Exception as e:
                    logger.error(f"AT pipeline error: {str(e)}")
                    results['errors'].append({
                        'type': 'AT',
                        'error': str(e)
                    })
            
            # Process WI files
            wi_files = [...]  # Your existing logic
            if wi_files:
                if progress_callback:
                    progress_callback(f"Parsing {len(wi_files)} WI files...", 60)
                
                try:
                    raw_wi_response = await self.parse_pdf_with_tiparser(
                        None,
                        'WI',
                        case_id
                    )
                    
                    # CHANGE: Store in Bronze
                    bronze_id = bronze.store_wi_response(case_id, raw_wi_response)
                    
                    # SQL trigger automatically populates:
                    # - income_documents
                    # - employment_information (Gold)
                    # - income_sources (Gold)
                    
                    results['wage_income'] = [{
                        'bronze_id': bronze_id,
                        'files': len(wi_files),
                        'status': 'stored_in_bronze'
                    }]
                    results['summary']['total_bronze_records'] += 1
                    
                    logger.info(f"✅ WI data stored in Bronze: {bronze_id}")
                    
                except Exception as e:
                    logger.error(f"WI pipeline error: {str(e)}")
                    results['errors'].append({
                        'type': 'WI',
                        'error': str(e)
                    })
            
            # Process TRT (if requested)
            if transcript_types is None or 'TRT' in transcript_types:
                if progress_callback:
                    progress_callback("Fetching TRT data...", 85)
                
                try:
                    raw_trt_response = await self.parse_pdf_with_tiparser(
                        None,
                        'TRT',
                        case_id
                    )
                    
                    # CHANGE: Store in Bronze
                    bronze_id = bronze.store_trt_response(case_id, raw_trt_response)
                    
                    results['summary']['total_bronze_records'] += 1
                    logger.info(f"✅ TRT data stored in Bronze: {bronze_id}")
                    
                except Exception as e:
                    logger.warning(f"TRT pipeline error (may be expected): {str(e)}")
                    results['errors'].append({
                        'type': 'TRT',
                        'error': str(e)
                    })
            
            # Fetch and store interview data
            if progress_callback:
                progress_callback("Fetching interview data...", 92)
            
            try:
                interview_data = await self.interview_fetcher.fetch_interview_data(case_id)
                
                if interview_data:
                    # CHANGE: Store in Bronze
                    bronze_id = bronze.store_interview_response(case_id, interview_data)
                    
                    results['summary']['interview_data_saved'] = True
                    results['summary']['total_bronze_records'] += 1
                    logger.info(f"✅ Interview data stored in Bronze: {bronze_id}")
                else:
                    logger.info(f"No interview data found for case {case_id}")
                    results['summary']['interview_data_saved'] = False
                    
            except Exception as e:
                logger.warning(f"Interview data fetch error: {str(e)}")
                results['errors'].append({
                    'type': 'interview',
                    'error': str(e)
                })
            
            if progress_callback:
                progress_callback("Processing complete!", 100)
            
            return results
            
        except Exception as e:
            error_msg = f"Pipeline error: {str(e)}"
            logger.error(error_msg)
            results['errors'].append({
                'file': 'pipeline',
                'error': str(e)
            })
            raise Exception(error_msg)
```

---

## What You Can Delete (After Triggers Are Created)

Once Bronze → Silver triggers are working, you can **delete or archive** these files:

1. ❌ `save_at_data()` function (287 lines) - Replaced by SQL trigger
2. ❌ `save_wi_data()` function (423 lines) - Replaced by SQL trigger
3. ❌ `save_trt_data()` function (179 lines) - Replaced by SQL trigger
4. ❌ `save_logiqs_raw_data()` function (346 lines) - Replaced by SQL trigger

**Total code deleted:** ~1,235 lines of Python parsing logic!

**What replaces it:** 4 SQL triggers (we'll create these next in Phase 4)

---

## Benefits of This Approach

### 1. Replay Ability

**Scenario:** Business rule changes (e.g., new form type classification)

**Before:**
```
❌ Must re-call expensive TiParser API ($$$)
❌ Slow (API rate limits)
❌ May get different data (time has passed)
```

**After:**
```
✅ Reprocess from Bronze (free, instant)
✅ Just update trigger logic
✅ Same data every time
```

### 2. Debugging

**Before:**
```
❌ Bug in parsing? Data lost forever
❌ Must guess what API returned
❌ Can't reproduce issues
```

**After:**
```
✅ Bug in trigger? Raw data preserved
✅ Can inspect exact API response
✅ Fix trigger and replay
```

### 3. Audit Trail

**Before:**
```
❌ No record of what API returned
❌ Can't prove data accuracy
❌ No audit trail
```

**After:**
```
✅ Complete record of API responses
✅ Timestamped immutable history
✅ Full audit trail for compliance
```

---

## Backward Compatibility

If you want to keep your existing code working during migration:

```python
# Option: Dual-write (Bronze + Old Silver)
# This lets you test Bronze layer without breaking existing code

async def process_case_with_dual_write(self, supabase, case_id):
    raw_response = await self.parse_pdf_with_tiparser('AT', case_id)
    
    # NEW: Write to Bronze
    bronze_id = bronze.store_at_response(case_id, raw_response)
    
    # OLD: Also write to Silver (temporary, for safety)
    await save_at_data(supabase, case_id, raw_response)
    
    # Compare results to verify triggers work correctly
    # Once verified, remove save_at_data() call
```

---

## Testing Your Changes

### 1. Test Bronze Storage

```python
# Test: Store AT data in Bronze
bronze = BronzeStorage(supabase)
test_response = {"records": [{"tax_year": "2023", "transactions": []}]}
bronze_id = bronze.store_at_response("TEST-CASE", test_response)

# Verify stored correctly
record = bronze.get_bronze_record('bronze_at_raw', bronze_id)
assert record['raw_response'] == test_response
assert record['processing_status'] == 'pending'
```

### 2. Test Trigger (After Phase 4)

```python
# After trigger created, test automatic Silver population
bronze_id = bronze.store_at_response("TEST-CASE", test_response)

# Wait for trigger to complete (usually instant)
import time
time.sleep(1)

# Check Silver layer was populated
tax_years = supabase.table('tax_years').select('*').eq('case_id', 'TEST-CASE').execute()
assert len(tax_years.data) > 0  # Silver layer populated!
```

### 3. Test End-to-End

```python
# Test complete flow
await process_case_transcripts(supabase, "REAL-CASE-ID")

# Check Bronze
summary = bronze.get_processing_summary()
print(summary)
# {'AT': {'total': 1, 'processed': 1, 'pending': 0, 'failed': 0}}

# Check Silver (should be auto-populated)
activities = supabase.table('account_activity').select('*').execute()
assert len(activities.data) > 0
```

---

## Next Steps

1. ✅ **Apply Bronze migration:** `supabase db push` (run 001_create_bronze_tables.sql)
2. ⏸️ **Create Bronze → Silver triggers** (Phase 4)
3. ⏸️ **Modify your Python code** (use this guide)
4. ⏸️ **Test with sample data**
5. ⏸️ **Deploy to production**

---

## Questions?

**Q: What if the trigger fails?**
A: Bronze record marked as `processing_status = 'failed'`. You can inspect the error, fix the trigger, and replay.

**Q: Can I replay old Bronze data after trigger changes?**
A: Yes! Use `bronze.replay_bronze_to_silver('bronze_at_raw', case_id='CASE-001')`

**Q: Do I need to change my frontend?**
A: No! Frontend still reads from Silver/Gold tables (no changes needed)

**Q: How much storage does Bronze use?**
A: ~10-50KB per case per API call. 1,000 cases = ~50MB (negligible)

---

**Ready for Phase 4?** Next we'll create the SQL triggers that automatically transform Bronze → Silver!

