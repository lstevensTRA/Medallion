# PDF Blob Storage Implementation

## 📋 Status: Ready to Deploy

We've implemented PDF blob storage alongside the existing JSON parsing flow.

---

## 🎯 What's Been Created

### 1. Database Migration
**File:** `supabase/migrations/004_bronze_pdf_storage.sql`

Creates:
- ✅ `bronze_pdf_raw` table for PDF metadata
- ✅ Storage bucket `case-pdfs` for actual PDF files
- ✅ Helper functions (`get_pdf_download_url`, `link_pdf_to_parsed_data`, `get_case_pdfs`)
- ✅ Monitoring view (`bronze_pdf_health`)
- ✅ RLS policies for secure access

### 2. PDF Storage Service
**File:** `backend/app/services/pdf_storage.py`

Provides:
- ✅ `upload_pdf()` - Store PDF with metadata
- ✅ `download_pdf_from_url()` - Download and store from URL
- ✅ `get_pdf_content()` - Retrieve stored PDF
- ✅ `get_pdf_signed_url()` - Generate temporary access URLs
- ✅ `link_pdf_to_parsed_data()` - Link PDF to parsed JSON
- ✅ SHA-256 hashing for deduplication
- ✅ Automatic file organization: `{case_id}/{document_type}/{tax_year}/{filename}`

### 3. Enhanced CaseHelper Resource
**File:** `dagster_pipeline/resources/casehelper_resource.py`

New methods:
- ✅ `get_document_list()` - List all case documents
- ✅ `filter_transcript_files()` - Find AT/WI/TRT PDFs
- ✅ `download_pdf()` - Download PDF from CaseHelper

### 4. Dagster PDF Storage Resource
**File:** `dagster_pipeline/resources/pdf_storage_resource.py`

Wraps PDFStorageService for Dagster assets.

---

## 💰 Cost Analysis (Supabase Storage)

**Pro Plan:** $25/month
- Includes **100 GB storage** (FREE for most use cases)
- Additional storage: $0.021/GB/month

**Real-World Usage:**
```
1,000 cases × 4 PDFs × 200 KB = 0.8 GB → FREE
10,000 cases × 4 PDFs × 200 KB = 8 GB → FREE  
100,000 cases × 4 PDFs × 200 KB = 80 GB → FREE
1,000,000 cases × 4 PDFs × 200 KB = 800 GB → $14/month extra
```

**Verdict:** Essentially FREE for your scale! ✅

---

## 🚀 Next Steps to Deploy

### Step 1: Apply the Migration

```bash
# Navigate to project root
cd /Users/lindseystevens/Medallion

# Create the storage bucket (required before migration)
# Go to Supabase Dashboard → Storage → Create bucket:
#   - Name: "case-pdfs"
#   - Public: NO (private)
#   - File size limit: 50MB
#   - Allowed MIME types: application/pdf

# Apply the migration
supabase db push
```

### Step 2: Update Dagster Assets (TODO)

We need to enhance the Bronze assets to:
1. Call TiParser API for parsed JSON (current flow) ✅
2. Download actual PDFs from CaseHelper (new)
3. Store PDFs in Supabase Storage (new)
4. Link PDFs to parsed data (new)

**Example enhanced asset:**
```python
@asset
def bronze_at_data_with_pdfs(
    context: AssetExecutionContext,
    config: BronzeAssetConfig,
    supabase: SupabaseResource,
    tiparser: TiParserResource,
    casehelper: CaseHelperResource,
    pdf_storage: PDFStorageResource
):
    case_id = config.case_id
    
    # 1. Get parsed JSON from TiParser (existing)
    at_response = tiparser.get_at_analysis(case_id)
    bronze_id = store_in_bronze_at_raw(at_response)
    
    # 2. Download PDFs from CaseHelper (new)
    documents = casehelper.get_document_list(case_id)
    at_files = [f for f in casehelper.filter_transcript_files(documents) if f.type == 'AT']
    
    pdf_service = pdf_storage.get_service(supabase.get_client())
    
    for transcript_file in at_files:
        # Download PDF
        pdf_bytes = casehelper.download_pdf(case_id, transcript_file.document_entry)
        
        # Store in Supabase Storage
        result = pdf_service.upload_pdf(
            file_content=pdf_bytes,
            case_id=case_id,
            document_type='AT',
            file_name=transcript_file.file_name,
            source_system='casehelper',
            tax_year=transcript_file.year
        )
        
        # Link PDF to parsed data
        pdf_service.link_pdf_to_parsed_data(
            bronze_pdf_id=result['bronze_pdf_id'],
            parsed_bronze_id=bronze_id
        )
    
    return {"bronze_id": bronze_id, "pdfs_stored": len(at_files)}
```

### Step 3: Test with Real Case

```yaml
ops:
  bronze_at_data_with_pdfs:
    config:
      case_id: "1295022"
      case_number: "CASE-1295022"
```

### Step 4: Verify Storage

```sql
-- Check PDFs stored
SELECT * FROM bronze_pdf_raw WHERE case_id = '1295022';

-- Check storage health
SELECT * FROM bronze_pdf_health;

-- Get case PDFs
SELECT * FROM get_case_pdfs('1295022');
```

---

## 📊 Data Flow

```
┌─────────────┐
│ CaseHelper  │
│   (PDFs)    │
└──────┬──────┘
       │
       │ ① Download PDF bytes
       ▼
┌─────────────┐
│  TiParser   │──② Parse PDF──┐
│     API     │              │
└─────────────┘              │
                             │
       ┌─────────────────────┴───────────────────┐
       │                                         │
       ▼                                         ▼
┌─────────────────┐                    ┌──────────────────┐
│ bronze_pdf_raw  │◄───Link────────────│ bronze_at_raw    │
│  (PDF metadata) │                    │  (Parsed JSON)   │
└────────┬────────┘                    └──────────────────┘
         │                                       │
         │ storage_path                          │ SQL Trigger
         ▼                                       ▼
┌─────────────────┐                    ┌──────────────────┐
│ Supabase        │                    │ Silver Layer     │
│  Storage        │                    │  (typed data)    │
│  (PDF files)    │                    └──────────────────┘
└─────────────────┘
```

---

## 🎯 Benefits of PDF Storage

1. **Audit Trail** - Original documents preserved
2. **Re-parsing** - Can re-process if TiParser updates
3. **Compliance** - Legal/regulatory requirements met
4. **Data Lineage** - Complete traceable data flow
5. **Cost-Effective** - Essentially free at your scale

---

## 📝 Optional Enhancements (Future)

1. **Compression** - Reduce PDF sizes by 30-50%
2. **OCR** - Extract text from scanned PDFs
3. **Lifecycle Policies** - Auto-delete old PDFs after X years
4. **Archive to S3 Glacier** - Move old PDFs to cheaper storage
5. **PDF Preview** - Generate thumbnails for UI
6. **Versioning** - Track PDF updates over time

---

## ✅ Testing Checklist

- [ ] Apply migration (`supabase db push`)
- [ ] Create storage bucket in Supabase Dashboard
- [ ] Update Bronze assets with PDF download logic
- [ ] Test with case 1295022
- [ ] Verify PDF stored in `bronze_pdf_raw`
- [ ] Verify file in Supabase Storage
- [ ] Check `bronze_pdf_health` view
- [ ] Test PDF retrieval with `get_pdf_signed_url()`
- [ ] Verify linking between PDF and parsed data

---

## 🚨 Important Notes

1. **Storage Bucket** must be created BEFORE running migration
2. **File paths** are standardized: `{case_id}/{type}/{year}/{filename}`
3. **Deduplication** uses SHA-256 hash to prevent duplicate storage
4. **RLS policies** ensure secure access control
5. **Signed URLs** expire after 1 hour by default

---

## 📚 Documentation

- **API Reference:** See `backend/app/services/pdf_storage.py` docstrings
- **Schema:** See `supabase/migrations/004_bronze_pdf_storage.sql` comments
- **Dagster Usage:** See `dagster_pipeline/resources/` for resource examples

---

**Status:** Ready for deployment! Next step is to apply the migration and update the Dagster assets.

