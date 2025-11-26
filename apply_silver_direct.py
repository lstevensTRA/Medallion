#!/usr/bin/env python3
"""
Apply Silver Layer Migration via Supabase REST API
"""

import os
import sys
from pathlib import Path
from dotenv import load_dotenv
import httpx
import json

# Load environment
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in .env")
    sys.exit(1)

def apply_migration():
    """Apply the Silver layer migration via REST API"""
    
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
    print()
    
    # Supabase doesn't have a direct SQL execution endpoint via REST
    # We need to use the Dashboard SQL Editor or psql
    
    # However, we can try to execute via the PostgREST API if we break it into smaller statements
    # But complex DDL statements require direct database access
    
    print("⚠️  Supabase REST API doesn't support raw SQL execution")
    print("   Complex migrations must be applied via:")
    print("   1. Supabase Dashboard SQL Editor (recommended)")
    print("   2. Direct psql connection")
    print("   3. Supabase CLI (if project is linked)")
    print()
    
    # Try to use Supabase CLI if linked
    import subprocess
    result = subprocess.run(
        ['supabase', 'db', 'push'],
        cwd=Path(__file__).parent,
        capture_output=True,
        text=True
    )
    
    if result.returncode == 0:
        print("✅ Migration applied via Supabase CLI!")
        return True
    else:
        print("⚠️  Supabase CLI not linked or not available")
        print()
        print("📋 Manual Application Required:")
        print("=" * 80)
        print("1. Open: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql")
        print("2. Paste the migration SQL (copied to clipboard)")
        print("3. Click RUN")
        print()
        
        # Copy to clipboard
        try:
            subprocess.run(['pbcopy'], input=sql.encode(), check=True)
            print("✅ Migration copied to clipboard!")
        except:
            print("⚠️  Could not copy to clipboard")
            print(f"   File: {migration_path}")
        
        return False

if __name__ == "__main__":
    success = apply_migration()
    sys.exit(0 if success else 1)


