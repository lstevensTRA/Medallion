#!/usr/bin/env python3
"""
Direct SQL insert for WI data - bypasses all triggers
"""
import os
import sys
from pathlib import Path
from dotenv import load_dotenv
from supabase import create_client
import json
import requests

load_dotenv()

SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_KEY')
SUPABASE_ACCESS_TOKEN = os.getenv('SUPABASE_ACCESS_TOKEN', '')
project_ref = SUPABASE_URL.replace('https://', '').replace('http://', '').replace('.supabase.co', '')

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
    
    # Form type
    if 'Form' in form:
        form_val = form['Form']
        if isinstance(form_val, str):
            result['form_type'] = form_val.upper().strip()
    
    # Income
    if 'Income' in form:
        result['income'] = parse_decimal(form['Income'])
    
    # Withholding
    if 'Withholding' in form:
        result['withholding'] = parse_decimal(form['Withholding'])
    
    # Extract from Fields
    if 'Fields' in form and isinstance(form['Fields'], dict):
        fields = form['Fields']
        result['issuer_name'] = fields.get('PayerName') or fields.get('EmployerName')
        result['issuer_ein'] = fields.get('PayerEIN') or fields.get('EmployerEIN')
        result['recipient_name'] = fields.get('RecipientName') or fields.get('EmployeeName')
        result['recipient_ssn'] = fields.get('RecipientSSN') or fields.get('EmployeeSSN')
    
    if result['form_type'] is None:
        result['form_type'] = 'UNKNOWN'
    
    return result

def process_wi_direct_sql(case_id: str):
    print("=" * 80)
    print("🔄 PROCESSING WI DATA (DIRECT SQL)")
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
    
    # Collect all inserts
    inserts = []
    
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
                    
                    fields = extract_all_fields(form)
                    wi_rule = get_wi_rule(fields['form_type'])
                    
                    # Build SQL insert
                    inserts.append({
                        'tax_year_id': str(tax_year_id),
                        'document_type': fields['form_type'],
                        'gross_amount': fields['income'],
                        'federal_withholding': fields['withholding'],
                        'issuer_name': fields['issuer_name'],
                        'issuer_id': str(fields['issuer_ein']) if fields['issuer_ein'] else None,
                        'recipient_name': fields['recipient_name'],
                        'recipient_id': str(fields['recipient_ssn']) if fields['recipient_ssn'] else None,
                        'calculated_category': wi_rule.get('category') if wi_rule else 'Unknown',
                        'is_self_employment': wi_rule.get('is_self_employment') if wi_rule else False
                    })
    
    print(f"📝 Prepared {len(inserts)} inserts")
    print("   Executing via direct SQL (bypassing triggers)...")
    print()
    
    # Execute via Supabase Management API (direct SQL)
    url = f'https://api.supabase.com/v1/projects/{project_ref}/database/query'
    headers = {
        'Authorization': f'Bearer {SUPABASE_ACCESS_TOKEN}',
        'Content-Type': 'application/json'
    }
    
    # Build bulk insert SQL
    for i, insert in enumerate(inserts):  # Process all inserts
        values = []
        values.append(f"'{insert['tax_year_id']}'::uuid")
        
        doc_type = insert['document_type'].replace("'", "''")
        values.append(f"'{doc_type}'")
        
        values.append(str(insert['gross_amount']))
        values.append(str(insert['federal_withholding']))
        
        if insert['calculated_category']:
            cat = insert['calculated_category'].replace("'", "''")
            values.append(f"'{cat}'")
        else:
            values.append('NULL')
        
        values.append('TRUE' if insert['is_self_employment'] else 'FALSE')
        
        if insert['issuer_name']:
            issuer_name = insert['issuer_name'].replace("'", "''")
            values.append(f"'{issuer_name}'")
        else:
            values.append('NULL')
        
        if insert['issuer_id']:
            issuer_id = insert['issuer_id'].replace("'", "''")
            values.append(f"'{issuer_id}'")
        else:
            values.append('NULL')
        
        if insert['recipient_name']:
            recipient_name = insert['recipient_name'].replace("'", "''")
            values.append(f"'{recipient_name}'")
        else:
            values.append('NULL')
        
        if insert['recipient_id']:
            recipient_id = insert['recipient_id'].replace("'", "''")
            values.append(f"'{recipient_id}'")
        else:
            values.append('NULL')
        
        sql = f"""
        INSERT INTO income_documents (
            tax_year_id, document_type, gross_amount, federal_withholding,
            calculated_category, is_self_employment,
            issuer_name, issuer_id, recipient_name, recipient_id
        ) VALUES (
            {', '.join(values)}
        ) ON CONFLICT DO NOTHING;
        """
        
        try:
            payload = {'query': sql}
            response = requests.post(url, json=payload, headers=headers, timeout=30)
            if response.status_code in [200, 201]:
                total_processed += 1
                if total_processed == 1:
                    print(f"   ✅ First insert successful: {insert['document_type']}")
            else:
                if total_processed == 0:
                    print(f"   ⚠️  Error: {response.text[:200]}")
        except Exception as e:
            if total_processed == 0:
                print(f"   ⚠️  Exception: {str(e)[:200]}")
    
    print()
    print("=" * 80)
    print(f"✅ Processed {total_processed} income documents")
    print("=" * 80)

if __name__ == "__main__":
    case_id = sys.argv[1] if len(sys.argv) > 1 else "1295022"
    process_wi_direct_sql(case_id)

