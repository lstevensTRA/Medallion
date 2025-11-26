#!/usr/bin/env python3
"""
Validate Bronze → Silver → Gold Layers
Checks schemas, data flow, and completeness
"""

import os
from dotenv import load_dotenv
from supabase import create_client
from datetime import datetime

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

client = create_client(SUPABASE_URL, SUPABASE_KEY)

print("=" * 80)
print("🔍 VALIDATING MEDALLION ARCHITECTURE")
print("=" * 80)
print(f"Timestamp: {datetime.now().isoformat()}")
print()

# ============================================================================
# BRONZE LAYER VALIDATION
# ============================================================================

print("=" * 80)
print("🥉 BRONZE LAYER VALIDATION")
print("=" * 80)

bronze_tables = [
    'bronze_at_raw',
    'bronze_wi_raw',
    'bronze_trt_raw',
    'bronze_interview_raw',
    'bronze_pdf_raw'
]

bronze_status = {}

for table in bronze_tables:
    try:
        # Check if table exists and get schema
        result = client.table(table).select('*', count='exact').limit(1).execute()
        
        if result.data:
            sample = result.data[0]
            columns = list(sample.keys())
        else:
            # Table exists but empty - get schema from Supabase
            columns = []
        
        bronze_status[table] = {
            'exists': True,
            'count': result.count if hasattr(result, 'count') else 0,
            'columns': columns,
            'has_data': len(result.data) > 0
        }
        
        status_icon = "✅" if bronze_status[table]['exists'] else "❌"
        data_icon = "📊" if bronze_status[table]['has_data'] else "📭"
        
        print(f"{status_icon} {table}")
        print(f"   Count: {bronze_status[table]['count']} records")
        print(f"   Has Data: {data_icon}")
        if columns:
            print(f"   Key Columns: {', '.join(columns[:5])}...")
        print()
        
    except Exception as e:
        bronze_status[table] = {
            'exists': False,
            'error': str(e)
        }
        print(f"❌ {table}: {str(e)[:100]}")
        print()

# ============================================================================
# SILVER LAYER VALIDATION
# ============================================================================

print("=" * 80)
print("🥈 SILVER LAYER VALIDATION")
print("=" * 80)

silver_tables = [
    'tax_years',
    'account_activity',
    'income_documents',
    'trt_records',
    'logiqs_raw_data'
]

silver_status = {}

for table in silver_tables:
    try:
        result = client.table(table).select('*', count='exact').limit(1).execute()
        
        if result.data:
            sample = result.data[0]
            columns = list(sample.keys())
        else:
            columns = []
        
        silver_status[table] = {
            'exists': True,
            'count': result.count if hasattr(result, 'count') else 0,
            'columns': columns,
            'has_data': len(result.data) > 0
        }
        
        status_icon = "✅" if silver_status[table]['exists'] else "❌"
        data_icon = "📊" if silver_status[table]['has_data'] else "📭"
        
        print(f"{status_icon} {table}")
        print(f"   Count: {silver_status[table]['count']} records")
        print(f"   Has Data: {data_icon}")
        if columns:
            print(f"   Key Columns: {', '.join(columns[:5])}...")
        print()
        
    except Exception as e:
        silver_status[table] = {
            'exists': False,
            'error': str(e)
        }
        print(f"❌ {table}: {str(e)[:100]}")
        print()

# ============================================================================
# GOLD LAYER VALIDATION
# ============================================================================

print("=" * 80)
print("🥇 GOLD LAYER VALIDATION")
print("=" * 80)

gold_tables = [
    'employment_information',
    'household_information',
    'financial_accounts',
    'monthly_expenses',
    'income_sources',
    'vehicles',
    'real_estate'
]

gold_status = {}

for table in gold_tables:
    try:
        result = client.table(table).select('*', count='exact').limit(1).execute()
        
        if result.data:
            sample = result.data[0]
            columns = list(sample.keys())
        else:
            columns = []
        
        gold_status[table] = {
            'exists': True,
            'count': result.count if hasattr(result, 'count') else 0,
            'columns': columns,
            'has_data': len(result.data) > 0
        }
        
        status_icon = "✅" if gold_status[table]['exists'] else "❌"
        data_icon = "📊" if gold_status[table]['has_data'] else "📭"
        
        print(f"{status_icon} {table}")
        print(f"   Count: {gold_status[table]['count']} records")
        print(f"   Has Data: {data_icon}")
        if columns:
            print(f"   Key Columns: {', '.join(columns[:5])}...")
        print()
        
    except Exception as e:
        gold_status[table] = {
            'exists': False,
            'error': str(e)
        }
        print(f"❌ {table}: {str(e)[:100]}")
        print()

# ============================================================================
# DATA FLOW VALIDATION
# ============================================================================

print("=" * 80)
print("🔄 DATA FLOW VALIDATION")
print("=" * 80)

# Check if Bronze data has corresponding Silver data
try:
    # Check AT → Silver flow
    bronze_at_count = bronze_status.get('bronze_at_raw', {}).get('count', 0)
    silver_tax_years_count = silver_status.get('tax_years', {}).get('count', 0)
    silver_activity_count = silver_status.get('account_activity', {}).get('count', 0)
    
    print(f"Bronze AT → Silver:")
    print(f"   Bronze AT records: {bronze_at_count}")
    print(f"   Silver tax_years: {silver_tax_years_count}")
    print(f"   Silver account_activity: {silver_activity_count}")
    
    if bronze_at_count > 0 and (silver_tax_years_count > 0 or silver_activity_count > 0):
        print("   ✅ Data flow working (Bronze → Silver)")
    elif bronze_at_count > 0:
        print("   ⚠️  Bronze data exists but no Silver data (triggers may not be working)")
    else:
        print("   ℹ️  No Bronze data to validate flow")
    print()
    
    # Check WI → Silver flow
    bronze_wi_count = bronze_status.get('bronze_wi_raw', {}).get('count', 0)
    silver_income_count = silver_status.get('income_documents', {}).get('count', 0)
    
    print(f"Bronze WI → Silver:")
    print(f"   Bronze WI records: {bronze_wi_count}")
    print(f"   Silver income_documents: {silver_income_count}")
    
    if bronze_wi_count > 0 and silver_income_count > 0:
        print("   ✅ Data flow working (Bronze → Silver)")
    elif bronze_wi_count > 0:
        print("   ⚠️  Bronze data exists but no Silver data (triggers may not be working)")
    else:
        print("   ℹ️  No Bronze data to validate flow")
    print()
    
except Exception as e:
    print(f"❌ Error validating data flow: {e}")
    print()

# ============================================================================
# SCHEMA VALIDATION
# ============================================================================

print("=" * 80)
print("📋 SCHEMA VALIDATION")
print("=" * 80)

# Expected Bronze columns
expected_bronze_columns = {
    'bronze_at_raw': ['bronze_id', 'case_id', 'raw_response', 'inserted_at'],
    'bronze_wi_raw': ['bronze_id', 'case_id', 'raw_response', 'inserted_at'],
    'bronze_trt_raw': ['bronze_id', 'case_id', 'raw_response', 'inserted_at'],
    'bronze_interview_raw': ['bronze_id', 'case_id', 'raw_response', 'inserted_at'],
}

# Expected Silver columns
expected_silver_columns = {
    'tax_years': ['id', 'case_id', 'tax_year', 'bronze_id'],
    'account_activity': ['id', 'case_id', 'tax_year', 'bronze_id', 'irs_transaction_code'],
    'income_documents': ['id', 'case_id', 'tax_year', 'bronze_id', 'document_type'],
}

# Expected Gold columns
expected_gold_columns = {
    'employment_information': ['id', 'case_id', 'person_type', 'employer_name'],
    'household_information': ['id', 'case_id', 'total_household_members'],
}

print("Checking critical columns...")
print()

for table, expected_cols in expected_bronze_columns.items():
    if table in bronze_status and bronze_status[table]['exists']:
        actual_cols = bronze_status[table].get('columns', [])
        missing = [col for col in expected_cols if col not in actual_cols]
        if missing:
            print(f"⚠️  {table}: Missing columns: {', '.join(missing)}")
        else:
            print(f"✅ {table}: All critical columns present")

print()

for table, expected_cols in expected_silver_columns.items():
    if table in silver_status and silver_status[table]['exists']:
        actual_cols = silver_status[table].get('columns', [])
        missing = [col for col in expected_cols if col not in actual_cols]
        if missing:
            print(f"⚠️  {table}: Missing columns: {', '.join(missing)}")
        else:
            print(f"✅ {table}: All critical columns present")

print()

for table, expected_cols in expected_gold_columns.items():
    if table in gold_status and gold_status[table]['exists']:
        actual_cols = gold_status[table].get('columns', [])
        missing = [col for col in expected_cols if col not in actual_cols]
        if missing:
            print(f"⚠️  {table}: Missing columns: {', '.join(missing)}")
        else:
            print(f"✅ {table}: All critical columns present")

print()

# ============================================================================
# SUMMARY
# ============================================================================

print("=" * 80)
print("📊 VALIDATION SUMMARY")
print("=" * 80)

bronze_existing = sum(1 for s in bronze_status.values() if s.get('exists'))
silver_existing = sum(1 for s in silver_status.values() if s.get('exists'))
gold_existing = sum(1 for s in gold_status.values() if s.get('exists'))

bronze_with_data = sum(1 for s in bronze_status.values() if s.get('has_data'))
silver_with_data = sum(1 for s in silver_status.values() if s.get('has_data'))
gold_with_data = sum(1 for s in gold_status.values() if s.get('has_data'))

print(f"Bronze Layer: {bronze_existing}/{len(bronze_tables)} tables exist, {bronze_with_data} with data")
print(f"Silver Layer: {silver_existing}/{len(silver_tables)} tables exist, {silver_with_data} with data")
print(f"Gold Layer: {gold_existing}/{len(gold_tables)} tables exist, {gold_with_data} with data")
print()

# Overall status
if bronze_existing == len(bronze_tables) and silver_existing == len(silver_tables):
    print("✅ BRONZE & SILVER LAYERS: COMPLETE")
else:
    print("⚠️  BRONZE & SILVER LAYERS: INCOMPLETE")

if gold_existing == len(gold_tables):
    print("✅ GOLD LAYER: COMPLETE")
elif gold_existing > 0:
    print("⚠️  GOLD LAYER: PARTIAL")
else:
    print("❌ GOLD LAYER: NOT CREATED")

print()
print("=" * 80)


