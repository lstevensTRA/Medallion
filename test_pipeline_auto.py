#!/usr/bin/env python3
"""
Auto Test Complete Pipeline - Non-Interactive
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


def trigger_bronze_ingestion(case_id: str):
    """Trigger Bronze ingestion via Dagster"""
    print(f"🚀 Triggering Bronze ingestion for case: {case_id}")
    print()
    
    try:
        from trigger_case_ingestion import trigger_case_ingestion
        success = trigger_case_ingestion(case_id)
        return success
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def check_all_layers(case_id: str):
    """Check all layers and return results"""
    print("🔍 Checking All Layers...")
    print()
    
    results = {
        'bronze': {},
        'silver': {},
        'gold': {}
    }
    
    # Get case UUID
    try:
        case_response = supabase.table('cases').select('id').eq('case_number', case_id).limit(1).execute()
        if case_response.data:
            case_uuid = case_response.data[0]['id']
        else:
            # Try direct UUID lookup
            case_uuid = case_id
    except:
        case_uuid = case_id
    
    # Bronze Layer
    print("🥉 Bronze Layer:")
    bronze_tables = ['bronze_at_raw', 'bronze_wi_raw', 'bronze_trt_raw', 'bronze_interview_raw']
    for table in bronze_tables:
        try:
            response = supabase.table(table).select('*', count='exact').eq('case_id', case_id).execute()
            count = response.count if hasattr(response, 'count') else len(response.data)
            results['bronze'][table] = count
            status = "✅" if count > 0 else "❌"
            print(f"   {status} {table}: {count} record(s)")
        except Exception as e:
            results['bronze'][table] = 0
            print(f"   ❌ {table}: Error - {str(e)[:50]}")
    print()
    
    # Silver Layer
    print("🥈 Silver Layer:")
    silver_tables = {
        'tax_years': 'case_id',
        'account_activity': 'case_id',
        'income_documents': 'case_id',
        'logiqs_raw_data': 'case_id'
    }
    for table, id_column in silver_tables.items():
        try:
            response = supabase.table(table).select('*', count='exact').eq(id_column, case_uuid).execute()
            count = response.count if hasattr(response, 'count') else len(response.data)
            results['silver'][table] = count
            status = "✅" if count > 0 else "❌"
            print(f"   {status} {table}: {count} record(s)")
        except Exception as e:
            results['silver'][table] = 0
            print(f"   ❌ {table}: Error - {str(e)[:50]}")
    print()
    
    # Gold Layer
    print("🥇 Gold Layer:")
    gold_tables = {
        'employment_information': 'case_id',
        'household_information': 'case_id',
        'monthly_expenses': 'case_id',
        'income_sources': 'case_id',
        'financial_accounts': 'case_id',
        'vehicles_v2': 'case_id',
        'real_property_v2': 'case_id'
    }
    for table, id_column in gold_tables.items():
        try:
            response = supabase.table(table).select('*', count='exact').eq(id_column, case_uuid).execute()
            count = response.count if hasattr(response, 'count') else len(response.data)
            results['gold'][table] = count
            status = "✅" if count > 0 else "❌"
            print(f"   {status} {table}: {count} record(s)")
        except Exception as e:
            results['gold'][table] = 0
            print(f"   ❌ {table}: Error - {str(e)[:50]}")
    print()
    
    return results


def main():
    case_id = sys.argv[1] if len(sys.argv) > 1 else "1295022"
    
    print("=" * 80)
    print("🧪 AUTO TEST: Complete Pipeline - Bronze → Silver → Gold")
    print("=" * 80)
    print()
    print(f"📋 Testing with case ID: {case_id}")
    print()
    
    # Step 1: Check current state
    print("STEP 1: Current State")
    print("-" * 80)
    initial_results = check_all_layers(case_id)
    
    # Step 2: Trigger Bronze ingestion
    print("STEP 2: Trigger Bronze Ingestion")
    print("-" * 80)
    print("🚀 Triggering Bronze ingestion...")
    success = trigger_bronze_ingestion(case_id)
    
    if not success:
        print("❌ Bronze ingestion failed!")
        print()
        print("📊 Current State Summary:")
        print_summary(initial_results)
        sys.exit(1)
    
    # Wait for triggers
    print()
    print("⏳ Waiting 10 seconds for triggers to process...")
    time.sleep(10)
    print()
    
    # Step 3: Check final state
    print("STEP 3: Final State After Ingestion")
    print("-" * 80)
    final_results = check_all_layers(case_id)
    
    # Step 4: Summary
    print("=" * 80)
    print("📊 TEST SUMMARY")
    print("=" * 80)
    print()
    print_summary(final_results)
    
    # Step 5: What's Missing
    print("=" * 80)
    print("🔍 WHAT'S MISSING")
    print("=" * 80)
    print()
    analyze_missing(final_results, case_id)


def print_summary(results):
    bronze_total = sum(results['bronze'].values())
    silver_total = sum(results['silver'].values())
    gold_total = sum(results['gold'].values())
    
    print(f"🥉 Bronze Layer: {bronze_total} total records")
    for table, count in results['bronze'].items():
        status = "✅" if count > 0 else "❌"
        print(f"   {status} {table}: {count}")
    print()
    
    print(f"🥈 Silver Layer: {silver_total} total records")
    for table, count in results['silver'].items():
        status = "✅" if count > 0 else "❌"
        print(f"   {status} {table}: {count}")
    print()
    
    print(f"🥇 Gold Layer: {gold_total} total records")
    for table, count in results['gold'].items():
        status = "✅" if count > 0 else "❌"
        print(f"   {status} {table}: {count}")
    print()


def analyze_missing(results, case_id):
    issues = []
    
    # Check Bronze
    if results['bronze']['bronze_at_raw'] == 0:
        issues.append("❌ Bronze AT data not ingested")
    if results['bronze']['bronze_wi_raw'] == 0:
        issues.append("❌ Bronze WI data not ingested")
    if results['bronze']['bronze_interview_raw'] == 0:
        issues.append("❌ Bronze Interview data not ingested")
    
    # Check Silver
    if results['bronze']['bronze_at_raw'] > 0 and results['silver']['tax_years'] == 0:
        issues.append("⚠️  Bronze → Silver trigger not working for AT data")
    if results['bronze']['bronze_wi_raw'] > 0 and results['silver']['income_documents'] == 0:
        issues.append("⚠️  Bronze → Silver trigger not working for WI data")
    if results['bronze']['bronze_interview_raw'] > 0 and results['silver']['logiqs_raw_data'] == 0:
        issues.append("⚠️  Bronze → Silver trigger not working for Interview data")
    
    # Check Gold
    if results['silver']['logiqs_raw_data'] > 0 and results['gold']['employment_information'] == 0:
        issues.append("⚠️  Silver → Gold trigger not working (employment_information empty)")
    if results['silver']['logiqs_raw_data'] > 0 and results['gold']['monthly_expenses'] == 0:
        issues.append("⚠️  Silver → Gold trigger not working (monthly_expenses empty)")
    
    if not issues:
        print("✅ Everything looks good! All layers populated.")
        print()
        print("🎉 SUCCESS! Complete pipeline is working!")
        print("   Bronze → Silver → Gold (all layers populated)")
    else:
        print("Found the following issues:")
        print()
        for issue in issues:
            print(f"   {issue}")
        print()
        print("💡 Recommendations:")
        print()
        
        if "Bronze" in str(issues):
            print("   • Check Dagster assets are running correctly")
            print("   • Verify API keys in .env")
            print("   • Check Dagster UI: http://localhost:3000")
        
        if "Bronze → Silver" in str(issues):
            print("   • Check Bronze → Silver triggers are active:")
            print("     SELECT tgname FROM pg_trigger WHERE tgname LIKE 'trigger_bronze%';")
        
        if "Silver → Gold" in str(issues):
            print("   • Check Silver → Gold trigger is active:")
            print("     SELECT tgname FROM pg_trigger WHERE tgname = 'trigger_silver_to_gold';")
            print("   • Verify logiqs_raw_data has data for this case")
            print("   • Check if trigger function exists:")
            print("     SELECT proname FROM pg_proc WHERE proname = 'process_silver_to_gold';")
    
    print()


if __name__ == "__main__":
    main()

