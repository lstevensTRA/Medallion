#!/usr/bin/env python3
"""
Apply Silver → Gold trigger migration directly to Supabase
"""

import os
import sys
from dotenv import load_dotenv
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from urllib.parse import quote_plus

# Load environment variables
load_dotenv()

SUPABASE_URL = os.getenv('SUPABASE_URL', '')
DB_PASSWORD = os.getenv('DATABASE_PASSWORD', '')

if not SUPABASE_URL or not DB_PASSWORD:
    print("❌ Missing SUPABASE_URL or DATABASE_PASSWORD in .env")
    sys.exit(1)

# Extract host from URL
host = SUPABASE_URL.replace('https://', '').replace('http://', '').replace('.supabase.co', '')

# URL-encode the password to handle special characters
encoded_password = quote_plus(DB_PASSWORD)

# Construct connection string (using direct connection, not pooler)
conn_string = f"postgresql://postgres:{encoded_password}@db.{host}.supabase.co:5432/postgres"

print("🔌 Connecting to Supabase database...")

try:
    # Connect to database
    conn = psycopg2.connect(conn_string, connect_timeout=10)
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cursor = conn.cursor()
    
    print("✅ Connected to database")
    
    # Read migration file
    migration_file = "APPLY_SILVER_TO_GOLD_TRIGGERS.sql"
    print(f"📖 Reading migration file: {migration_file}")
    
    with open(migration_file, 'r') as f:
        sql = f.read()
    
    print("🚀 Executing migration...")
    print("   (This may take a moment...)")
    
    # Execute SQL
    cursor.execute(sql)
    
    print("✅ Migration executed successfully!")
    
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
        print("✅ Function 'process_silver_to_gold' verified!")
        print("✅ Trigger 'trigger_silver_to_gold' verified!")
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
    else:
        print("⚠️  Function or trigger may not have been created - check for errors above")
        if not function_exists:
            print("   ❌ Function 'process_silver_to_gold' not found")
        if not trigger_exists:
            print("   ❌ Trigger 'trigger_silver_to_gold' not found")
    
    cursor.close()
    conn.close()
    
    print("\n🎉 Migration complete!")
    
except psycopg2.OperationalError as e:
    print(f"❌ Connection error: {e}")
    print("\n💡 Alternative: Run SQL manually via Supabase Dashboard")
    print("   1. Go to: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql")
    print("   2. Copy contents of: APPLY_SILVER_TO_GOLD_TRIGGERS.sql")
    print("   3. Paste and run")
    sys.exit(1)
    
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
    print("\n💡 Alternative: Run SQL manually via Supabase Dashboard")
    print("   1. Go to: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql")
    print("   2. Copy contents of: APPLY_SILVER_TO_GOLD_TRIGGERS.sql")
    print("   3. Paste and run")
    sys.exit(1)

