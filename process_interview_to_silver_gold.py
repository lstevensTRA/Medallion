#!/usr/bin/env python3
"""
Process Interview Data from Bronze → Silver → Gold
"""

import os
import sys
from pathlib import Path
from dotenv import load_dotenv
from supabase import create_client, Client
import json

# Load environment variables
env_path = Path(__file__).parent / ".env"
load_dotenv(env_path)

SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_KEY')

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ Missing SUPABASE_URL or SUPABASE_KEY in .env")
    sys.exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

def safe_get(data, *keys, default=None):
    """Safely get nested value from dict"""
    current = data
    for key in keys:
        if isinstance(current, dict):
            current = current.get(key)
        else:
            return default
        if current is None:
            return default
    return current if current is not None else default

def parse_decimal(value):
    """Parse decimal from various formats"""
    if value is None:
        return 0
    if isinstance(value, (int, float)):
        return float(value)
    try:
        cleaned = str(value).replace('$', '').replace(',', '').strip()
        return float(cleaned)
    except:
        return 0

def process_interview(case_id: str):
    """Process interview data from Bronze → Silver → Gold"""
    print("=" * 80)
    print("🔄 PROCESSING INTERVIEW DATA: Bronze → Silver → Gold")
    print("=" * 80)
    print()
    
    # Get case UUID
    case_response = supabase.table('cases').select('id').eq('case_number', case_id).limit(1).execute()
    if not case_response.data:
        print(f"❌ Case {case_id} not found")
        return
    case_uuid = case_response.data[0]['id']
    print(f"✅ Case UUID: {case_uuid}")
    print()
    
    # Get Bronze interview record
    print("STEP 1: Get Bronze Interview Data")
    print("-" * 80)
    bronze_interview = supabase.table('bronze_interview_raw').select('bronze_id, raw_response').eq('case_id', case_id).limit(1).execute()
    
    if not bronze_interview.data:
        print("❌ No Bronze interview data found")
        return
    
    bronze_id = bronze_interview.data[0]['bronze_id']
    raw_response = bronze_interview.data[0]['raw_response']
    print(f"✅ Found Bronze interview: {bronze_id}")
    print()
    
    # Extract sections
    employment = raw_response.get('employment', {})
    household = raw_response.get('household', {})
    assets = raw_response.get('assets', {})
    income = raw_response.get('income', {})
    expenses = raw_response.get('expenses', {})
    irs_standards = raw_response.get('irs_standards', {})
    
    print("STEP 2: Populate Silver (logiqs_raw_data)")
    print("-" * 80)
    
    # Map to logiqs_raw_data columns (Excel cell references)
    logiqs_data = {
        'case_id': case_uuid,
        'employment': employment,
        'household': household,
        'assets': assets,
        'income': income,
        'expenses': expenses,
        'irs_standards': irs_standards,
        'raw_response': raw_response,
        # Employment fields (b3-b7, c3-c7, al7, al8)
        'b3': safe_get(employment, 'clientEmployer', default=''),
        'b4': safe_get(employment, 'clientStartWorkingDate') or None,  # DATE field - use None not ''
        'b5': parse_decimal(safe_get(employment, 'clientGrossIncome')),
        'b6': parse_decimal(safe_get(employment, 'clientNetIncome')),
        'b7': safe_get(employment, 'clientFrequentlyPaid', default=''),
        'c3': safe_get(employment, 'spouseEmployer', default=''),
        'c4': safe_get(employment, 'spouseStartWorkingDate') or None,  # DATE field - use None not ''
        'c5': parse_decimal(safe_get(employment, 'spouseGrossIncome')),
        'c6': parse_decimal(safe_get(employment, 'spouseNetIncome')),
        'c7': safe_get(employment, 'spouseFrequentlyPaid', default=''),
        'al7': parse_decimal(safe_get(employment, 'clientMonthlyIncome')),
        'al8': parse_decimal(safe_get(employment, 'spouseMonthlyIncome')),
        # Household fields (b10-b14, c10-c14, b50-b53)
        'b10': safe_get(household, 'clientHouseMembers', default='1'),
        'b11': safe_get(household, 'clientNextTaxReturn', default=''),
        'b12': safe_get(household, 'clientSpouseClaim', default=''),
        'b13': safe_get(household, 'clientLengthofresidency', default=''),
        'b14': safe_get(household, 'clientOccupancyStatus', default=''),
        'c10': safe_get(household, 'spouseHouseMembers', default=''),
        'c11': safe_get(household, 'spouseNextTaxReturn', default=''),
        'c12': safe_get(household, 'spouseSpouseClaim', default=''),
        'c13': safe_get(household, 'spouseLengthofresidency', default=''),
        'c14': safe_get(household, 'spouseOccupancyStatus', default=''),
        'b50': safe_get(household, 'under65', default='0'),
        'b51': safe_get(household, 'over65', default='0'),
        'b52': safe_get(household, 'state', default=''),
        'b53': safe_get(household, 'county', default=''),
        # Assets (b18-b29, d20-d29)
        'b18': parse_decimal(safe_get(assets, 'checkingAccounts', default=0)),
        'b19': parse_decimal(safe_get(assets, 'cashOnHand', default=0)),
        'b20': parse_decimal(safe_get(assets, 'investments', default=0)),
        'b21': parse_decimal(safe_get(assets, 'lifeInsurance', default=0)),
        'b22': parse_decimal(safe_get(assets, 'retirement', default=0)),
        'b23': parse_decimal(safe_get(assets, 'realEstateValue', default=0)),
        'b24': parse_decimal(safe_get(assets, 'vehicle1Value', default=0)),
        'b25': parse_decimal(safe_get(assets, 'vehicle2Value', default=0)),
        'b26': parse_decimal(safe_get(assets, 'vehicle3Value', default=0)),
        'b27': parse_decimal(safe_get(assets, 'vehicle4Value', default=0)),
        'd20': parse_decimal(safe_get(assets, 'checkingLoans', default=0)),
        'd21': parse_decimal(safe_get(assets, 'cashLoans', default=0)),
        'd23': parse_decimal(safe_get(assets, 'realEstateLoan', default=0)),
        'd24': parse_decimal(safe_get(assets, 'vehicle1Loan', default=0)),
        'd25': parse_decimal(safe_get(assets, 'vehicle2Loan', default=0)),
        'd26': parse_decimal(safe_get(assets, 'vehicle3Loan', default=0)),
        'd27': parse_decimal(safe_get(assets, 'vehicle4Loan', default=0)),
        # Income (b33-b47)
        'b33': parse_decimal(safe_get(income, 'clientWages', default=0)),
        'b34': parse_decimal(safe_get(income, 'clientSocialSecurity', default=0)),
        'b35': parse_decimal(safe_get(income, 'clientPension', default=0)),
        'b36': parse_decimal(safe_get(income, 'spouseWages', default=0)),
        'b37': parse_decimal(safe_get(income, 'spouseSocialSecurity', default=0)),
        'b38': parse_decimal(safe_get(income, 'spousePension', default=0)),
        'b39': parse_decimal(safe_get(income, 'dividendsInterest', default=0)),
        'b40': parse_decimal(safe_get(income, 'rentalGross', default=0)),
        'b41': parse_decimal(safe_get(income, 'rentalExpenses', default=0)),
        'b42': parse_decimal(safe_get(income, 'distributions', default=0)),
        'b43': parse_decimal(safe_get(income, 'alimony', default=0)),
        'b44': parse_decimal(safe_get(income, 'childSupport', default=0)),
        'b45': parse_decimal(safe_get(income, 'otherIncome', default=0)),
        'b46': parse_decimal(safe_get(income, 'additional1', default=0)),
        'b47': parse_decimal(safe_get(income, 'additional2', default=0)),
        # Expenses (b56-b90, ak2-ak8)
        'b56': parse_decimal(safe_get(expenses, 'food', default=0)),
        'b57': parse_decimal(safe_get(expenses, 'housekeeping', default=0)),
        'b58': parse_decimal(safe_get(expenses, 'apparel', default=0)),
        'b59': parse_decimal(safe_get(expenses, 'personalCare', default=0)),
        'b60': parse_decimal(safe_get(expenses, 'misc', default=0)),
        'b64': parse_decimal(safe_get(expenses, 'mortgageLien1', default=0)),
        'b65': parse_decimal(safe_get(expenses, 'mortgageLien2', default=0)),
        'b66': parse_decimal(safe_get(expenses, 'rent', default=0)),
        'b67': parse_decimal(safe_get(expenses, 'insurance', default=0)),
        'b68': parse_decimal(safe_get(expenses, 'propertyTax', default=0)),
        'b69': parse_decimal(safe_get(expenses, 'gas', default=0)),
        'b70': parse_decimal(safe_get(expenses, 'electricity', default=0)),
        'b71': parse_decimal(safe_get(expenses, 'water', default=0)),
        'b72': parse_decimal(safe_get(expenses, 'sewer', default=0)),
        'b73': parse_decimal(safe_get(expenses, 'cable', default=0)),
        'b74': parse_decimal(safe_get(expenses, 'trash', default=0)),
        'b75': parse_decimal(safe_get(expenses, 'phone', default=0)),
        'b79': parse_decimal(safe_get(expenses, 'healthInsurance', default=0)),
        'b80': parse_decimal(safe_get(expenses, 'prescriptions', default=0)),
        'b81': parse_decimal(safe_get(expenses, 'copays', default=0)),
        'b84': parse_decimal(safe_get(expenses, 'taxes', default=0)),
        'b87': parse_decimal(safe_get(expenses, 'courtPayments', default=0)),
        'b88': parse_decimal(safe_get(expenses, 'childCare', default=0)),
        'b89': parse_decimal(safe_get(expenses, 'wholeLifeInsurance', default=0)),
        'b90': parse_decimal(safe_get(expenses, 'termLifeInsurance', default=0)),
        'ak2': parse_decimal(safe_get(expenses, 'transportation', default=0)),
        'ak4': parse_decimal(safe_get(expenses, 'publicTransportation', default=0)),
        'ak6': parse_decimal(safe_get(expenses, 'autoInsurance', default=0)),
        'ak7': parse_decimal(safe_get(expenses, 'autoPayment1', default=0)),
        'ak8': parse_decimal(safe_get(expenses, 'autoPayment2', default=0)),
        # IRS Standards (c56-c61, al4-al8, c76, c80)
        'c56': parse_decimal(safe_get(irs_standards, 'food', default=0)),
        'c57': parse_decimal(safe_get(irs_standards, 'housekeeping', default=0)),
        'c58': parse_decimal(safe_get(irs_standards, 'apparel', default=0)),
        'c59': parse_decimal(safe_get(irs_standards, 'personalCare', default=0)),
        'c60': parse_decimal(safe_get(irs_standards, 'misc', default=0)),
        'c61': safe_get(irs_standards, 'total', default=''),
        'c76': safe_get(irs_standards, 'housing', default=''),
        'c80': safe_get(irs_standards, 'transportation', default=''),
        'al4': parse_decimal(safe_get(irs_standards, 'totalMonthly', default=0)),
        'al5': parse_decimal(safe_get(irs_standards, 'totalAnnual', default=0)),
    }
    
    # Insert/update logiqs_raw_data
    try:
        result = supabase.table('logiqs_raw_data').upsert(logiqs_data, on_conflict='case_id').execute()
        print("✅ Silver logiqs_raw_data populated!")
        print()
    except Exception as e:
        print(f"❌ Error populating Silver: {e}")
        return
    
    print("STEP 3: Check Gold Layer (should auto-populate via trigger)")
    print("-" * 80)
    
    # Wait a moment for trigger
    import time
    time.sleep(2)
    
    # Check Gold
    employment_gold = supabase.table('employment_information').select('*', count='exact').eq('case_id', case_uuid).execute()
    expenses_gold = supabase.table('monthly_expenses').select('*', count='exact').eq('case_id', case_uuid).execute()
    household_gold = supabase.table('household_information').select('*', count='exact').eq('case_id', case_uuid).execute()
    income_gold = supabase.table('income_sources').select('*', count='exact').eq('case_id', case_uuid).execute()
    
    print("🥇 Gold Layer:")
    print(f"   employment_information: {employment_gold.count if hasattr(employment_gold, 'count') else len(employment_gold.data)} records")
    print(f"   monthly_expenses: {expenses_gold.count if hasattr(expenses_gold, 'count') else len(expenses_gold.data)} records")
    print(f"   household_information: {household_gold.count if hasattr(household_gold, 'count') else len(household_gold.data)} records")
    print(f"   income_sources: {income_gold.count if hasattr(income_gold, 'count') else len(income_gold.data)} records")
    print()
    
    total_gold = (employment_gold.count if hasattr(employment_gold, 'count') else len(employment_gold.data)) + \
                 (expenses_gold.count if hasattr(expenses_gold, 'count') else len(expenses_gold.data)) + \
                 (household_gold.count if hasattr(household_gold, 'count') else len(household_gold.data)) + \
                 (income_gold.count if hasattr(income_gold, 'count') else len(income_gold.data))
    
    if total_gold > 0:
        print("🎉 SUCCESS! Gold layer populated!")
    else:
        print("⚠️  Gold layer still empty - trigger may need manual fix")
    
    print()

if __name__ == "__main__":
    case_id = sys.argv[1] if len(sys.argv) > 1 else "1295022"
    process_interview(case_id)

