#!/usr/bin/env python3
"""Debug WI form structure"""
from supabase import create_client
import os
from dotenv import load_dotenv
import json
load_dotenv()

supabase = create_client(os.getenv('SUPABASE_URL'), os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_KEY'))

bronze_wi = supabase.table('bronze_wi_raw').select('raw_response').eq('case_id', '1295022').limit(1).execute()

if bronze_wi.data:
    raw_response = bronze_wi.data[0]['raw_response']
    
    if 'years_data' in raw_response:
        years_data = raw_response['years_data']
        first_year = list(years_data.keys())[0]
        year_data = years_data[first_year]
        
        if 'forms' in year_data and year_data['forms']:
            form = year_data['forms'][0]
            print(json.dumps(form, indent=2))

