#!/usr/bin/env python3
"""
Fix Pipeline Issues - Automated Fix Script

This script:
1. Creates case in cases table if missing
2. Verifies triggers are active
3. Attempts to trigger interview data ingestion
4. Re-tests the pipeline
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


def create_case_if_missing(case_number: str):
    """Create case in cases table if it doesn't exist"""
    print(f"🔍 Checking if case '{case_number}' exists...")
    
    try:
        # Check if case exists
        response = supabase.table('cases').select('id, case_number').eq('case_number', case_number).limit(1).execute()
        
        if response.data:
            case_uuid = response.data[0]['id']
            print(f"   ✅ Case already exists: {case_uuid}")
            return case_uuid
        else:
            # Create case
            print(f"   ⚠️  Case not found, creating...")
            insert_response = supabase.table('cases').insert({
                'case_number': case_number
            }).execute()
            
            if insert_response.data:
                case_uuid = insert_response.data[0]['id']
                print(f"   ✅ Case created: {case_uuid}")
                return case_uuid
            else:
                print(f"   ❌ Failed to create case")
                return None
                
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return None


def verify_triggers():
    """Verify Bronze → Silver triggers exist"""
    print("🔍 Verifying triggers...")
    print()
    
    # We can't directly query pg_trigger via Supabase client
    # But we can check if Silver tables can be populated by checking structure
    print("   ⚠️  Cannot directly verify triggers via Supabase client")
    print("   💡 To verify triggers, run in Supabase SQL Editor:")
    print("      SELECT tgname, tgrelid::regclass FROM pg_trigger WHERE tgname LIKE 'trigger_bronze%';")
    print()
    print("   💡 To verify ensure_case function:")
    print("      SELECT proname FROM pg_proc WHERE proname = 'ensure_case';")
    print()
    
    return True  # Assume triggers exist (they should from migrations)


def trigger_interview_ingestion(case_id: str):
    """Trigger interview data ingestion"""
    print(f"🚀 Attempting to trigger interview data ingestion for case: {case_id}")
    print()
    
    # Check if DAGSTER_HOME is set
    dagster_home = os.getenv('DAGSTER_HOME')
    if not dagster_home:
        print("   ⚠️  DAGSTER_HOME not set")
        print("   💡 Setting DAGSTER_HOME to ~/dagster_home")
        os.environ['DAGSTER_HOME'] = str(Path.home() / 'dagster_home')
        # Create directory if it doesn't exist
        Path(os.environ['DAGSTER_HOME']).mkdir(exist_ok=True)
    
    try:
        from trigger_case_ingestion import trigger_case_ingestion
        print("   ✅ Dagster trigger script found")
        print("   🚀 Triggering interview ingestion...")
        print()
        
        success = trigger_case_ingestion(case_id)
        
        if success:
            print("   ✅ Interview ingestion triggered successfully!")
            return True
        else:
            print("   ⚠️  Interview ingestion may have failed")
            return False
            
    except Exception as e:
        print(f"   ⚠️  Could not trigger via Dagster: {e}")
        print()
        print("   💡 Alternative: Trigger manually via:")
        print(f"      python3 trigger_case_ingestion.py {case_id}")
        print("      OR")
        print("      dagster asset materialize -m dagster_pipeline --select bronze_interview_data")
        return False


def check_pipeline_status(case_id: str, case_uuid: str = None):
    """Check current pipeline status"""
    print("🔍 Checking Pipeline Status...")
    print()
    
    if not case_uuid:
        # Get case UUID
        try:
            response = supabase.table('cases').select('id').eq('case_number', case_id).limit(1).execute()
            if response.data:
                case_uuid = response.data[0]['id']
            else:
                case_uuid = case_id
        except:
            case_uuid = case_id
    
    results = {
        'bronze': {},
        'silver': {},
        'gold': {}
    }
    
    # Bronze
    print("🥉 Bronze Layer:")
    for table in ['bronze_at_raw', 'bronze_wi_raw', 'bronze_trt_raw', 'bronze_interview_raw']:
        try:
            response = supabase.table(table).select('*', count='exact').eq('case_id', case_id).execute()
            count = response.count if hasattr(response, 'count') else len(response.data)
            results['bronze'][table] = count
            status = "✅" if count > 0 else "❌"
            print(f"   {status} {table}: {count} record(s)")
        except Exception as e:
            results['bronze'][table] = 0
            print(f"   ❌ {table}: Error")
    print()
    
    # Silver
    print("🥈 Silver Layer:")
    for table in ['tax_years', 'account_activity', 'income_documents', 'logiqs_raw_data']:
        try:
            response = supabase.table(table).select('*', count='exact').eq('case_id', case_uuid).execute()
            count = response.count if hasattr(response, 'count') else len(response.data)
            results['silver'][table] = count
            status = "✅" if count > 0 else "❌"
            print(f"   {status} {table}: {count} record(s)")
        except Exception as e:
            results['silver'][table] = 0
            print(f"   ❌ {table}: Error")
    print()
    
    # Gold
    print("🥇 Gold Layer:")
    for table in ['employment_information', 'household_information', 'monthly_expenses', 'income_sources']:
        try:
            response = supabase.table(table).select('*', count='exact').eq('case_id', case_uuid).execute()
            count = response.count if hasattr(response, 'count') else len(response.data)
            results['gold'][table] = count
            status = "✅" if count > 0 else "❌"
            print(f"   {status} {table}: {count} record(s)")
        except Exception as e:
            results['gold'][table] = 0
            print(f"   ❌ {table}: Error")
    print()
    
    return results


def main():
    case_id = sys.argv[1] if len(sys.argv) > 1 else "1295022"
    
    print("=" * 80)
    print("🔧 FIXING PIPELINE ISSUES")
    print("=" * 80)
    print()
    print(f"📋 Case ID: {case_id}")
    print()
    
    # Step 1: Create case if missing
    print("STEP 1: Ensure Case Exists")
    print("-" * 80)
    case_uuid = create_case_if_missing(case_id)
    if not case_uuid:
        print("❌ Failed to create case. Cannot continue.")
        sys.exit(1)
    print()
    
    # Step 2: Verify triggers
    print("STEP 2: Verify Triggers")
    print("-" * 80)
    verify_triggers()
    print()
    
    # Step 3: Check current status
    print("STEP 3: Current Pipeline Status")
    print("-" * 80)
    initial_results = check_pipeline_status(case_id, case_uuid)
    print()
    
    # Step 4: Trigger interview ingestion
    print("STEP 4: Trigger Interview Data Ingestion")
    print("-" * 80)
    interview_triggered = trigger_interview_ingestion(case_id)
    print()
    
    if interview_triggered:
        print("⏳ Waiting 15 seconds for triggers to process...")
        time.sleep(15)
        print()
    
    # Step 5: Check final status
    print("STEP 5: Final Pipeline Status")
    print("-" * 80)
    final_results = check_pipeline_status(case_id, case_uuid)
    print()
    
    # Summary
    print("=" * 80)
    print("📊 FIX SUMMARY")
    print("=" * 80)
    print()
    
    bronze_total = sum(final_results['bronze'].values())
    silver_total = sum(final_results['silver'].values())
    gold_total = sum(final_results['gold'].values())
    
    print(f"🥉 Bronze: {bronze_total} records")
    print(f"🥈 Silver: {silver_total} records")
    print(f"🥇 Gold: {gold_total} records")
    print()
    
    # What's still missing
    print("🔍 What's Still Missing:")
    print()
    
    issues = []
    
    if final_results['bronze']['bronze_interview_raw'] == 0:
        issues.append("❌ Interview data not ingested (bronze_interview_raw is empty)")
    
    if bronze_total > 0 and silver_total == 0:
        issues.append("⚠️  Bronze → Silver triggers not working (Bronze has data, Silver is empty)")
    
    if final_results['silver']['logiqs_raw_data'] > 0 and gold_total == 0:
        issues.append("⚠️  Silver → Gold trigger not working (logiqs_raw_data exists but Gold is empty)")
    
    if not issues:
        print("   ✅ Everything looks good!")
        print()
        print("🎉 SUCCESS! Pipeline is working!")
    else:
        for issue in issues:
            print(f"   {issue}")
        print()
        print("💡 Next Steps:")
        print()
        
        if "Interview data" in str(issues):
            print("   1. Manually trigger interview ingestion:")
            print(f"      python3 trigger_case_ingestion.py {case_id}")
            print("      OR")
            print("      dagster asset materialize -m dagster_pipeline --select bronze_interview_data")
            print()
        
        if "Bronze → Silver" in str(issues):
            print("   2. Check Bronze → Silver triggers in Supabase SQL Editor:")
            print("      SELECT tgname FROM pg_trigger WHERE tgname LIKE 'trigger_bronze%';")
            print("   3. Check ensure_case function:")
            print("      SELECT proname FROM pg_proc WHERE proname = 'ensure_case';")
            print()
        
        if "Silver → Gold" in str(issues):
            print("   4. Check Silver → Gold trigger:")
            print("      SELECT tgname FROM pg_trigger WHERE tgname = 'trigger_silver_to_gold';")
            print()
    
    print()


if __name__ == "__main__":
    main()

