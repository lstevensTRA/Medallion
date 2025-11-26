#!/usr/bin/env python3
"""
Trigger Bronze Ingestion for a Case

Automatically triggers Dagster to ingest data for a specific case.
"""

import sys
from pathlib import Path
from dotenv import load_dotenv
from dagster import materialize, DagsterInstance
from dagster_pipeline import defs
from dagster_pipeline.assets.bronze_assets import (
    bronze_at_data,
    bronze_wi_data,
    bronze_trt_data,
    bronze_interview_data
)

# Load environment variables from .env file
env_path = Path(__file__).parent / ".env"
load_dotenv(env_path)


def trigger_case_ingestion(case_id: str, case_number: str = None):
    """
    Trigger Bronze ingestion for a specific case
    
    Args:
        case_id: Case ID (e.g., "1295022")
        case_number: Optional case number for logging
    """
    if not case_number:
        case_number = f"CASE-{case_id}"
    
    print("=" * 80)
    print(f"🚀 TRIGGERING BRONZE INGESTION FOR CASE {case_number}")
    print("=" * 80)
    print(f"   Case ID: {case_id}")
    print(f"   Case Number: {case_number}")
    print()
    
    # Configuration for all Bronze assets
    config = {
        "ops": {
            "bronze_at_data": {
                "config": {
                    "case_id": case_id,
                    "case_number": case_number
                }
            },
            "bronze_wi_data": {
                "config": {
                    "case_id": case_id,
                    "case_number": case_number
                }
            },
            "bronze_trt_data": {
                "config": {
                    "case_id": case_id,
                    "case_number": case_number
                }
            },
            "bronze_interview_data": {
                "config": {
                    "case_id": case_id,
                    "case_number": case_number
                }
            }
        }
    }
    
    # Get Dagster instance
    instance = DagsterInstance.get()
    
    assets_to_run = [
        bronze_at_data,
        bronze_wi_data,
        bronze_trt_data,
        bronze_interview_data
    ]
    
    print("📋 Running Assets:")
    for asset in assets_to_run:
        print(f"   • {asset.key}")
    print()
    
    try:
        # Materialize the assets
        print("⏳ Executing Bronze ingestion pipeline...")
        print()
        
        result = materialize(
            assets_to_run,
            instance=instance,
            run_config=config,
            resources={
                "supabase": defs.resources["supabase"],
                "tiparser": defs.resources["tiparser"],
                "pdf_storage": defs.resources["pdf_storage"]
            }
        )
        
        print()
        print("=" * 80)
        
        if result.success:
            print("✅ BRONZE INGESTION COMPLETED SUCCESSFULLY!")
            print("=" * 80)
            print()
            print("📊 Results:")
            
            for asset_key in result.asset_materializations_for_node.keys():
                materializations = result.asset_materializations_for_node[asset_key]
                if materializations:
                    print(f"   ✅ {asset_key}: {len(materializations)} materialization(s)")
            
            print()
            print("🔍 Check the following:")
            print(f"   • Dagster UI: http://localhost:3000/runs/{result.run_id}")
            print(f"   • Bronze tables: bronze_at_raw, bronze_wi_raw, bronze_trt_raw, bronze_interview_raw")
            print(f"   • Silver tables: tax_years, income_documents, account_activity, etc.")
            print(f"   • Gold tables: employment_information, household_information, etc.")
            
        else:
            print("❌ BRONZE INGESTION FAILED")
            print("=" * 80)
            print()
            print("Check Dagster UI for error details:")
            print(f"   http://localhost:3000/runs/{result.run_id}")
        
        print()
        return result.success
        
    except Exception as e:
        print()
        print("=" * 80)
        print("❌ ERROR DURING EXECUTION")
        print("=" * 80)
        print(f"   {str(e)}")
        print()
        import traceback
        traceback.print_exc()
        return False


def main():
    """Main entry point"""
    
    if len(sys.argv) < 2:
        print("Usage: python trigger_case_ingestion.py <case_id> [case_number]")
        print()
        print("Examples:")
        print("  python trigger_case_ingestion.py 1295022")
        print("  python trigger_case_ingestion.py 1295022 CASE-1295022")
        sys.exit(1)
    
    case_id = sys.argv[1]
    case_number = sys.argv[2] if len(sys.argv) > 2 else None
    
    success = trigger_case_ingestion(case_id, case_number)
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()

