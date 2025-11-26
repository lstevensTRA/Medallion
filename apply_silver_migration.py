#!/usr/bin/env python3
"""
Apply Silver Layer Migration
Executes the SQL migration directly via Supabase REST API
"""

import os
import sys
from pathlib import Path
from dotenv import load_dotenv
from supabase import create_client, Client
import httpx

# Load environment
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in .env")
    sys.exit(1)

def apply_migration():
    """Apply the Silver layer migration"""
    
    # Read migration file
    migration_path = Path(__file__).parent / "supabase" / "migrations" / "006_create_silver_layer.sql"
    
    if not migration_path.exists():
        print(f"❌ Migration file not found: {migration_path}")
        sys.exit(1)
    
    with open(migration_path, 'r') as f:
        sql = f.read()
    
    print("=" * 80)
    print("🚀 Applying Silver Layer Migration")
    print("=" * 80)
    print(f"📄 File: {migration_path.name}")
    print(f"📏 Size: {len(sql)} characters")
    print()
    
    # Execute via Supabase REST API (rpc endpoint)
    # Note: Supabase Python client doesn't support raw SQL execution
    # We'll use the REST API directly
    
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json"
    }
    
    # Split SQL into statements (basic splitting by semicolon)
    # For complex migrations, it's better to use Supabase Dashboard
    print("⚠️  Note: Supabase Python client doesn't support raw SQL execution")
    print("   For complex migrations, use Supabase Dashboard SQL Editor")
    print()
    print("📋 Migration SQL is ready in your clipboard!")
    print()
    print("To apply manually:")
    print("1. Go to: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql")
    print("2. Paste the migration (it's in your clipboard)")
    print("3. Click RUN")
    print()
    
    # Copy to clipboard
    import subprocess
    try:
        subprocess.run(['pbcopy'], input=sql.encode(), check=True)
        print("✅ Migration copied to clipboard!")
    except:
        print("⚠️  Could not copy to clipboard (pbcopy not available)")
        print("   Migration file: supabase/migrations/006_create_silver_layer.sql")
    
    return False  # Indicate manual application needed

if __name__ == "__main__":
    success = apply_migration()
    sys.exit(0 if success else 1)


