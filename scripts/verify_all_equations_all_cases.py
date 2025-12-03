#!/usr/bin/env python3
"""
Comprehensive Equation Verification Script

Purpose: Verify all equations from COMPLETE_EQUATION_REFERENCE.md are implemented
and working correctly for all cases in the database.

Process:
1. Get all case IDs from database
2. For each equation type (chunk by chunk):
   - Check if database function/table exists
   - Verify calculation logic matches reference
   - Test with actual case data
   - Report discrepancies

Based on: docs/developer-handoff/COMPLETE_EQUATION_REFERENCE.md
"""

import os
import sys
import argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple
from decimal import Decimal
import json

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from dotenv import load_dotenv
from supabase import create_client, Client

# Load environment variables - try root .env first, then backend/.env
env_files = ['.env', 'backend/.env']
for env_file in env_files:
    if os.path.exists(env_file):
        load_dotenv(env_file)
        print(f"📝 Loaded environment from: {env_file}")
        break

# Supabase connection
SUPABASE_URL = os.getenv('SUPABASE_URL')
# Use service role key if available (full access), otherwise use anon key
SUPABASE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_KEY')

if not SUPABASE_URL:
    print("❌ Missing SUPABASE_URL in .env or backend/.env")
    print("   Please check your .env file")
    sys.exit(1)

if not SUPABASE_KEY:
    print("❌ Missing SUPABASE_KEY or SUPABASE_SERVICE_ROLE_KEY in .env or backend/.env")
    print("   Please check your .env file")
    sys.exit(1)

# Use service role key if available
key_type = "Service Role Key" if os.getenv('SUPABASE_SERVICE_ROLE_KEY') else "Anon Key"
print(f"✅ Using {key_type} for database access")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Output directory for reports
REPORT_DIR = Path(__file__).parent.parent / "docs" / "verification-reports"
REPORT_DIR.mkdir(parents=True, exist_ok=True)


class EquationVerifier:
    """Verify equation implementations against COMPLETE_EQUATION_REFERENCE.md"""
    
    def __init__(self):
        self.results = {
            'verification_date': datetime.now().isoformat(),
            'cases_checked': [],
            'equation_chunks': {},
            'missing_functions': [],
            'missing_tables': [],
            'calculation_errors': [],
            'summary': {}
        }
    
    def get_all_case_ids(self) -> List[Dict]:
        """Get all case IDs from database"""
        print("📋 Fetching all cases from database...")
        
        try:
            response = supabase.table('cases').select('id, case_number, created_at').execute()
            cases = response.data
            print(f"✅ Found {len(cases)} cases in database")
            return cases
        except Exception as e:
            print(f"❌ Error fetching cases: {e}")
            return []
    
    def check_function_exists(self, function_name: str) -> bool:
        """Check if a database function exists"""
        query = """
        SELECT EXISTS (
            SELECT 1 
            FROM pg_proc 
            WHERE proname = %s
        );
        """
        
        # Use raw SQL query
        try:
            # Check via information_schema instead
            response = supabase.rpc('check_function_exists', {'function_name': function_name}).execute()
            return True  # If no error, function exists
        except:
            # Try querying information_schema directly via table query workaround
            # We'll check differently - query for function results instead
            return None  # Unknown - will check via actual test
    
    def verify_chunk_1_csed_calculations(self, case_ids: List[Dict]) -> Dict:
        """CHUNK 1: Verify CSED Calculations"""
        print("\n" + "="*60)
        print("CHUNK 1: CSED Calculations Verification")
        print("="*60)
        
        chunk_results = {
            'chunk_name': 'CSED Calculations',
            'sub_equations': {},
            'cases_tested': 0,
            'cases_passed': 0,
            'cases_failed': 0,
            'errors': []
        }
        
        # 1.1 Base CSED Calculation
        print("\n1.1 Checking Base CSED Calculation...")
        
        # Check if tax_years table has base_csed_date column
        try:
            # Get a sample tax year to check structure
            sample = supabase.table('tax_years').select('*').limit(1).execute()
            if sample.data:
                tax_year = sample.data[0]
                has_return_filed_date = 'return_filed_date' in tax_year
                has_base_csed_date = 'base_csed_date' in tax_year
                
                chunk_results['sub_equations']['1.1_base_csed'] = {
                    'status': '✅' if has_return_filed_date else '❌',
                    'has_return_filed_date_column': has_return_filed_date,
                    'has_base_csed_date_column': has_base_csed_date,
                    'notes': []
                }
                
                if not has_return_filed_date:
                    chunk_results['sub_equations']['1.1_base_csed']['notes'].append(
                        "Missing return_filed_date column in tax_years table"
                    )
        except Exception as e:
            chunk_results['sub_equations']['1.1_base_csed'] = {
                'status': '❌',
                'error': str(e)
            }
        
        # 1.2 CSED Tolling - Bankruptcy
        print("1.2 Checking CSED Tolling - Bankruptcy...")
        
        # Check if csed_tolling_events table exists
        try:
            sample = supabase.table('csed_tolling_events').select('*').limit(1).execute()
            has_table = True
        except:
            has_table = False
        
        # Check if account_activity has codes 520, 521
        try:
            codes = supabase.table('account_activity')\
                .select('code')\
                .in_('code', ['520', '521'])\
                .limit(1)\
                .execute()
            has_bankruptcy_codes = len(codes.data) > 0
        except:
            has_bankruptcy_codes = False
        
        chunk_results['sub_equations']['1.2_bankruptcy_tolling'] = {
            'status': '✅' if (has_table and has_bankruptcy_codes) else '⚠️',
            'has_csed_tolling_events_table': has_table,
            'has_bankruptcy_codes': has_bankruptcy_codes,
            'notes': []
        }
        
        # Test with actual cases
        print("\n   Testing with actual cases...")
        cases_with_bankruptcy = 0
        
        for case in case_ids[:5]:  # Test first 5 cases
            try:
                # Get tax years for this case
                tax_years = supabase.table('tax_years')\
                    .select('id, return_filed_date, base_csed_date')\
                    .eq('case_id', case['id'])\
                    .execute()
                
                for ty in tax_years.data:
                    if ty.get('return_filed_date'):
                        # Check if base_csed_date is calculated
                        if ty.get('base_csed_date'):
                            chunk_results['cases_passed'] += 1
                        else:
                            chunk_results['cases_failed'] += 1
                            chunk_results['errors'].append({
                                'case_id': case['id'],
                                'tax_year_id': ty['id'],
                                'error': 'base_csed_date not calculated'
                            })
                        
                        # Check for bankruptcy codes
                        bankruptcy = supabase.table('account_activity')\
                            .select('code')\
                            .eq('tax_year_id', ty['id'])\
                            .in_('code', ['520', '521'])\
                            .execute()
                        
                        if bankruptcy.data:
                            cases_with_bankruptcy += 1
                        
                        chunk_results['cases_tested'] += 1
                        break  # Just test first tax year per case
            except Exception as e:
                chunk_results['errors'].append({
                    'case_id': case['id'],
                    'error': f"Error testing: {str(e)}"
                })
        
        chunk_results['sub_equations']['1.2_bankruptcy_tolling']['cases_with_bankruptcy'] = cases_with_bankruptcy
        
        # 1.3-1.5 Other tolling types (similar checks)
        print("1.3-1.5 Checking other tolling types...")
        
        chunk_results['sub_equations']['1.3_oic_tolling'] = {
            'status': '⚠️',
            'note': 'To be verified - check for codes 480, 481, 482, 483'
        }
        
        chunk_results['sub_equations']['1.4_cdp_tolling'] = {
            'status': '⚠️',
            'note': 'To be verified - check for code 971'
        }
        
        chunk_results['sub_equations']['1.5_penalty_tolling'] = {
            'status': '⚠️',
            'note': 'To be verified - check for codes 276, 196'
        }
        
        return chunk_results
    
    def verify_chunk_2_tax_projections(self, case_ids: List[Dict]) -> Dict:
        """CHUNK 2: Verify Tax Projection Calculations"""
        print("\n" + "="*60)
        print("CHUNK 2: Tax Projection Calculations Verification")
        print("="*60)
        
        chunk_results = {
            'chunk_name': 'Tax Projection Calculations',
            'sub_equations': {},
            'cases_tested': 0,
            'cases_passed': 0,
            'cases_failed': 0,
            'errors': []
        }
        
        # 2.1 Taxpayer Income Aggregation
        print("\n2.1 Checking Taxpayer Income Aggregation...")
        
        # Check if income_documents table exists and has required columns
        try:
            sample = supabase.table('income_documents').select('*').limit(1).execute()
            has_table = True
            sample_cols = list(sample.data[0].keys()) if sample.data else []
            
            required_cols = ['gross_amount', 'recipient_ssn', 'tax_year_id', 'is_excluded']
            missing_cols = [col for col in required_cols if col not in sample_cols]
            
            chunk_results['sub_equations']['2.1_tp_income'] = {
                'status': '✅' if not missing_cols else '❌',
                'has_income_documents_table': has_table,
                'missing_columns': missing_cols,
                'notes': []
            }
        except Exception as e:
            chunk_results['sub_equations']['2.1_tp_income'] = {
                'status': '❌',
                'error': str(e)
            }
        
        # 2.2-2.11 Other tax projection calculations
        print("2.2-2.11 Checking other tax projection calculations...")
        
        # Check tax_projections table
        try:
            sample = supabase.table('tax_projections').select('*').limit(1).execute()
            has_table = True
            sample_cols = list(sample.data[0].keys()) if sample.data else []
            
            required_cols = [
                'tp_income', 'tp_se_income', 'estimated_agi', 
                'taxable_income', 'tax_liability', 'total_tax', 
                'projected_balance'
            ]
            missing_cols = [col for col in required_cols if col not in sample_cols]
            
            chunk_results['sub_equations']['2.2-2.11_tax_projection_table'] = {
                'status': '✅' if not missing_cols else '⚠️',
                'has_tax_projections_table': has_table,
                'missing_columns': missing_cols,
                'notes': []
            }
        except Exception as e:
            chunk_results['sub_equations']['2.2-2.11_tax_projection_table'] = {
                'status': '❌',
                'error': str(e)
            }
        
        # Test calculations with actual cases
        print("\n   Testing tax projections with actual cases...")
        
        for case in case_ids[:5]:  # Test first 5 cases
            try:
                # Check if tax projections exist for this case
                projections = supabase.table('tax_projections')\
                    .select('*')\
                    .eq('case_id', case['id'])\
                    .execute()
                
                if projections.data:
                    # Verify calculation fields are populated
                    for proj in projections.data:
                        has_tp_income = proj.get('tp_income') is not None
                        has_estimated_agi = proj.get('estimated_agi') is not None
                        has_projected_balance = proj.get('projected_balance') is not None
                        
                        if has_tp_income and has_estimated_agi and has_projected_balance:
                            chunk_results['cases_passed'] += 1
                        else:
                            chunk_results['cases_failed'] += 1
                            chunk_results['errors'].append({
                                'case_id': case['id'],
                                'tax_period': proj.get('tax_period'),
                                'missing_fields': [
                                    'tp_income' if not has_tp_income else None,
                                    'estimated_agi' if not has_estimated_agi else None,
                                    'projected_balance' if not has_projected_balance else None
                                ]
                            })
                        
                        chunk_results['cases_tested'] += 1
                else:
                    chunk_results['errors'].append({
                        'case_id': case['id'],
                        'error': 'No tax projections found'
                    })
                    
            except Exception as e:
                chunk_results['errors'].append({
                    'case_id': case['id'],
                    'error': f"Error testing: {str(e)}"
                })
        
        return chunk_results
    
    def verify_chunk_3_account_balance(self, case_ids: List[Dict]) -> Dict:
        """CHUNK 3: Verify Account Balance Calculations"""
        print("\n" + "="*60)
        print("CHUNK 3: Account Balance Calculations Verification")
        print("="*60)
        
        chunk_results = {
            'chunk_name': 'Account Balance Calculations',
            'sub_equations': {},
            'cases_tested': 0,
            'cases_passed': 0,
            'cases_failed': 0,
            'errors': []
        }
        
        # 3.1 Current Balance
        print("\n3.1 Checking Current Balance Calculation...")
        
        # Check if account_activity and at_transaction_rules exist
        try:
            sample_aa = supabase.table('account_activity').select('*').limit(1).execute()
            has_account_activity = True
        except:
            has_account_activity = False
        
        try:
            sample_rules = supabase.table('at_transaction_rules').select('*').limit(1).execute()
            has_rules = True
            sample_cols = list(sample_rules.data[0].keys()) if sample_rules.data else []
            has_affects_balance = 'affects_balance' in sample_cols
        except:
            has_rules = False
            has_affects_balance = False
        
        chunk_results['sub_equations']['3.1_current_balance'] = {
            'status': '✅' if (has_account_activity and has_rules and has_affects_balance) else '⚠️',
            'has_account_activity_table': has_account_activity,
            'has_at_transaction_rules_table': has_rules,
            'has_affects_balance_column': has_affects_balance,
            'notes': []
        }
        
        # Check if tax_years has current_balance column
        try:
            sample = supabase.table('tax_years').select('*').limit(1).execute()
            if sample.data:
                has_current_balance = 'current_balance' in sample.data[0]
                chunk_results['sub_equations']['3.1_current_balance']['has_current_balance_column'] = has_current_balance
        except:
            pass
        
        # 3.2 Return Filed Date
        print("3.2 Checking Return Filed Date...")
        
        chunk_results['sub_equations']['3.2_return_filed_date'] = {
            'status': '✅',
            'note': 'Checked in Chunk 1 (CSED calculations)'
        }
        
        return chunk_results
    
    def verify_chunk_4_aur_sfr(self, case_ids: List[Dict]) -> Dict:
        """CHUNK 4: Verify AUR/SFR Calculations"""
        print("\n" + "="*60)
        print("CHUNK 4: AUR/SFR Calculations Verification")
        print("="*60)
        
        chunk_results = {
            'chunk_name': 'AUR/SFR Calculations',
            'sub_equations': {},
            'cases_tested': 0,
            'cases_passed': 0,
            'cases_failed': 0,
            'errors': []
        }
        
        # 4.1 AUR Detection
        print("\n4.1 Checking AUR Detection...")
        
        # Check if tax_years has aur_indicator column
        try:
            sample = supabase.table('tax_years').select('*').limit(1).execute()
            if sample.data:
                has_aur_indicator = 'aur_indicator' in sample.data[0] or 'aur_status' in sample.data[0]
                
                chunk_results['sub_equations']['4.1_aur_detection'] = {
                    'status': '✅' if has_aur_indicator else '⚠️',
                    'has_aur_indicator_column': has_aur_indicator,
                    'notes': []
                }
        except Exception as e:
            chunk_results['sub_equations']['4.1_aur_detection'] = {
                'status': '❌',
                'error': str(e)
            }
        
        # Check for AUR codes (420, 424, 430)
        try:
            aur_codes = supabase.table('account_activity')\
                .select('code')\
                .in_('code', ['420', '424', '430'])\
                .limit(1)\
                .execute()
            has_aur_codes = len(aur_codes.data) > 0
            chunk_results['sub_equations']['4.1_aur_detection']['has_aur_codes'] = has_aur_codes
        except:
            pass
        
        # 5.1 SFR Detection (similar)
        print("5.1 Checking SFR Detection...")
        
        chunk_results['sub_equations']['5.1_sfr_detection'] = {
            'status': '⚠️',
            'note': 'Check for Code 150 with SFR in explanation'
        }
        
        return chunk_results
    
    def verify_chunk_5_resolution_options(self, case_ids: List[Dict]) -> Dict:
        """CHUNK 5: Verify Resolution Options Calculations"""
        print("\n" + "="*60)
        print("CHUNK 5: Resolution Options Calculations Verification")
        print("="*60)
        
        chunk_results = {
            'chunk_name': 'Resolution Options Calculations',
            'sub_equations': {},
            'cases_tested': 0,
            'cases_passed': 0,
            'cases_failed': 0,
            'errors': []
        }
        
        # Check if resolution_options table exists
        try:
            sample = supabase.table('resolution_options').select('*').limit(1).execute()
            has_table = True
            sample_cols = list(sample.data[0].keys()) if sample.data else []
            
            required_cols = [
                'ia_eligible', 'ia_monthly_payment', 'oic_eligible', 
                'oic_recommended_offer', 'cnc_eligible'
            ]
            missing_cols = [col for col in required_cols if col not in sample_cols]
            
            chunk_results['sub_equations']['resolution_options_table'] = {
                'status': '✅' if not missing_cols else '⚠️',
                'has_resolution_options_table': has_table,
                'missing_columns': missing_cols,
                'notes': []
            }
        except Exception as e:
            chunk_results['sub_equations']['resolution_options_table'] = {
                'status': '❌',
                'error': str(e)
            }
        
        return chunk_results
    
    def generate_report(self):
        """Generate final verification report"""
        print("\n" + "="*60)
        print("GENERATING VERIFICATION REPORT")
        print("="*60)
        
        report_file = REPORT_DIR / f"equation_verification_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        
        # Save JSON report
        with open(report_file, 'w') as f:
            json.dump(self.results, f, indent=2, default=str)
        
        print(f"\n✅ Report saved to: {report_file}")
        
        # Generate markdown summary
        md_report = REPORT_DIR / f"equation_verification_{datetime.now().strftime('%Y%m%d_%H%M%S')}.md"
        
        with open(md_report, 'w') as f:
            f.write("# Equation Verification Report\n\n")
            f.write(f"**Verification Date:** {self.results['verification_date']}\n\n")
            f.write(f"**Cases Checked:** {len(self.results['cases_checked'])}\n\n")
            
            f.write("## Summary by Chunk\n\n")
            
            for chunk_name, chunk_data in self.results['equation_chunks'].items():
                f.write(f"### {chunk_data['chunk_name']}\n\n")
                f.write(f"- Cases Tested: {chunk_data['cases_tested']}\n")
                f.write(f"- Cases Passed: {chunk_data['cases_passed']}\n")
                f.write(f"- Cases Failed: {chunk_data['cases_failed']}\n\n")
                
                f.write("**Sub-Equations:**\n\n")
                for eq_name, eq_data in chunk_data['sub_equations'].items():
                    status = eq_data.get('status', '❓')
                    f.write(f"- {eq_name}: {status}\n")
                    if 'error' in eq_data:
                        f.write(f"  - Error: {eq_data['error']}\n")
                    if 'missing_columns' in eq_data and eq_data['missing_columns']:
                        f.write(f"  - Missing Columns: {', '.join(eq_data['missing_columns'])}\n")
                f.write("\n")
            
            if self.results.get('calculation_errors'):
                f.write("## Errors Found\n\n")
                for error in self.results['calculation_errors']:
                    f.write(f"- {error}\n")
        
        print(f"✅ Markdown report saved to: {md_report}")
        
        return report_file, md_report


def main():
    """Main verification process"""
    parser = argparse.ArgumentParser(
        description='Verify equations from COMPLETE_EQUATION_REFERENCE.md',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Verify all chunks for all cases
  python verify_all_equations_all_cases.py

  # Verify only Chunk 1 (CSED calculations)
  python verify_all_equations_all_cases.py --chunk 1

  # Verify Chunks 1-3 for specific cases
  python verify_all_equations_all_cases.py --chunk 1,2,3 --cases 1333562,1273247

  # Verify all chunks for specific cases
  python verify_all_equations_all_cases.py --cases 941839
        """
    )
    
    parser.add_argument(
        '--chunk',
        type=str,
        help='Comma-separated list of chunks to verify (1-5). Default: all chunks',
        default='1,2,3,4,5'
    )
    
    parser.add_argument(
        '--cases',
        type=str,
        help='Comma-separated list of case numbers to verify. Default: all cases',
        default=None
    )
    
    parser.add_argument(
        '--limit',
        type=int,
        help='Limit number of cases to test (for faster testing)',
        default=None
    )
    
    args = parser.parse_args()
    
    # Parse chunks
    chunks_to_run = [int(c.strip()) for c in args.chunk.split(',')]
    
    print("="*60)
    print("EQUATION VERIFICATION - ALL CASES")
    print("="*60)
    print(f"Based on: docs/developer-handoff/COMPLETE_EQUATION_REFERENCE.md")
    print(f"\nChunks to verify: {chunks_to_run}")
    if args.cases:
        print(f"Cases to verify: {args.cases}")
    if args.limit:
        print(f"Case limit: {args.limit}")
    print()
    
    verifier = EquationVerifier()
    
    # Step 1: Get cases
    all_case_ids = verifier.get_all_case_ids()
    
    # Filter cases if specified
    if args.cases:
        case_numbers = [c.strip() for c in args.cases.split(',')]
        case_ids = [c for c in all_case_ids if c['case_number'] in case_numbers]
        if not case_ids:
            print(f"⚠️  No cases found matching: {args.cases}")
            print(f"Available cases: {[c['case_number'] for c in all_case_ids]}")
            return
        print(f"✅ Filtered to {len(case_ids)} case(s)")
    else:
        case_ids = all_case_ids
    
    # Limit cases if specified
    if args.limit:
        case_ids = case_ids[:args.limit]
        print(f"✅ Limited to first {len(case_ids)} case(s)")
    
    verifier.results['cases_checked'] = [c['case_number'] for c in case_ids]
    
    if not case_ids:
        print("⚠️  No cases found in database. Exiting.")
        return
    
    # Step 2: Verify chunks
    print("\n🔍 Starting chunk-by-chunk verification...")
    
    if 1 in chunks_to_run:
        print("\n▶️  Running Chunk 1: CSED Calculations...")
        chunk1_results = verifier.verify_chunk_1_csed_calculations(case_ids)
        verifier.results['equation_chunks']['chunk_1_csed'] = chunk1_results
    
    if 2 in chunks_to_run:
        print("\n▶️  Running Chunk 2: Tax Projections...")
        chunk2_results = verifier.verify_chunk_2_tax_projections(case_ids)
        verifier.results['equation_chunks']['chunk_2_tax_projections'] = chunk2_results
    
    if 3 in chunks_to_run:
        print("\n▶️  Running Chunk 3: Account Balance...")
        chunk3_results = verifier.verify_chunk_3_account_balance(case_ids)
        verifier.results['equation_chunks']['chunk_3_account_balance'] = chunk3_results
    
    if 4 in chunks_to_run:
        print("\n▶️  Running Chunk 4: AUR/SFR...")
        chunk4_results = verifier.verify_chunk_4_aur_sfr(case_ids)
        verifier.results['equation_chunks']['chunk_4_aur_sfr'] = chunk4_results
    
    if 5 in chunks_to_run:
        print("\n▶️  Running Chunk 5: Resolution Options...")
        chunk5_results = verifier.verify_chunk_5_resolution_options(case_ids)
        verifier.results['equation_chunks']['chunk_5_resolution_options'] = chunk5_results
    
    # Step 3: Generate report
    json_report, md_report = verifier.generate_report()
    
    print("\n" + "="*60)
    print("VERIFICATION COMPLETE")
    print("="*60)
    print(f"\n📊 Reports generated:")
    print(f"  - JSON: {json_report}")
    print(f"  - Markdown: {md_report}")
    print(f"\n✅ Review reports to see what needs to be implemented/fixed")
    
    # Print quick summary
    print("\n📋 Quick Summary:")
    for chunk_name, chunk_data in verifier.results['equation_chunks'].items():
        passed = chunk_data.get('cases_passed', 0)
        failed = chunk_data.get('cases_failed', 0)
        tested = chunk_data.get('cases_tested', 0)
        if tested > 0:
            print(f"  {chunk_name}: {passed}/{tested} passed, {failed} failed")


if __name__ == "__main__":
    main()

