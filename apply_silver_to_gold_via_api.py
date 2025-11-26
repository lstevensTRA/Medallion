#!/usr/bin/env python3
"""
Apply Silver → Gold trigger migration via Supabase Management API
"""

import os
import sys
import requests
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

SUPABASE_URL = os.getenv('SUPABASE_URL', '')
SUPABASE_ACCESS_TOKEN = os.getenv('SUPABASE_ACCESS_TOKEN', '')

if not SUPABASE_URL or not SUPABASE_ACCESS_TOKEN:
    print("❌ Missing SUPABASE_URL or SUPABASE_ACCESS_TOKEN in .env")
    sys.exit(1)

# Extract project ref from URL
project_ref = SUPABASE_URL.replace('https://', '').replace('http://', '').replace('.supabase.co', '')

# Read migration file
migration_file = "APPLY_SILVER_TO_GOLD_TRIGGERS.sql"
print(f"📖 Reading migration file: {migration_file}")

with open(migration_file, 'r') as f:
    sql = f.read()

print("🚀 Executing migration via Supabase Management API...")
print("   (This may take a moment...)")

# Supabase Management API endpoint for executing SQL
url = f"https://api.supabase.com/v1/projects/{project_ref}/database/query"

headers = {
    "Authorization": f"Bearer {SUPABASE_ACCESS_TOKEN}",
    "Content-Type": "application/json"
}

payload = {
    "query": sql
}

try:
    response = requests.post(url, json=payload, headers=headers, timeout=60)
    
    if response.status_code == 200:
        print("✅ Migration executed successfully!")
        result = response.json()
        if result.get('data'):
            print(f"   Result: {result['data']}")
        print("")
        print("📊 Silver → Gold pipeline is now active!")
        print("   When logiqs_raw_data is inserted/updated:")
        print("   → employment_information (taxpayer + spouse)")
        print("   → household_information")
        print("   → monthly_expenses (all categories)")
        print("   → income_sources (all types)")
        print("   → financial_accounts")
        print("   → vehicles_v2")
        print("   → real_property_v2")
        print("\n🎉 Migration complete!")
    else:
        print(f"❌ API Error: {response.status_code}")
        print(f"   Response: {response.text}")
        print("\n💡 Alternative: Run SQL manually via Supabase Dashboard")
        print("   1. Go to: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql")
        print("   2. Copy contents of: APPLY_SILVER_TO_GOLD_TRIGGERS.sql")
        print("   3. Paste and run")
        sys.exit(1)
        
except requests.exceptions.RequestException as e:
    print(f"❌ Request error: {e}")
    print("\n💡 Alternative: Run SQL manually via Supabase Dashboard")
    print("   1. Go to: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql")
    print("   2. Copy contents of: APPLY_SILVER_TO_GOLD_TRIGGERS.sql")
    print("   3. Paste and run")
    sys.exit(1)

