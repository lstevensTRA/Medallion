#!/usr/bin/env python3
"""
Final WI Processing Script - Comprehensive form extraction
Handles ANY form structure and extracts to income_documents
"""
import os
import sys
from pathlib import Path
from dotenv import load_dotenv
from supabase import create_client, Client
import json

load_dotenv()

SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_KEY')

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

def get_or_create_case(case_number: str):
    response = supabase.table('cases').select('id').eq('case_number', case_number).limit(1).execute()
    if response.data:
        return response.data[0]['id']
    else:
        insert_response = supabase.table('cases').insert({'case_number': case_number, 'status_code': 'NEW'}).execute()
        return insert_response.data[0]['id']

def ensure_tax_year(case_uuid: str, year: int):
    response = supabase.table('tax_years').select('id').eq('case_id', case_uuid).eq('year', year).limit(1).execute()
    if response.data:
        return response.data[0]['id']
    else:
        insert_response = supabase.table('tax_years').insert({'case_id': case_uuid, 'year': year}).execute()
        return insert_response.data[0]['id']

def parse_decimal(value):
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
    if not form_type:
        return None
    form_type_upper = form_type.upper().strip()
    response = supabase.table('wi_type_rules').select('*').eq('form_code', form_type_upper).limit(1).execute()
    return response.data[0] if response.data else None

def extract_form_type(form: dict):
    """Extract form type from ANY possible structure"""
    # Method 1: Direct keys
    for key in ['Form', 'form', 'form_type', 'document_type', 'type', 'FormType', 'formCode', 'FormCode', 'Code', 'code']:
        if key in form and form[key]:
            val = str(form[key]).upper().strip()
            if val and val != 'NULL':
                return val
    
    # Method 2: Nested Form object
    if 'Form' in form and isinstance(form['Form'], dict):
        for key in ['Type', 'type', 'Code', 'code']:
            if key in form['Form'] and form['Form'][key]:
                val = str(form['Form'][key]).upper().strip()
                if val and val != 'NULL':
                    return val
    
    # Method 3: Scan all values for form patterns
    for key, value in form.items():
        if isinstance(value, str):
            value_upper = value.upper().strip()
            if any(term in value_upper for term in ['W-2', '1099', 'W2', '1099-NEC', '1099-MISC']):
                return value_upper
    
    return None

def extract_value(form: dict, keys: list):
    """Extract value trying multiple keys"""
    for key in keys:
        if key in form:
            val = form[key]
            if val is not None and val != '':
                return val
        # Try nested
        if '.' in key:
            parts = key.split('.')
            current = form
            try:
                for part in parts:
                    if isinstance(current, dict) and part in current:
                        current = current[part]
                    else:
                        current = None
                        break
                if current is not None and current != '':
                    return current
            except:
                pass
    return None

def process_wi_complete(case_id: str):
    print("=" * 80)
    print("🔄 PROCESSING WI DATA (COMPREHENSIVE)")
    print("=" * 80)
    print()
    
    case_uuid = get_or_create_case(case_id)
    print(f"✅ Case UUID: {case_uuid}")
    print()
    
    bronze_wi = supabase.table('bronze_wi_raw').select('bronze_id, raw_response').eq('case_id', case_id).execute()
    
    if not bronze_wi.data:
        print("❌ No Bronze WI records found")
        return
    
    print(f"📋 Processing {len(bronze_wi.data)} Bronze WI records")
    print()
    
    total_processed = 0
    total_forms_found = 0
    total_forms_skipped = 0
    
    for bronze_record in bronze_wi.data:
        raw_response = bronze_record['raw_response']
        
        # Handle years_data structure
        if 'years_data' in raw_response and isinstance(raw_response['years_data'], dict):
            years_data = raw_response['years_data']
            
            for year_key, year_data in years_data.items():
                try:
                    year = int(year_key)
                except:
                    continue
                
                tax_year_id = ensure_tax_year(case_uuid, year)
                
                # Handle year_data as dict with 'forms' key, or as list directly
                forms = []
                if isinstance(year_data, dict):
                    forms = year_data.get('forms', [])
                    if not isinstance(forms, list):
                        forms = []
                elif isinstance(year_data, list):
                    forms = year_data
                
                if not isinstance(forms, list):
                    continue
                
                total_forms_found += len(forms)
                print(f"   Year {year}: {len(forms)} forms")
                
                for form in forms:
                    if not isinstance(form, dict):
                        total_forms_skipped += 1
                        continue
                    
                    # Extract form type
                    form_type = extract_form_type(form)
                    
                    if not form_type:
                        # Debug: print first form that fails
                        if total_forms_skipped == 0:
                            print(f'      ⚠️  First form has no form_type')
                            print(f'      Form keys: {list(form.keys())[:15]}')
                            print(f'      Sample values:')
                            for key, val in list(form.items())[:5]:
                                print(f'        {key}: {val}')
                        total_forms_skipped += 1
                        continue
                    
                    # Get WI rule
                    wi_rule = get_wi_rule(form_type)
                    
                    # Extract all fields
                    income = parse_decimal(extract_value(form, [
                        'Income', 'income', 'gross_amount', 'amount', 'Gross', 'Wages', 'wages', 'Total', 'total'
                    ]))
                    
                    withholding = parse_decimal(extract_value(form, [
                        'Withholding', 'withholding', 'federal_withholding', 'Federal', 'FederalTaxWithheld'
                    ]))
                    
                    issuer_name = extract_value(form, [
                        'Issuer.Name', 'Issuer.name', 'issuer_name', 'Employer', 'employer_name', 'EmployerName'
                    ])
                    
                    issuer_ein = extract_value(form, [
                        'Issuer.EIN', 'Issuer.ein', 'issuer_ein', 'EIN', 'ein', 'EmployerEIN'
                    ])
                    
                    recipient_name = extract_value(form, [
                        'Recipient.Name', 'Recipient.name', 'recipient_name', 'Employee', 'employee_name', 'EmployeeName'
                    ])
                    
                    recipient_ssn = extract_value(form, [
                        'Recipient.SSN', 'Recipient.ssn', 'recipient_ssn', 'SSN', 'ssn', 'EmployeeSSN'
                    ])
                    
                    # Insert income_document
                    try:
                        supabase.table('income_documents').insert({
                            'tax_year_id': tax_year_id,
                            'document_type': form_type,
                            'gross_amount': income,
                            'federal_withholding': withholding,
                            'issuer_name': str(issuer_name) if issuer_name else None,
                            'issuer_ein': str(issuer_ein) if issuer_ein else None,
                            'recipient_name': str(recipient_name) if recipient_name else None,
                            'recipient_ssn': str(recipient_ssn) if recipient_ssn else None,
                            'calculated_category': wi_rule.get('category') if wi_rule else 'Unknown',
                            'is_self_employment': wi_rule.get('is_self_employment') if wi_rule else False
                        }).execute()
                        total_processed += 1
                    except Exception as e:
                        # Skip duplicates or errors
                        total_forms_skipped += 1
                        pass
    
    print()
    print("=" * 80)
    print(f"✅ Processed {total_processed} income documents")
    print(f"   Forms found: {total_forms_found}")
    print(f"   Forms skipped: {total_forms_skipped} (duplicates/no form type)")
    print("=" * 80)
    print()
    
    # Verify results
    tax_year_ids = supabase.table('tax_years').select('id').eq('case_id', case_uuid).execute()
    tax_year_id_list = [t['id'] for t in tax_year_ids.data] if tax_year_ids.data else []
    
    if tax_year_id_list:
        income_documents = supabase.table('income_documents').select('*', count='exact').in_('tax_year_id', tax_year_id_list).execute()
        count = income_documents.count if hasattr(income_documents, 'count') else len(income_documents.data)
        print(f"📊 Total income_documents in Silver: {count} records")
        if count > 0:
            print("🎉 SUCCESS! Income documents populated!")
    
    print()

if __name__ == "__main__":
    case_id = sys.argv[1] if len(sys.argv) > 1 else "1295022"
    process_wi_complete(case_id)

