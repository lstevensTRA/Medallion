#!/usr/bin/env python3
"""
Fix Bronze → Silver Triggers via Supabase API
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

# Read diagnosis SQL
diagnosis_file = Path(__file__).parent / "diagnose_and_fix_triggers.sql"
print("=" * 80)
print("🔧 DIAGNOSING AND FIXING BRONZE → SILVER TRIGGERS")
print("=" * 80)
print()

with open(diagnosis_file, 'r') as f:
    sql = f.read()

# Split into individual queries
queries = []
current_query = []
for line in sql.split('\n'):
    line = line.strip()
    if not line or line.startswith('--'):
        continue
    if line.endswith(';'):
        current_query.append(line)
        queries.append(' '.join(current_query))
        current_query = []
    else:
        current_query.append(line)

print(f"📋 Found {len(queries)} SQL queries to run")
print()

# Run queries via Management API
url = f"https://api.supabase.com/v1/projects/{project_ref}/database/query"

headers = {
    "Authorization": f"Bearer {SUPABASE_ACCESS_TOKEN}",
    "Content-Type": "application/json"
}

results = []

for i, query in enumerate(queries, 1):
    if 'DO $$' in query or 'RAISE NOTICE' in query:
        # Skip DO blocks (can't run via API easily)
        continue
    
    print(f"🔍 Running query {i}/{len(queries)}...")
    
    payload = {"query": query}
    
    try:
        response = requests.post(url, json=payload, headers=headers, timeout=30)
        
        if response.status_code in [200, 201]:
            result = response.json()
            results.append((i, query[:50] + "...", "✅ Success", result))
            print(f"   ✅ Success")
        else:
            results.append((i, query[:50] + "...", f"❌ Error {response.status_code}", response.text[:100]))
            print(f"   ⚠️  Status {response.status_code}")
    except Exception as e:
        results.append((i, query[:50] + "...", f"❌ Exception", str(e)[:100]))
        print(f"   ❌ Error: {str(e)[:50]}")

print()
print("=" * 80)
print("📊 RESULTS")
print("=" * 80)
print()

for i, query, status, result in results:
    print(f"{status} Query {i}: {query}")
    if isinstance(result, dict) and result:
        print(f"   Result: {result}")
    print()

print()
print("💡 For detailed diagnosis, run diagnose_and_fix_triggers.sql in Supabase SQL Editor")
print()

