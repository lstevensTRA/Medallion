#!/usr/bin/env python3
"""
Test Complete Pipeline: Bronze → Silver → Gold

This script:
1. Checks if Silver → Gold trigger is applied
2. Triggers Bronze ingestion for a case
3. Verifies all layers are populated correctly
"""

import sys
import time
from pathlib import Path
from dotenv import load_dotenv
from supabase import create_client, Client

# Load environment variables
env_path = Path(__file__).parent / ".env"
load_dotenv(env_path)

import os
SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_KEY')

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ Missing SUPABASE_URL or SUPABASE_KEY in .env")
    sys.exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)


def check_silver_to_gold_trigger():
    """Check if Silver → Gold trigger is applied"""
    print("🔍 Checking Silver → Gold trigger status...")
    
    try:
        # Check if we can query employment_information (Gold table)
        # If trigger is working, we should be able to query it
        response = supabase.table('employment_information').select('*', count='exact').limit(1).execute()
        table_exists = True
        
        # Check if logiqs_raw_data exists (Silver table)
        silver_response = supabase.table('logiqs_raw_data').select('*', count='exact').limit(1).execute()
        
        print(f"   ✅ Gold table 'employment_information' exists")
        print(f"   ✅ Silver table 'logiqs_raw_data' exists")
        print()
        print("   ⚠️  Cannot directly verify trigger via Supabase client")
        print("   💡 To verify trigger, run in Supabase SQL Editor:")
        print("      SELECT tgname FROM pg_trigger WHERE tgname = 'trigger_silver_to_gold';")
        print()
        print("   📋 If trigger is NOT applied, paste this file in SQL Editor:")
        print("      APPLY_SILVER_TO_GOLD_TRIGGERS.sql")
        print()
        return None  # Return None to allow test to continue
        
    except Exception as e:
        print(f"   ⚠️  Could not verify: {e}")
        print("   💡 Please apply migration: APPLY_SILVER_TO_GOLD_TRIGGERS.sql")
        print()
        return None  # Return None to allow test to continue anyway


def trigger_bronze_ingestion(case_id: str):
    """Trigger Bronze ingestion via Dagster"""
    print(f"🚀 Triggering Bronze ingestion for case: {case_id}")
    print()
    
    try:
        # Import trigger script
        from trigger_case_ingestion import trigger_case_ingestion
        
        success = trigger_case_ingestion(case_id)
        
        if success:
            print("✅ Bronze ingestion completed!")
            print()
            return True
        else:
            print("❌ Bronze ingestion failed!")
            print()
            return False
            
    except Exception as e:
        print(f"❌ Error triggering ingestion: {e}")
        print()
        import traceback
        traceback.print_exc()
        return False


def verify_bronze_layer(case_id: str):
    """Verify Bronze layer is populated"""
    print("🔍 Verifying Bronze Layer...")
    
    bronze_tables = [
        'bronze_at_raw',
        'bronze_wi_raw',
        'bronze_trt_raw',
        'bronze_interview_raw'
    ]
    
    results = {}
    
    for table in bronze_tables:
        try:
            response = supabase.table(table).select('*', count='exact').eq('case_id', case_id).execute()
            count = response.count if hasattr(response, 'count') else len(response.data)
            results[table] = count
            status = "✅" if count > 0 else "❌"
            print(f"   {status} {table}: {count} record(s)")
        except Exception as e:
            results[table] = 0
            print(f"   ❌ {table}: Error - {e}")
    
    print()
    return results


def verify_silver_layer(case_id: str):
    """Verify Silver layer is populated"""
    print("🔍 Verifying Silver Layer...")
    
    # Get case UUID first
    try:
        case_response = supabase.table('cases').select('id').eq('case_number', case_id).limit(1).execute()
        if not case_response.data:
            print(f"   ⚠️  Case {case_id} not found in cases table")
            print("   💡 Using case_id directly for verification")
            case_uuid = case_id
        else:
            case_uuid = case_response.data[0]['id']
    except:
        case_uuid = case_id
    
    silver_tables = {
        'tax_years': 'case_id',
        'account_activity': 'case_id',
        'income_documents': 'case_id',
        'logiqs_raw_data': 'case_id'
    }
    
    results = {}
    
    for table, id_column in silver_tables.items():
        try:
            response = supabase.table(table).select('*', count='exact').eq(id_column, case_uuid).execute()
            count = response.count if hasattr(response, 'count') else len(response.data)
            results[table] = count
            status = "✅" if count > 0 else "❌"
            print(f"   {status} {table}: {count} record(s)")
        except Exception as e:
            results[table] = 0
            print(f"   ❌ {table}: Error - {e}")
    
    print()
    return results


def verify_gold_layer(case_id: str):
    """Verify Gold layer is populated"""
    print("🔍 Verifying Gold Layer...")
    
    # Get case UUID first
    try:
        case_response = supabase.table('cases').select('id').eq('case_number', case_id).limit(1).execute()
        if not case_response.data:
            print(f"   ⚠️  Case {case_id} not found in cases table")
            print("   💡 Using case_id directly for verification")
            case_uuid = case_id
        else:
            case_uuid = case_response.data[0]['id']
    except:
        case_uuid = case_id
    
    gold_tables = {
        'employment_information': 'case_id',
        'household_information': 'case_id',
        'monthly_expenses': 'case_id',
        'income_sources': 'case_id',
        'financial_accounts': 'case_id',
        'vehicles_v2': 'case_id',
        'real_property_v2': 'case_id'
    }
    
    results = {}
    
    for table, id_column in gold_tables.items():
        try:
            response = supabase.table(table).select('*', count='exact').eq(id_column, case_uuid).execute()
            count = response.count if hasattr(response, 'count') else len(response.data)
            results[table] = count
            status = "✅" if count > 0 else "❌"
            print(f"   {status} {table}: {count} record(s)")
        except Exception as e:
            results[table] = 0
            print(f"   ❌ {table}: Error - {e}")
    
    print()
    return results


def main():
    """Main test function"""
    print("=" * 80)
    print("🧪 COMPLETE PIPELINE TEST: Bronze → Silver → Gold")
    print("=" * 80)
    print()
    
    # Get case ID from command line
    if len(sys.argv) < 2:
        case_id = "1295022"
        print(f"⚠️  No case ID provided, using default: {case_id}")
        print()
    else:
        case_id = sys.argv[1]
    
    print(f"📋 Testing with case ID: {case_id}")
    print()
    
    # Step 1: Check Silver → Gold trigger
    print("STEP 1: Check Silver → Gold Trigger")
    print("-" * 80)
    trigger_status = check_silver_to_gold_trigger()
    
    if trigger_status is False:
        print("⚠️  Silver → Gold trigger not found!")
        print()
        print("📋 To apply the trigger:")
        print("   1. Open: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/sql")
        print("   2. Paste contents of: APPLY_SILVER_TO_GOLD_TRIGGERS.sql")
        print("   3. Run the query")
        print()
        response = input("Continue with test anyway? (y/n): ")
        if response.lower() != 'y':
            print("❌ Test cancelled")
            sys.exit(1)
        print()
    
    # Step 2: Trigger Bronze ingestion
    print("STEP 2: Trigger Bronze Ingestion")
    print("-" * 80)
    response = input(f"Trigger Bronze ingestion for case {case_id}? (y/n): ")
    if response.lower() != 'y':
        print("⏭️  Skipping Bronze ingestion")
        print()
    else:
        success = trigger_bronze_ingestion(case_id)
        if not success:
            print("❌ Bronze ingestion failed. Check errors above.")
            sys.exit(1)
        
        # Wait a bit for triggers to fire
        print("⏳ Waiting 5 seconds for triggers to process...")
        time.sleep(5)
        print()
    
    # Step 3: Verify Bronze Layer
    print("STEP 3: Verify Bronze Layer")
    print("-" * 80)
    bronze_results = verify_bronze_layer(case_id)
    
    # Step 4: Verify Silver Layer
    print("STEP 4: Verify Silver Layer")
    print("-" * 80)
    silver_results = verify_silver_layer(case_id)
    
    # Step 5: Verify Gold Layer
    print("STEP 5: Verify Gold Layer")
    print("-" * 80)
    gold_results = verify_gold_layer(case_id)
    
    # Summary
    print("=" * 80)
    print("📊 TEST SUMMARY")
    print("=" * 80)
    print()
    
    bronze_total = sum(bronze_results.values())
    silver_total = sum(silver_results.values())
    gold_total = sum(gold_results.values())
    
    print(f"🥉 Bronze Layer: {bronze_total} total records")
    for table, count in bronze_results.items():
        status = "✅" if count > 0 else "❌"
        print(f"   {status} {table}: {count}")
    print()
    
    print(f"🥈 Silver Layer: {silver_total} total records")
    for table, count in silver_results.items():
        status = "✅" if count > 0 else "❌"
        print(f"   {status} {table}: {count}")
    print()
    
    print(f"🥇 Gold Layer: {gold_total} total records")
    for table, count in gold_results.items():
        status = "✅" if count > 0 else "❌"
        print(f"   {status} {table}: {count}")
    print()
    
    # Final verdict
    if bronze_total > 0 and silver_total > 0 and gold_total > 0:
        print("🎉 SUCCESS! Complete pipeline is working!")
        print("   Bronze → Silver → Gold (all layers populated)")
    elif bronze_total > 0 and silver_total > 0:
        print("⚠️  PARTIAL SUCCESS")
        print("   Bronze → Silver working, but Gold not populated")
        print("   💡 Apply Silver → Gold trigger migration")
    elif bronze_total > 0:
        print("⚠️  PARTIAL SUCCESS")
        print("   Bronze populated, but Silver not populated")
        print("   💡 Check Bronze → Silver triggers")
    else:
        print("❌ FAILED")
        print("   Bronze layer not populated")
        print("   💡 Check Dagster assets and API connections")
    
    print()


if __name__ == "__main__":
    main()

