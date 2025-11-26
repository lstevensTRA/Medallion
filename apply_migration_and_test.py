#!/usr/bin/env python3
"""
Apply Silver → Gold Migration and Test Complete Pipeline

This script:
1. Attempts to apply the migration via Supabase
2. Runs the complete pipeline test
"""

import sys
import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
env_path = Path(__file__).parent / ".env"
load_dotenv(env_path)

SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_KEY')

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ Missing SUPABASE_URL or SUPABASE_KEY in .env")
    sys.exit(1)

print("=" * 80)
print("🚀 APPLY MIGRATION & TEST COMPLETE PIPELINE")
print("=" * 80)
print()

# Step 1: Show migration instructions
print("STEP 1: Apply Silver → Gold Migration")
print("-" * 80)
print()
print("📋 To apply the migration:")
print("   1. Open: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql")
print("   2. Click 'New query'")
print("   3. Open file: APPLY_SILVER_TO_GOLD_TRIGGERS.sql")
print("   4. Copy ALL contents (Cmd+A, Cmd+C)")
print("   5. Paste into Supabase SQL Editor")
print("   6. Click 'Run' (or Cmd+Enter)")
print()
print("💡 The migration file is ready at:")
print(f"   {Path(__file__).parent / 'APPLY_SILVER_TO_GOLD_TRIGGERS.sql'}")
print()

response = input("Have you applied the migration? (y/n): ")
if response.lower() != 'y':
    print()
    print("⏸️  Please apply the migration first, then run this script again.")
    print("   Or run: python3 test_complete_pipeline.py 1295022")
    sys.exit(0)

print()
print("✅ Proceeding with test...")
print()

# Step 2: Run the test
print("STEP 2: Running Complete Pipeline Test")
print("-" * 80)
print()

# Import and run the test
try:
    from test_complete_pipeline import main as test_main
    
    # Get case ID from command line or use default
    case_id = sys.argv[1] if len(sys.argv) > 1 else "1295022"
    
    # Modify sys.argv for the test script
    sys.argv = ['test_complete_pipeline.py', case_id]
    
    test_main()
    
except KeyboardInterrupt:
    print()
    print("❌ Test cancelled by user")
    sys.exit(1)
except Exception as e:
    print()
    print(f"❌ Error running test: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

