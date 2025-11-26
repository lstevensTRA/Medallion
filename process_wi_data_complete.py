#!/usr/bin/env python3
"""
Process WI Data to Populate income_documents
Handles the actual TiParser WI data structure
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

def get_or_create_case(case_number: str):
    """Get or create case UUID"""
    response = supabase.table('cases').select('id').eq('case_number', case_number).limit(1).execute()
    
    if response.data:
        return response.data[0]['id']
    else:
        insert_response = supabase.table('cases').insert({
            'case_number': case_number,
            'status_code': 'NEW'
        }).execute()
        return insert_response.data[0]['id']

def ensure_tax_year(case_uuid: str, year: int):
    """Get or create tax_year UUID"""
    response = supabase.table('tax_years').select('id').eq('case_id', case_uuid).eq('year', year).limit(1).execute()
    
    if response.data:
        return response.data[0]['id']
    else:
        insert_response = supabase.table('tax_years').insert({
            'case_id': case_uuid,
            'year': year
        }).execute()
        return insert_response.data[0]['id']

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

def get_wi_rule(form_type: str):
    """Get WI type rule"""
    if not form_type:
        return None
    
    form_type_upper = form_type.upper().strip()
    response = supabase.table('wi_type_rules').select('*').eq('form_code', form_type_upper).limit(1).execute()
    
    if response.data:
        return response.data[0]
    return None

def process_wi_data(case_id: str):
    """Process WI data from Bronze to Silver"""
    print("=" * 80)
    print("🔄 PROCESSING WI DATA: Bronze → Silver")
    print("=" * 80)
    print()
    
    # Get case UUID
    case_uuid = get_or_create_case(case_id)
    print(f"✅ Case UUID: {case_uuid}")
    print()
    
    # Get Bronze WI records
    bronze_wi = supabase.table('bronze_wi_raw').select('bronze_id, raw_response').eq('case_id', case_id).execute()
    
    if not bronze_wi.data:
        print("❌ No Bronze WI records found")
        return
    
    print(f"📋 Found {len(bronze_wi.data)} Bronze WI records")
    print()
    
    total_processed = 0
    
    for bronze_record in bronze_wi.data:
        bronze_id = bronze_record['bronze_id']
        raw_response = bronze_record['raw_response']
        
        print(f"🔄 Processing Bronze WI: {bronze_id}")
        
        # Handle years_data structure
        if 'years_data' in raw_response and isinstance(raw_response['years_data'], dict):
            years_data = raw_response['years_data']
            
            for year_key, year_data in years_data.items():
                year = int(year_key) if year_key.isdigit() else None
                
                if year:
                    tax_year_id = ensure_tax_year(case_uuid, year)
                    
                    # Get forms from this year
                    forms = []
                    if 'forms' in year_data and isinstance(year_data['forms'], list):
                        forms = year_data['forms']
                    elif isinstance(year_data, list):
                        forms = year_data
                    
                    print(f"   Year {year}: {len(forms)} forms")
                    
                    for form_idx, form in enumerate(forms):
                        if not isinstance(form, dict):
                            if form_idx == 0:
                                print(f'      ⚠️  Form {form_idx} is not a dict: {type(form)}')
                            continue
                        
                        # Extract form type - check all possible keys
                        form_type = None
                        for key in form.keys():
                            if any(term in key.lower() for term in ['form', 'type', 'document', 'code']):
                                if form[key]:
                                    form_type = str(form[key]).upper().strip()
                                    break
                        
                        # If still no form type, try direct values
                        if not form_type:
                            # Check if form itself has a type indicator
                            for key, value in form.items():
                                if isinstance(value, str) and any(term in value.upper() for term in ['W-2', '1099', 'W2', '1099-NEC', '1099-MISC']):
                                    form_type = value.upper().strip()
                                    break
                        
                        if not form_type:
                            # Debug: print first form that fails
                            if form_idx == 0:
                                print(f'      ⚠️  Form {form_idx} has no form_type')
                                print(f'      Keys: {list(form.keys())[:10]}')
                            continue
                        
                        # Get WI rule
                        wi_rule = get_wi_rule(form_type)
                        
                        # Extract income
                        income = 0
                        for key in ['Income', 'income', 'gross_amount', 'amount', 'Gross', 'Wages']:
                            if key in form:
                                income = parse_decimal(form[key])
                                break
                        
                        # Extract withholding
                        withholding = 0
                        for key in ['Withholding', 'withholding', 'federal_withholding', 'Federal', 'FederalTaxWithheld']:
                            if key in form:
                                withholding = parse_decimal(form[key])
                                break
                        
                        # Extract issuer info
                        issuer_name = None
                        issuer_ein = None
                        if 'Issuer' in form and isinstance(form['Issuer'], dict):
                            issuer_name = form['Issuer'].get('Name') or form['Issuer'].get('name')
                            issuer_ein = form['Issuer'].get('EIN') or form['Issuer'].get('ein')
                        else:
                            issuer_name = form.get('issuer_name') or form.get('Employer') or form.get('employer_name')
                            issuer_ein = form.get('issuer_ein') or form.get('EIN') or form.get('ein')
                        
                        # Extract recipient info
                        recipient_name = None
                        recipient_ssn = None
                        if 'Recipient' in form and isinstance(form['Recipient'], dict):
                            recipient_name = form['Recipient'].get('Name') or form['Recipient'].get('name')
                            recipient_ssn = form['Recipient'].get('SSN') or form['Recipient'].get('ssn')
                        else:
                            recipient_name = form.get('recipient_name') or form.get('Employee') or form.get('employee_name')
                            recipient_ssn = form.get('recipient_ssn') or form.get('SSN') or form.get('ssn')
                        
                        # Insert income_document
                        try:
                            supabase.table('income_documents').insert({
                                'tax_year_id': tax_year_id,
                                'document_type': form_type,
                                'gross_amount': income,
                                'federal_withholding': withholding,
                                'issuer_name': issuer_name,
                                'issuer_ein': issuer_ein,
                                'recipient_name': recipient_name,
                                'recipient_ssn': recipient_ssn,
                                'calculated_category': wi_rule.get('category') if wi_rule else 'Unknown',
                                'is_self_employment': wi_rule.get('is_self_employment') if wi_rule else False
                            }).execute()
                            total_processed += 1
                        except Exception as e:
                            # Skip duplicates
                            pass
        
        # Handle old structure (direct forms array)
        elif 'forms' in raw_response and isinstance(raw_response['forms'], list):
            forms = raw_response['forms']
            print(f"   Found {len(forms)} forms (old structure)")
            
            for form in forms:
                if not isinstance(form, dict):
                    continue
                
                # Extract year
                year = None
                for key in ['Year', 'year', 'tax_year', 'TaxYear']:
                    if key in form:
                        try:
                            year = int(str(form[key]))
                            break
                        except:
                            pass
                
                if not year:
                    continue
                
                tax_year_id = ensure_tax_year(case_uuid, year)
                
                # Extract form type
                form_type = None
                for key in ['Form', 'form', 'form_type', 'document_type', 'type']:
                    if key in form and form[key]:
                        form_type = str(form[key]).upper().strip()
                        break
                
                if not form_type:
                    continue
                
                # Get WI rule
                wi_rule = get_wi_rule(form_type)
                
                # Extract income
                income = 0
                for key in ['Income', 'income', 'gross_amount', 'amount']:
                    if key in form:
                        income = parse_decimal(form[key])
                        break
                
                # Extract withholding
                withholding = 0
                for key in ['Withholding', 'withholding', 'federal_withholding']:
                    if key in form:
                        withholding = parse_decimal(form[key])
                        break
                
                # Insert income_document
                try:
                    supabase.table('income_documents').insert({
                        'tax_year_id': tax_year_id,
                        'document_type': form_type,
                        'gross_amount': income,
                        'federal_withholding': withholding,
                        'calculated_category': wi_rule.get('category') if wi_rule else 'Unknown',
                        'is_self_employment': wi_rule.get('is_self_employment') if wi_rule else False
                    }).execute()
                    total_processed += 1
                except Exception as e:
                    # Skip duplicates
                    pass
    
    print()
    print("=" * 80)
    print(f"✅ Processed {total_processed} income documents")
    print("=" * 80)
    print()
    
    # Check results
    tax_year_ids = supabase.table('tax_years').select('id').eq('case_id', case_uuid).execute()
    tax_year_id_list = [t['id'] for t in tax_year_ids.data] if tax_year_ids.data else []
    
    if tax_year_id_list:
        income_documents = supabase.table('income_documents').select('*', count='exact').in_('tax_year_id', tax_year_id_list).execute()
        count = income_documents.count if hasattr(income_documents, 'count') else len(income_documents.data)
        print(f"📊 Total income_documents in Silver: {count} records")
    
    print()

if __name__ == "__main__":
    case_id = sys.argv[1] if len(sys.argv) > 1 else "1295022"
    process_wi_data(case_id)

