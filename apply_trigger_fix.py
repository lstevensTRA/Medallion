#!/usr/bin/env python3
"""
Apply Trigger Fix - Manually Process Bronze Records to Populate Silver
"""

import os
import sys
import requests
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
env_path = Path(__file__).parent / ".env"
load_dotenv(env_path)

SUPABASE_URL = os.getenv('SUPABASE_URL', '')
SUPABASE_ACCESS_TOKEN = os.getenv('SUPABASE_ACCESS_TOKEN', '')

if not SUPABASE_URL or not SUPABASE_ACCESS_TOKEN:
    print("❌ Missing SUPABASE_URL or SUPABASE_ACCESS_TOKEN in .env")
    sys.exit(1)

# Extract project ref
project_ref = SUPABASE_URL.replace('https://', '').replace('http://', '').replace('.supabase.co', '')

print("=" * 80)
print("🔧 FIXING BRONZE → SILVER TRIGGERS")
print("=" * 80)
print()

# Read the manual populate SQL
sql_file = Path(__file__).parent / "manually_populate_silver.sql"
print(f"📖 Reading SQL file: {sql_file}")

with open(sql_file, 'r') as f:
    sql = f.read()

print(f"   ✅ Read {len(sql)} characters")
print()

# Apply via Management API
url = f"https://api.supabase.com/v1/projects/{project_ref}/database/query"
headers = {
    "Authorization": f"Bearer {SUPABASE_ACCESS_TOKEN}",
    "Content-Type": "application/json"
}
payload = {"query": sql}

print("🚀 Applying trigger fix...")
print("   (This will process existing Bronze records to populate Silver)")
print()

try:
    response = requests.post(url, json=payload, headers=headers, timeout=60)
    
    if response.status_code in [200, 201]:
        result = response.json()
        print("✅ Trigger fix applied!")
        print()
        if result:
            print(f"   Result: {result}")
        print()
        print("📊 Checking Silver layer status...")
        print()
        
        # Check Silver status
        from supabase import create_client
        SUPABASE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_KEY')
        supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
        
        # Get case UUID
        case_response = supabase.table('cases').select('id').eq('case_number', '1295022').limit(1).execute()
        if case_response.data:
            case_uuid = case_response.data[0]['id']
            
            # Check Silver tables
            tax_years = supabase.table('tax_years').select('*', count='exact').eq('case_id', case_uuid).execute()
            account_activity = supabase.table('account_activity').select('*', count='exact').eq('case_id', case_uuid).execute()
            income_documents = supabase.table('income_documents').select('*', count='exact').eq('case_id', case_uuid).execute()
            
            print("🥈 Silver Layer Status:")
            print(f"   tax_years: {tax_years.count if hasattr(tax_years, 'count') else len(tax_years.data)} records")
            print(f"   account_activity: {account_activity.count if hasattr(account_activity, 'count') else len(account_activity.data)} records")
            print(f"   income_documents: {income_documents.count if hasattr(income_documents, 'count') else len(income_documents.data)} records")
            print()
            
            if (tax_years.count if hasattr(tax_years, 'count') else len(tax_years.data)) > 0:
                print("🎉 SUCCESS! Silver layer is now populated!")
                print("   Bronze → Silver pipeline is working!")
            else:
                print("⚠️  Silver still empty - triggers may need manual fix")
                print("   Run manually_populate_silver.sql in Supabase SQL Editor")
        else:
            print("⚠️  Case not found")
    else:
        print(f"❌ API Error: {response.status_code}")
        print(f"   Response: {response.text[:200]}")
        print()
        print("💡 Alternative: Run manually_populate_silver.sql in Supabase SQL Editor")
        print("   1. Open: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql")
        print("   2. Paste contents of: manually_populate_silver.sql")
        print("   3. Run query")
        
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
    print()
    print("💡 Alternative: Run manually_populate_silver.sql in Supabase SQL Editor")

