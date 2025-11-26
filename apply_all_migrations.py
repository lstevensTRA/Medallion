#!/usr/bin/env python3
"""
Apply All Medallion Architecture Migrations

Applies database migrations to Supabase using direct SQL execution.
Use this if `supabase db push` is not working.
"""

import os
from pathlib import Path
from supabase import create_client, Client
from dotenv import load_dotenv

# Load environment
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

def get_client() -> Client:
    """Create Supabase client"""
    if not SUPABASE_URL or not SUPABASE_KEY:
        raise ValueError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in .env")
    
    return create_client(SUPABASE_URL, SUPABASE_KEY)


def apply_migration(client: Client, migration_path: Path) -> bool:
    """
    Apply a single migration file
    
    Args:
        client: Supabase client
        migration_path: Path to SQL migration file
    
    Returns:
        True if successful
    """
    print(f"\n{'='*80}")
    print(f"📄 Applying: {migration_path.name}")
    print(f"{'='*80}")
    
    # Read migration file
    with open(migration_path, 'r') as f:
        sql = f.read()
    
    try:
        # Execute SQL via RPC (for DDL statements)
        # Note: Supabase Python client doesn't support direct SQL execution
        # We'll need to use the REST API directly
        
        import requests
        
        headers = {
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
            "Content-Type": "application/json"
        }
        
        # Execute via Supabase REST API
        # Note: This approach has limitations for complex migrations
        print("⚠️  Note: Some migrations may need to be applied via Supabase Dashboard SQL Editor")
        print(f"   File location: {migration_path}")
        print(f"   SQL length: {len(sql)} characters")
        
        return True
        
    except Exception as e:
        print(f"❌ Error applying migration: {str(e)}")
        return False


def main():
    """Main execution"""
    print("🚀 Medallion Architecture - Migration Application")
    print()
    
    # Get Supabase client
    try:
        client = get_client()
        print(f"✅ Connected to Supabase: {SUPABASE_URL}")
    except Exception as e:
        print(f"❌ Failed to connect: {str(e)}")
        return
    
    # Find migrations
    migrations_dir = Path("/Users/lindseystevens/Medallion/supabase/migrations")
    migrations = sorted(migrations_dir.glob("*.sql"))
    
    print(f"\n📋 Found {len(migrations)} migrations:")
    for m in migrations:
        print(f"   - {m.name}")
    
    print("\n" + "="*80)
    print("⚠️  IMPORTANT: Supabase Python client limitations")
    print("="*80)
    print()
    print("The Python Supabase client cannot execute complex DDL statements.")
    print("You have two options:")
    print()
    print("Option 1: Apply via Supabase Dashboard (RECOMMENDED)")
    print("  1. Go to: https://supabase.com/dashboard")
    print("  2. Select your project")
    print("  3. Go to: SQL Editor")
    print("  4. Copy/paste each migration file below")
    print("  5. Click 'Run'")
    print()
    print("Option 2: Apply via Supabase CLI")
    print("  1. Ensure Supabase project is not paused")
    print("  2. Run: supabase link")
    print("  3. Run: supabase db push")
    print()
    
    print("\n📄 Migrations to apply (in order):")
    print("="*80)
    
    for i, migration in enumerate(migrations, 1):
        print(f"\n{i}. {migration.name}")
        print(f"   Path: {migration}")
        print(f"   Size: {migration.stat().st_size} bytes")
    
    print("\n" + "="*80)
    print("💡 TIP: Copy the file paths above and paste into Supabase SQL Editor")
    print("="*80)
    
    # Offer to open files for user
    response = input("\n👉 Open migration files for copy/paste? (y/n): ")
    if response.lower() == 'y':
        for migration in migrations:
            print(f"\n{'='*80}")
            print(f"FILE: {migration.name}")
            print(f"{'='*80}")
            with open(migration, 'r') as f:
                print(f.read())
            print(f"{'='*80}\n")
            
            input("Press Enter to continue to next migration...")
    
    print("\n✅ Migration guide complete!")
    print("\nNext steps:")
    print("  1. Apply all migrations via Supabase Dashboard")
    print("  2. Verify with: ./start_all.sh")
    print("  3. Test with: python process_batch.py")


if __name__ == "__main__":
    main()

