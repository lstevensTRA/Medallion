#!/usr/bin/env python3
"""
Check if Silver layer tables exist
"""

import os
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Check if Silver tables exist by trying to query them
silver_tables = [
    'tax_years',
    'account_activity', 
    'income_documents',
    'trt_records',
    'logiqs_raw_data'
]

print("=" * 80)
print("🔍 Checking Silver Layer Tables")
print("=" * 80)
print()

results = {}

for table in silver_tables:
    try:
        # Try to query the table (just count)
        result = client.table(table).select('*', count='exact').limit(1).execute()
        results[table] = {
            'exists': True,
            'count': result.count if hasattr(result, 'count') else 'unknown'
        }
        print(f"✅ {table}: EXISTS (count: {results[table]['count']})")
    except Exception as e:
        results[table] = {
            'exists': False,
            'error': str(e)
        }
        print(f"❌ {table}: MISSING - {str(e)[:100]}")

print()
print("=" * 80)

# Summary
existing = sum(1 for r in results.values() if r['exists'])
total = len(silver_tables)

if existing == total:
    print(f"✅ SUCCESS! All {total} Silver tables exist!")
    print()
    print("🎯 Next: Check if triggers processed your Bronze data:")
    print("   Run in Supabase: SELECT * FROM tax_years WHERE case_id = '1295022';")
elif existing > 0:
    print(f"⚠️  PARTIAL: {existing}/{total} tables exist")
    print("   Migration may have partially applied")
else:
    print(f"❌ FAILED: No Silver tables found")
    print("   Migration did not apply successfully")

print("=" * 80)


