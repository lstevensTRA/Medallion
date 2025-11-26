#!/usr/bin/env python3
"""
Apply Silver → Gold Migration via Supabase REST API
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
SUPABASE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_KEY')
SUPABASE_ACCESS_TOKEN = os.getenv('SUPABASE_ACCESS_TOKEN', '')

if not SUPABASE_URL:
    print("❌ Missing SUPABASE_URL in .env")
    sys.exit(1)

# Extract project ref from URL
project_ref = SUPABASE_URL.replace('https://', '').replace('http://', '').replace('.supabase.co', '')

# Read migration file
migration_file = Path(__file__).parent / "APPLY_SILVER_TO_GOLD_TRIGGERS.sql"
print("=" * 80)
print("🚀 APPLYING SILVER → GOLD MIGRATION")
print("=" * 80)
print()
print(f"📖 Reading migration file: {migration_file}")

with open(migration_file, 'r') as f:
    sql = f.read()

print(f"   ✅ Read {len(sql)} characters ({len(sql.splitlines())} lines)")
print()

# Method 1: Try Supabase Management API
if SUPABASE_ACCESS_TOKEN:
    print("🔌 Attempting via Supabase Management API...")
    
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
        
        if response.status_code in [200, 201]:
            print("✅ Migration executed via Management API!")
            result = response.json()
            print(f"   Response: {result}")
            print()
            print("✅ Silver → Gold triggers should now be active!")
            sys.exit(0)
        else:
            print(f"   ⚠️  API returned status {response.status_code}")
            print(f"   Response: {response.text[:200]}")
            print()
    except Exception as e:
        print(f"   ⚠️  Management API failed: {e}")
        print()

# Method 2: Try Supabase REST API (PostgREST) - won't work for DDL, but let's try
print("🔌 Attempting via Supabase REST API (PostgREST)...")
print("   ⚠️  Note: PostgREST doesn't support DDL, but checking anyway...")

# This won't work for CREATE FUNCTION/TRIGGER, but let's document it
print("   ❌ PostgREST doesn't support DDL operations (CREATE FUNCTION, etc.)")
print()

# Method 3: Try direct PostgreSQL connection with different parameters
print("🔌 Attempting direct PostgreSQL connection...")

import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from urllib.parse import quote_plus

DB_PASSWORD = os.getenv('DATABASE_PASSWORD', '')

if DB_PASSWORD:
    encoded_password = quote_plus(DB_PASSWORD)
    
    # Try different connection strings
    conn_strings = [
        # Direct connection
        f"postgresql://postgres:{encoded_password}@db.{project_ref}.supabase.co:5432/postgres",
        # Connection pooler (transaction mode)
        f"postgresql://postgres.{project_ref}:{encoded_password}@aws-0-us-west-1.pooler.supabase.com:6543/postgres",
        # Connection pooler (session mode)
        f"postgresql://postgres.{project_ref}:{encoded_password}@aws-0-us-west-1.pooler.supabase.com:5432/postgres",
    ]
    
    for i, conn_string in enumerate(conn_strings, 1):
        print(f"   Trying connection {i}/{len(conn_strings)}...")
        try:
            conn = psycopg2.connect(conn_string, connect_timeout=10)
            conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
            cursor = conn.cursor()
            
            print("   ✅ Connected!")
            print("   🚀 Executing migration...")
            
            cursor.execute(sql)
            
            print("   ✅ Migration executed!")
            
            # Verify
            cursor.execute("""
                SELECT EXISTS (
                    SELECT 1 FROM pg_proc 
                    WHERE proname = 'process_silver_to_gold'
                );
            """)
            function_exists = cursor.fetchone()[0]
            
            cursor.execute("""
                SELECT EXISTS (
                    SELECT 1 FROM pg_trigger 
                    WHERE tgname = 'trigger_silver_to_gold'
                );
            """)
            trigger_exists = cursor.fetchone()[0]
            
            if function_exists and trigger_exists:
                print("   ✅ Verification successful!")
                print("      ✅ Function 'process_silver_to_gold' exists")
                print("      ✅ Trigger 'trigger_silver_to_gold' exists")
                print()
                print("=" * 80)
                print("🎉 MIGRATION APPLIED SUCCESSFULLY!")
                print("=" * 80)
                print()
                print("📊 Silver → Gold pipeline is now active!")
                print("   When logiqs_raw_data is inserted/updated:")
                print("   → employment_information (taxpayer + spouse)")
                print("   → household_information")
                print("   → monthly_expenses (all categories)")
                print("   → income_sources (all types)")
                print("   → financial_accounts")
                print("   → vehicles_v2")
                print("   → real_property_v2")
                print()
                
                cursor.close()
                conn.close()
                sys.exit(0)
            else:
                print("   ⚠️  Migration executed but verification failed")
                if not function_exists:
                    print("      ❌ Function not found")
                if not trigger_exists:
                    print("      ❌ Trigger not found")
            
            cursor.close()
            conn.close()
            break
            
        except psycopg2.OperationalError as e:
            print(f"   ❌ Connection failed: {str(e)[:100]}")
            if i < len(conn_strings):
                continue
        except Exception as e:
            print(f"   ❌ Error: {str(e)[:100]}")
            import traceback
            traceback.print_exc()
            if i < len(conn_strings):
                continue

print()
print("=" * 80)
print("⚠️  COULD NOT APPLY MIGRATION AUTOMATICALLY")
print("=" * 80)
print()
print("📋 Please apply manually via Supabase SQL Editor:")
print()
print("   1. Open: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql")
print("   2. Click 'New query'")
print("   3. Open file: APPLY_SILVER_TO_GOLD_TRIGGERS.sql")
print("   4. Copy ALL contents (Cmd+A, Cmd+C)")
print("   5. Paste into SQL Editor")
print("   6. Click 'Run' (or Cmd+Enter)")
print()
print("💡 The file is located at:")
print(f"   {migration_file.absolute()}")
print()
sys.exit(1)

