#!/usr/bin/env python3
"""
Diagnose and Fix Bronze → Silver Triggers

This script:
1. Checks trigger status via Supabase
2. Attempts to fix trigger issues
3. Tests trigger functionality
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
    print("❌ Missing SUPABASE_URL or SUPABASE_ACCESS_TOKEN")
    sys.exit(1)

project_ref = SUPABASE_URL.replace('https://', '').replace('http://', '').replace('.supabase.co', '')

print("=" * 80)
print("🔍 DIAGNOSING BRONZE → SILVER TRIGGERS")
print("=" * 80)
print()

# SQL queries to diagnose
diagnosis_queries = {
    "Check Triggers": """
        SELECT 
            tgname as trigger_name,
            tgrelid::regclass as table_name,
            tgenabled as enabled,
            CASE tgenabled
                WHEN 'O' THEN 'Enabled'
                WHEN 'D' THEN 'Disabled'
                WHEN 'R' THEN 'Replica'
                WHEN 'A' THEN 'Always'
                ELSE 'Unknown'
            END as status
        FROM pg_trigger
        WHERE tgname LIKE 'trigger_bronze%'
        ORDER BY tgname;
    """,
    
    "Check ensure_case Function": """
        SELECT 
            proname as function_name,
            CASE 
                WHEN proname IS NULL THEN 'MISSING'
                ELSE 'EXISTS'
            END as status
        FROM pg_proc
        WHERE proname = 'ensure_case';
    """,
    
    "Check Trigger Functions": """
        SELECT 
            proname as function_name,
            CASE 
                WHEN proname IS NULL THEN 'MISSING'
                ELSE 'EXISTS'
            END as status
        FROM pg_proc
        WHERE proname IN ('process_bronze_at', 'process_bronze_wi', 'process_bronze_interview')
        ORDER BY proname;
    """,
    
    "Test ensure_case": """
        SELECT ensure_case('1295022') as case_uuid;
    """
}

# Execute queries via Management API
url = f"https://api.supabase.com/v1/projects/{project_ref}/database/query"
headers = {
    "Authorization": f"Bearer {SUPABASE_ACCESS_TOKEN}",
    "Content-Type": "application/json"
}

results = {}

for query_name, sql in diagnosis_queries.items():
    print(f"🔍 {query_name}...")
    payload = {"query": sql}
    
    try:
        response = requests.post(url, json=payload, headers=headers, timeout=30)
        
        if response.status_code in [200, 201]:
            data = response.json()
            results[query_name] = data
            print(f"   ✅ Query executed")
            
            # Try to parse results
            if isinstance(data, list) and len(data) > 0:
                print(f"   📊 Results:")
                for row in data[:5]:  # Show first 5 rows
                    print(f"      {row}")
            elif isinstance(data, dict):
                print(f"   📊 Result: {data}")
        else:
            print(f"   ⚠️  API returned {response.status_code}")
            print(f"   Response: {response.text[:200]}")
            results[query_name] = None
    except Exception as e:
        print(f"   ❌ Error: {str(e)[:100]}")
        results[query_name] = None
    
    print()

# Summary
print("=" * 80)
print("📊 DIAGNOSIS SUMMARY")
print("=" * 80)
print()

# Analyze results
if results.get("Check Triggers"):
    triggers = results["Check Triggers"]
    if isinstance(triggers, list) and len(triggers) > 0:
        print("✅ Triggers Found:")
        for trigger in triggers:
            name = trigger.get('trigger_name', 'Unknown')
            status = trigger.get('status', 'Unknown')
            print(f"   • {name}: {status}")
    else:
        print("❌ No triggers found!")
        print("   💡 Triggers may not be created")
else:
    print("⚠️  Could not check triggers")

print()

if results.get("Check ensure_case Function"):
    func = results["Check ensure_case Function"]
    if isinstance(func, list) and len(func) > 0:
        status = func[0].get('status', 'Unknown')
        if status == 'EXISTS':
            print("✅ ensure_case function exists")
        else:
            print("❌ ensure_case function MISSING!")
            print("   💡 Need to create ensure_case function")
    else:
        print("⚠️  Could not check ensure_case function")
else:
    print("⚠️  Could not check ensure_case function")

print()

# Create fix SQL if needed
print("=" * 80)
print("🔧 FIXES NEEDED")
print("=" * 80)
print()

# Read the trigger migration to get ensure_case function
trigger_migration = Path(__file__).parent / "supabase/migrations/20250125000003_medallion_triggers.sql"

if trigger_migration.exists():
    print("📋 Creating fix SQL file...")
    
    with open(trigger_migration, 'r') as f:
        migration_content = f.read()
    
    # Extract ensure_case function
    import re
    ensure_case_match = re.search(r'CREATE OR REPLACE FUNCTION ensure_case.*?END;', migration_content, re.DOTALL)
    
    if ensure_case_match:
        ensure_case_sql = ensure_case_match.group(0)
        
        # Create fix file
        fix_sql = f"""-- ============================================================================
-- FIX BRONZE → SILVER TRIGGERS
-- Purpose: Ensure triggers are active and functions exist
-- ============================================================================

-- Step 1: Ensure ensure_case function exists
{ensure_case_sql}

-- Step 2: Verify triggers are enabled
ALTER TABLE bronze_at_raw ENABLE TRIGGER trigger_bronze_at_to_silver;
ALTER TABLE bronze_wi_raw ENABLE TRIGGER trigger_bronze_wi_to_silver;
ALTER TABLE bronze_interview_raw ENABLE TRIGGER trigger_bronze_interview_to_silver;

-- Step 3: Verify triggers exist (run this to check)
-- SELECT tgname, tgrelid::regclass, tgenabled FROM pg_trigger WHERE tgname LIKE 'trigger_bronze%';
"""
        
        fix_file = Path(__file__).parent / "FIX_BRONZE_TO_SILVER_TRIGGERS.sql"
        with open(fix_file, 'w') as f:
            f.write(fix_sql)
        
        print(f"   ✅ Created: {fix_file}")
        print()
        print("📋 To apply fix:")
        print("   1. Open: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql")
        print("   2. Paste contents of: FIX_BRONZE_TO_SILVER_TRIGGERS.sql")
        print("   3. Run query")
    else:
        print("   ⚠️  Could not extract ensure_case function from migration")
else:
    print("   ⚠️  Trigger migration file not found")

print()

