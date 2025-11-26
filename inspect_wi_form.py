from supabase import create_client
import os, json
from dotenv import load_dotenv
load_dotenv()

supabase = create_client(os.getenv('SUPABASE_URL'), os.getenv('SUPABASE_SERVICE_ROLE_KEY'))

bronze_wi = supabase.table('bronze_wi_raw').select('raw_response').eq('case_id', '1295022').limit(1).execute()

if bronze_wi.data:
    raw = bronze_wi.data[0]['raw_response']
    if 'years_data' in raw:
        yd = raw['years_data']
        fy = list(yd.keys())[0]
        ydata = yd[fy]
        if 'forms' in ydata:
            forms = ydata['forms']
            if forms:
                f = forms[0]
                print(json.dumps(f, indent=2, default=str)[:2000])

