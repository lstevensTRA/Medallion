#!/usr/bin/env python3
"""
Apply the interview extraction and Excel formula migration directly to Supabase
"""

import os
import sys
from dotenv import load_dotenv
from supabase import create_client

# Load environment variables
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env")
    sys.exit(1)

print("🔌 Connecting to Supabase...")
client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Read the migration file
migration_file = "APPLY_INTERVIEW_AND_EXCEL_MIGRATIONS.sql"
print(f"📖 Reading migration file: {migration_file}")

try:
    with open(migration_file, 'r') as f:
        sql = f.read()
    
    print("🚀 Executing migration...")
    print("   (This may take a minute...)")
    
    # Execute via Supabase REST API (rpc call)
    # Note: Supabase Python client doesn't support raw SQL directly
    # We need to use the REST API or provide instructions
    
    print("\n⚠️  Supabase Python client doesn't support raw SQL execution.")
    print("   Please apply the migration manually:\n")
    print("   1. Open Supabase Dashboard → SQL Editor")
    print(f"   2. Copy contents of: {migration_file}")
    print("   3. Paste and click 'Run'")
    print("\n   OR use psql if you have database credentials:\n")
    print(f"   psql $DATABASE_URL -f {migration_file}")
    
    # Try to check if we can use the REST API
    # Actually, let's just provide clear instructions and verify the file exists
    
    if os.path.exists(migration_file):
        file_size = os.path.getsize(migration_file)
        print(f"\n✅ Migration file found ({file_size} bytes)")
        print(f"   Location: {os.path.abspath(migration_file)}")
    else:
        print(f"\n❌ Migration file not found: {migration_file}")
        sys.exit(1)
    
except FileNotFoundError:
    print(f"❌ Migration file not found: {migration_file}")
    sys.exit(1)
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)

print("\n" + "="*60)
print("📋 MIGRATION READY TO APPLY")
print("="*60)
print(f"\nFile: {migration_file}")
print(f"Size: {file_size} bytes")
print(f"Lines: {len(sql.splitlines())} lines")
print("\nNext step: Apply in Supabase SQL Editor")

