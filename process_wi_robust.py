#!/usr/bin/env python3
"""
Robust WI Processing - Process ALL forms, extract what we can
"""
import os
import sys
from pathlib import Path
from dotenv import load_dotenv
from supabase import create_client
import json

load_dotenv()

SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_KEY')

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

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
    try:
        response = supabase.table('wi_type_rules').select('*').eq('form_code', form_type_upper).limit(1).execute()
        return response.data[0] if response.data else None
    except:
        return None

def extract_all_fields(form: dict):
    """Extract all possible fields from form"""
    result = {
        'form_type': None,
        'income': 0,
        'withholding': 0,
        'issuer_name': None,
        'issuer_ein': None,
        'recipient_name': None,
        'recipient_ssn': None
    }
    
    # Form type - check 'Form' key first (TiParser structure)
    if 'Form' in form:
        form_val = form['Form']
        if isinstance(form_val, str):
            result['form_type'] = form_val.upper().strip()
        elif isinstance(form_val, dict):
            # Form is a nested object
            result['form_type'] = form_val.get('Type') or form_val.get('Code') or form_val.get('type') or form_val.get('code')
            if result['form_type']:
                result['form_type'] = str(result['form_type']).upper().strip()
    
    # Try EVERY possible key combination
    for key, value in form.items():
        key_lower = key.lower()
        
        # Form type (if not already found)
        if result['form_type'] is None:
            if any(term in key_lower for term in ['form', 'type', 'document', 'code']):
                if value and isinstance(value, str):
                    val_upper = value.upper()
                    if any(term in val_upper for term in ['W-2', '1099', 'W2', 'WAGE']):
                        result['form_type'] = val_upper.strip()
            elif isinstance(value, str) and any(term in value.upper() for term in ['W-2', '1099', 'W2']):
                result['form_type'] = value.upper().strip()
        
        # Income - check 'Income' key directly
        if 'Income' in form:
            result['income'] = parse_decimal(form['Income'])
        elif result['income'] == 0:
        
            if any(term in key_lower for term in ['income', 'wage', 'gross', 'amount', 'total', 'wages']):
                if value is not None:
                    result['income'] = parse_decimal(value)
        
        # Withholding - check 'Withholding' key directly
        if 'Withholding' in form:
            result['withholding'] = parse_decimal(form['Withholding'])
        elif result['withholding'] == 0:
            if any(term in key_lower for term in ['withhold', 'federal', 'tax']):
                if value is not None:
                    result['withholding'] = parse_decimal(value)
        
        # Issuer
        if result['issuer_name'] is None:
            if any(term in key_lower for term in ['employer', 'issuer', 'payer', 'company']):
                if 'name' in key_lower and value:
                    result['issuer_name'] = str(value)
        
        if result['issuer_ein'] is None:
            if 'ein' in key_lower and value:
                result['issuer_ein'] = str(value)
        
        # Recipient
        if result['recipient_name'] is None:
            if any(term in key_lower for term in ['employee', 'recipient', 'worker']):
                if 'name' in key_lower and value:
                    result['recipient_name'] = str(value)
        
        if result['recipient_ssn'] is None:
            if 'ssn' in key_lower and value:
                result['recipient_ssn'] = str(value)
    
    # Check nested structures
    for key in ['Issuer', 'issuer', 'Employer', 'employer']:
        if key in form and isinstance(form[key], dict):
            issuer = form[key]
            if result['issuer_name'] is None and 'Name' in issuer:
                result['issuer_name'] = str(issuer['Name'])
            if result['issuer_ein'] is None and 'EIN' in issuer:
                result['issuer_ein'] = str(issuer['EIN'])
    
    for key in ['Recipient', 'recipient', 'Employee', 'employee']:
        if key in form and isinstance(form[key], dict):
            recipient = form[key]
            if result['recipient_name'] is None and 'Name' in recipient:
                result['recipient_name'] = str(recipient['Name'])
            if result['recipient_ssn'] is None and 'SSN' in recipient:
                result['recipient_ssn'] = str(recipient['SSN'])
    
    # Extract from Fields if present (TiParser structure)
    if 'Fields' in form and isinstance(form['Fields'], dict):
        fields = form['Fields']
        
        # Check Fields for issuer/recipient info
        if result['issuer_name'] is None:
            result['issuer_name'] = fields.get('PayerName') or fields.get('EmployerName') or fields.get('payer_name')
        if result['issuer_ein'] is None:
            result['issuer_ein'] = fields.get('PayerEIN') or fields.get('EmployerEIN') or fields.get('ein')
        if result['recipient_name'] is None:
            result['recipient_name'] = fields.get('RecipientName') or fields.get('EmployeeName') or fields.get('recipient_name')
        if result['recipient_ssn'] is None:
            result['recipient_ssn'] = fields.get('RecipientSSN') or fields.get('EmployeeSSN') or fields.get('ssn')
    
    # Default form type if still None
    if result['form_type'] is None:
        result['form_type'] = 'UNKNOWN'
    
    return result

def process_wi_robust(case_id: str):
    print("=" * 80)
    print("🔄 ROBUST WI PROCESSING")
    print("=" * 80)
    print()
    
    case_uuid = get_or_create_case(case_id)
    
    bronze_wi = supabase.table('bronze_wi_raw').select('bronze_id, raw_response').eq('case_id', case_id).execute()
    
    if not bronze_wi.data:
        print("❌ No Bronze WI records")
        return
    
    print(f"📋 Processing {len(bronze_wi.data)} Bronze WI records")
    print()
    
    total_processed = 0
    sample_printed = False
    
    for bronze_record in bronze_wi.data:
        raw_response = bronze_record['raw_response']
        
        if 'years_data' in raw_response and isinstance(raw_response['years_data'], dict):
            years_data = raw_response['years_data']
            
            for year_key, year_data in years_data.items():
                try:
                    year = int(year_key)
                except:
                    continue
                
                tax_year_id = ensure_tax_year(case_uuid, year)
                
                forms = []
                if isinstance(year_data, dict):
                    forms = year_data.get('forms', [])
                elif isinstance(year_data, list):
                    forms = year_data
                
                if not isinstance(forms, list):
                    continue
                
                for form in forms:
                    if not isinstance(form, dict):
                        continue
                    
                    # Print sample form structure
                    if not sample_printed:
                        print(f"📋 Sample form structure (Year {year}):")
                        print(f"   Keys: {list(form.keys())[:20]}")
                        sample_printed = True
                    
                    # Extract all fields
                    fields = extract_all_fields(form)
                    
                    # Get WI rule
                    wi_rule = get_wi_rule(fields['form_type'])
                    
                    # Insert (even if form_type is UNKNOWN)
                    try:
                        insert_data = {
                            'tax_year_id': tax_year_id,
                            'document_type': fields['form_type'],
                            'gross_amount': fields['income'],
                            'federal_withholding': fields['withholding'],
                            'issuer_name': fields['issuer_name'],
                            'issuer_id': fields['issuer_ein'],  # EIN stored in issuer_id column
                            'recipient_name': fields['recipient_name'],
                            'recipient_id': fields['recipient_ssn'],  # SSN stored in recipient_id column
                            'calculated_category': wi_rule.get('category') if wi_rule else 'Unknown',
                            'is_self_employment': wi_rule.get('is_self_employment') if wi_rule else False
                        }
                        supabase.table('income_documents').insert(insert_data).execute()
                        total_processed += 1
                        if total_processed == 1:
                            print(f"   ✅ First insert successful: {fields['form_type']} - Income: ${fields['income']}")
                    except Exception as e:
                        # Print first error
                        if total_processed == 0:
                            print(f"   ⚠️  Insert error: {str(e)[:200]}")
                            print(f"      Form type: {fields['form_type']}, Income: {fields['income']}, Tax Year ID: {tax_year_id}")
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
        print(f"📊 Total income_documents: {count} records")
        
        if count > 0:
            print()
            print("🎉 SUCCESS! Income documents populated!")
        else:
            print()
            print("⚠️  Still 0 records - checking why...")

if __name__ == "__main__":
    case_id = sys.argv[1] if len(sys.argv) > 1 else "1295022"
    process_wi_robust(case_id)

