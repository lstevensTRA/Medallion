#!/usr/bin/env python3
"""
Apply migration via Supabase REST API SQL execution
"""

import os
import sys
import requests
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY")
    sys.exit(1)

# Read migration file
migration_file = "APPLY_INTERVIEW_AND_EXCEL_MIGRATIONS.sql"
print(f"📖 Reading {migration_file}...")

with open(migration_file, 'r') as f:
    sql = f.read()

# Supabase REST API doesn't support raw SQL execution directly
# We need to use the Management API or psql
# Let's try using the Supabase Management API endpoint

print("🔌 Attempting to execute via Supabase API...")

# Try using the SQL execution endpoint (if available)
# Note: This may not work as Supabase REST API doesn't expose raw SQL execution
# We'll need to use psql or the Supabase CLI

print("⚠️  Supabase REST API doesn't support raw SQL execution")
print("   Trying alternative method...")

# Alternative: Use Supabase CLI db execute
import subprocess

try:
    print("🚀 Executing via Supabase CLI...")
    result = subprocess.run(
        ["supabase", "db", "execute", "--file", migration_file],
        capture_output=True,
        text=True,
        timeout=120
    )
    
    if result.returncode == 0:
        print("✅ Migration executed successfully!")
        print(result.stdout)
    else:
        print("❌ Migration failed:")
        print(result.stderr)
        print("\n💡 Trying manual application...")
        raise Exception("CLI execution failed")
        
except Exception as e:
    print(f"⚠️  CLI method failed: {e}")
    print("\n" + "="*60)
    print("📋 MANUAL APPLICATION REQUIRED")
    print("="*60)
    print("\nSupabase doesn't support raw SQL via REST API.")
    print("Please apply manually:\n")
    print("1. Open: https://supabase.com/dashboard")
    print("2. Go to: SQL Editor")
    print(f"3. Copy contents of: {migration_file}")
    print("4. Paste and click 'Run'")
    print(f"\nFile location: {os.path.abspath(migration_file)}")
    print(f"File size: {os.path.getsize(migration_file)} bytes")

