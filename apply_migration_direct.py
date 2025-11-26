#!/usr/bin/env python3
"""
Apply Silver → Gold Migration Directly via Database Connection
"""

import os
import sys
from pathlib import Path
from dotenv import load_dotenv
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from urllib.parse import quote_plus

# Load environment variables
env_path = Path(__file__).parent / ".env"
load_dotenv(env_path)

SUPABASE_URL = os.getenv('SUPABASE_URL', '')
DB_PASSWORD = os.getenv('DATABASE_PASSWORD', '')

if not SUPABASE_URL or not DB_PASSWORD:
    print("❌ Missing SUPABASE_URL or DATABASE_PASSWORD in .env")
    sys.exit(1)

# Extract host from URL
host = SUPABASE_URL.replace('https://', '').replace('http://', '').replace('.supabase.co', '')

# URL-encode the password
encoded_password = quote_plus(DB_PASSWORD)

# Try direct connection first
conn_strings = [
    f"postgresql://postgres:{encoded_password}@db.{host}.supabase.co:5432/postgres",
    f"postgresql://postgres:{encoded_password}@aws-0-us-west-1.pooler.supabase.com:6543/postgres",
]

print("=" * 80)
print("🚀 APPLYING SILVER → GOLD MIGRATION")
print("=" * 80)
print()

# Read migration file
migration_file = Path(__file__).parent / "APPLY_SILVER_TO_GOLD_TRIGGERS.sql"
print(f"📖 Reading migration file: {migration_file}")

with open(migration_file, 'r') as f:
    sql = f.read()

print(f"   ✅ Read {len(sql)} characters")
print()

# Try to connect and apply
success = False
for i, conn_string in enumerate(conn_strings, 1):
    print(f"🔌 Attempting connection {i}/{len(conn_strings)}...")
    
    try:
        conn = psycopg2.connect(conn_string, connect_timeout=10)
        conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
        cursor = conn.cursor()
        
        print("   ✅ Connected!")
        print()
        print("🚀 Executing migration...")
        print("   (This may take a moment...)")
        print()
        
        # Execute SQL
        cursor.execute(sql)
        
        print("✅ Migration executed successfully!")
        print()
        
        # Verify function exists
        cursor.execute("""
            SELECT EXISTS (
                SELECT 1 FROM pg_proc 
                WHERE proname = 'process_silver_to_gold'
            );
        """)
        function_exists = cursor.fetchone()[0]
        
        # Verify trigger exists
        cursor.execute("""
            SELECT EXISTS (
                SELECT 1 FROM pg_trigger 
                WHERE tgname = 'trigger_silver_to_gold'
            );
        """)
        trigger_exists = cursor.fetchone()[0]
        
        if function_exists and trigger_exists:
            print("✅ Verification:")
            print("   ✅ Function 'process_silver_to_gold' exists")
            print("   ✅ Trigger 'trigger_silver_to_gold' exists")
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
            success = True
        else:
            print("⚠️  Migration executed but verification failed:")
            if not function_exists:
                print("   ❌ Function 'process_silver_to_gold' not found")
            if not trigger_exists:
                print("   ❌ Trigger 'trigger_silver_to_gold' not found")
        
        cursor.close()
        conn.close()
        break
        
    except psycopg2.OperationalError as e:
        print(f"   ❌ Connection failed: {e}")
        if i < len(conn_strings):
            print("   Trying next connection method...")
            print()
        else:
            print()
            print("💡 Alternative: Apply migration manually via Supabase SQL Editor")
            print("   1. Open: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql")
            print("   2. Paste contents of: APPLY_SILVER_TO_GOLD_TRIGGERS.sql")
            print("   3. Run query")
            success = False
    except Exception as e:
        print(f"   ❌ Error: {e}")
        import traceback
        traceback.print_exc()
        success = False
        break

print()
if success:
    print("=" * 80)
    print("🎉 MIGRATION APPLIED SUCCESSFULLY!")
    print("=" * 80)
    print()
    print("✅ Ready to test the complete pipeline!")
    sys.exit(0)
else:
    print("=" * 80)
    print("⚠️  COULD NOT APPLY MIGRATION AUTOMATICALLY")
    print("=" * 80)
    print()
    print("📋 Please apply manually:")
    print("   1. Open: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql")
    print("   2. Click 'New query'")
    print("   3. Open file: APPLY_SILVER_TO_GOLD_TRIGGERS.sql")
    print("   4. Copy ALL contents and paste into SQL Editor")
    print("   5. Click 'Run'")
    print()
    sys.exit(1)
