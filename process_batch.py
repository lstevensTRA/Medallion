#!/usr/bin/env python3
"""
Batch Process Cases Through Medallion Pipeline

Triggers data extraction for multiple cases and monitors progress.
"""

import requests
import time
import sys
from typing import List, Dict, Any
from datetime import datetime

BACKEND_URL = "http://localhost:8000"


def check_backend_health() -> bool:
    """Check if backend is running"""
    try:
        response = requests.get(f"{BACKEND_URL}/health", timeout=5)
        return response.status_code == 200
    except:
        return False


def trigger_extraction(case_id: str) -> Dict[str, Any]:
    """
    Trigger data extraction for a single case
    
    Args:
        case_id: Case ID to process
    
    Returns:
        Response from backend
    """
    try:
        response = requests.post(
            f"{BACKEND_URL}/api/dagster/cases/{case_id}/extract",
            timeout=10
        )
        
        if response.status_code == 200:
            return response.json()
        else:
            return {
                "case_id": case_id,
                "status": "failed",
                "error": f"HTTP {response.status_code}",
                "detail": response.text
            }
    except Exception as e:
        return {
            "case_id": case_id,
            "status": "failed",
            "error": str(e)
        }


def get_case_status(case_id: str) -> Dict[str, Any]:
    """Get processing status for a case"""
    try:
        response = requests.get(
            f"{BACKEND_URL}/api/dagster/status/{case_id}",
            timeout=10
        )
        
        if response.status_code == 200:
            return response.json()
        else:
            return {
                "case_id": case_id,
                "status": "error",
                "error": f"HTTP {response.status_code}"
            }
    except Exception as e:
        return {
            "case_id": case_id,
            "status": "error",
            "error": str(e)
        }


def process_batch(case_ids: List[str], delay_seconds: int = 3) -> List[Dict]:
    """
    Process a batch of cases
    
    Args:
        case_ids: List of case IDs to process
        delay_seconds: Seconds to wait between triggering cases
    
    Returns:
        List of trigger results
    """
    print("\n" + "="*80)
    print(f"🚀 BATCH PROCESSING: {len(case_ids)} CASES")
    print("="*80)
    
    results = []
    
    for i, case_id in enumerate(case_ids, 1):
        print(f"\n[{i}/{len(case_ids)}] Processing case {case_id}...")
        
        result = trigger_extraction(case_id)
        results.append(result)
        
        if result.get("status") == "triggered":
            print(f"  ✅ Triggered successfully")
            print(f"  📊 Process ID: {result.get('process_id')}")
        elif result.get("status") == "failed":
            print(f"  ❌ Failed: {result.get('error')}")
            if 'detail' in result:
                print(f"  ℹ️  Detail: {result['detail'][:100]}")
        else:
            print(f"  ⚠️  Unknown status: {result}")
        
        # Wait between requests (except for last one)
        if i < len(case_ids):
            time.sleep(delay_seconds)
    
    return results


def check_batch_status(case_ids: List[str]):
    """Check and display status for all cases"""
    print("\n" + "="*80)
    print("📊 BATCH STATUS REPORT")
    print("="*80)
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    summary = {
        "complete": 0,
        "bronze_only": 0,
        "silver_only": 0,
        "not_started": 0,
        "error": 0
    }
    
    for case_id in case_ids:
        status = get_case_status(case_id)
        
        case_status = status.get('status', 'unknown')
        summary[case_status] = summary.get(case_status, 0) + 1
        
        # Status emoji
        status_emoji = {
            "complete": "✅",
            "silver_only": "🟡",
            "bronze_only": "🟠",
            "not_started": "⚪",
            "error": "❌"
        }.get(case_status, "❓")
        
        print(f"{status_emoji} Case {case_id}: {case_status.upper()}")
        
        if case_status in ["complete", "silver_only", "bronze_only"]:
            bronze = status.get('bronze', {})
            silver = status.get('silver', {})
            gold = status.get('gold', {})
            
            print(f"   Bronze: {bronze.get('total_records', 0)} records")
            print(f"   Silver: {silver.get('total_records', 0)} records")
            print(f"   Gold: {gold.get('total_records', 0)} records")
        
        print()
    
    # Summary
    print("="*80)
    print("SUMMARY:")
    print(f"  ✅ Complete: {summary['complete']}")
    print(f"  🟡 Processing: {summary.get('silver_only', 0) + summary.get('bronze_only', 0)}")
    print(f"  ⚪ Not Started: {summary['not_started']}")
    print(f"  ❌ Errors: {summary['error']}")
    print("="*80)
    
    return summary


def main():
    """Main execution"""
    # Check if backend is running
    print("🔍 Checking backend health...")
    if not check_backend_health():
        print("❌ Backend is not running!")
        print("   Start it with: ./start_all.sh")
        sys.exit(1)
    
    print("✅ Backend is healthy")
    
    # Your 10 test cases (EDIT THIS LIST)
    test_cases = [
        "1295022",
        # Add your other 9 case IDs here:
        # "1234567",
        # "2345678",
        # "3456789",
        # "4567890",
        # "5678901",
        # "6789012",
        # "7890123",
        # "8901234",
        # "9012345",
    ]
    
    print(f"\n📋 Found {len(test_cases)} cases to process")
    print(f"   Case IDs: {', '.join(test_cases)}")
    
    # Confirm
    response = input("\n👉 Continue? (y/n): ")
    if response.lower() != 'y':
        print("❌ Aborted")
        sys.exit(0)
    
    # Process batch
    results = process_batch(test_cases)
    
    # Count successes
    triggered = sum(1 for r in results if r.get('status') == 'triggered')
    failed = sum(1 for r in results if r.get('status') == 'failed')
    
    print(f"\n✅ Triggered: {triggered}/{len(test_cases)}")
    print(f"❌ Failed: {failed}/{len(test_cases)}")
    
    # Wait for processing
    print("\n⏳ Waiting 5 minutes for processing...")
    print("   (You can monitor in Dagster UI: http://localhost:3000)")
    
    for i in range(5, 0, -1):
        print(f"   {i} minutes remaining...")
        time.sleep(60)
    
    # Check final status
    print("\n🔍 Checking final status...")
    summary = check_batch_status(test_cases)
    
    # Final message
    if summary['complete'] == len(test_cases):
        print("\n🎉 SUCCESS! All cases processed completely!")
    elif summary['complete'] > 0:
        print(f"\n✅ Partial success: {summary['complete']}/{len(test_cases)} cases complete")
        print("   Check Dagster UI for details on incomplete cases")
    else:
        print("\n⚠️  No cases completed yet. Check:")
        print("   1. Dagster UI: http://localhost:3000")
        print("   2. Backend logs")
        print("   3. TiParser API key validity")
    
    print("\n📊 View results in Supabase Dashboard:")
    print("   https://supabase.com/dashboard")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Interrupted by user")
        sys.exit(0)
    except Exception as e:
        print(f"\n❌ Error: {str(e)}")
        sys.exit(1)

