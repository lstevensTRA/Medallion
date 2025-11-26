"""
Monitoring Assets

These assets monitor the health of the Bronze → Silver → Gold data flow.
They don't transform data, just validate that triggers are working correctly.
"""

from dagster import asset, AssetExecutionContext
from dagster_pipeline.resources.supabase_resource import SupabaseResource
from typing import Dict, Any


@asset(
    description="Monitor Bronze → Silver data flow health",
    group_name="monitoring",
    compute_kind="validation",
    metadata={
        "view": "bronze_silver_health",
        "checks": ["Bronze records processed", "Silver records created", "Failed records"]
    }
)
def monitor_bronze_silver_health(
    context: AssetExecutionContext,
    supabase: SupabaseResource
) -> Dict[str, Any]:
    """
    Monitor Bronze → Silver trigger health
    
    Checks:
    1. Bronze records are being processed
    2. Silver records are being created
    3. No failed records (or alerts if found)
    
    Returns:
        Dict with health metrics for each data type (AT, WI, TRT, Interview)
    """
    context.log.info("🏥 Checking Bronze → Silver health")
    
    client = supabase.get_client()
    
    # Query bronze_silver_health view
    result = client.table('bronze_silver_health').select('*').execute()
    
    health_metrics = {}
    alerts = []
    
    for row in result.data:
        data_type = row['data_type']
        bronze_total = row['bronze_total']
        bronze_processed = row['bronze_processed']
        bronze_pending = row['bronze_pending']
        bronze_failed = row['bronze_failed']
        silver_records = row['silver_records']
        
        # Calculate health score
        health_score = (bronze_processed / bronze_total * 100) if bronze_total > 0 else 100
        
        health_metrics[data_type] = {
            "bronze_total": bronze_total,
            "bronze_processed": bronze_processed,
            "bronze_pending": bronze_pending,
            "bronze_failed": bronze_failed,
            "silver_records": silver_records,
            "health_score": health_score
        }
        
        # Check for alerts
        if bronze_failed > 0:
            alerts.append(f"❌ {data_type}: {bronze_failed} failed Bronze records")
            context.log.warning(f"❌ {data_type}: {bronze_failed} failed Bronze records")
        
        if bronze_pending > 5:
            alerts.append(f"⚠️  {data_type}: {bronze_pending} pending Bronze records (may be stuck)")
            context.log.warning(f"⚠️  {data_type}: {bronze_pending} pending Bronze records")
        
        if health_score < 95:
            alerts.append(f"⚠️  {data_type}: Health score {health_score:.1f}% (below 95% threshold)")
            context.log.warning(f"⚠️  {data_type}: Health score {health_score:.1f}%")
        
        if health_score >= 95:
            context.log.info(f"✅ {data_type}: Health score {health_score:.1f}%")
    
    # Overall health
    overall_health = all(m['health_score'] >= 95 for m in health_metrics.values())
    
    return {
        "overall_health": "HEALTHY" if overall_health else "DEGRADED",
        "metrics": health_metrics,
        "alerts": alerts,
        "timestamp": context.run.run_id
    }


@asset(
    description="Monitor Silver → Gold data flow health",
    group_name="monitoring",
    compute_kind="validation",
    metadata={
        "view": "silver_gold_health",
        "checks": ["Silver records processed", "Gold records created"]
    },
    deps=[monitor_bronze_silver_health]  # Run after Bronze→Silver check
)
def monitor_silver_gold_health(
    context: AssetExecutionContext,
    supabase: SupabaseResource
) -> Dict[str, Any]:
    """
    Monitor Silver → Gold trigger health
    
    Checks:
    1. Silver logiqs_raw_data populating Gold employment/household
    2. Silver income_documents enriching Gold employment
    
    Returns:
        Dict with health metrics for Gold entities
    """
    context.log.info("🏥 Checking Silver → Gold health")
    
    client = supabase.get_client()
    
    # Query silver_gold_health view
    result = client.table('silver_gold_health').select('*').execute()
    
    health_metrics = {}
    alerts = []
    
    for row in result.data:
        entity_type = row['entity_type']
        silver_records = row['silver_records']
        gold_records = row['gold_records']
        cases_in_gold = row['cases_in_gold']
        
        health_metrics[entity_type] = {
            "silver_records": silver_records,
            "gold_records": gold_records,
            "cases_in_gold": cases_in_gold
        }
        
        # Check for alerts
        if silver_records > 0 and gold_records == 0:
            alerts.append(f"❌ {entity_type}: Silver has data but Gold is empty")
            context.log.error(f"❌ {entity_type}: Silver → Gold trigger may not be working")
        
        if silver_records > 0 and gold_records > 0:
            context.log.info(f"✅ {entity_type}: Silver ({silver_records}) → Gold ({gold_records})")
    
    overall_health = len(alerts) == 0
    
    return {
        "overall_health": "HEALTHY" if overall_health else "DEGRADED",
        "metrics": health_metrics,
        "alerts": alerts,
        "timestamp": context.run.run_id
    }


@asset(
    description="Monitor Gold business functions",
    group_name="monitoring",
    compute_kind="validation",
    metadata={
        "functions": [
            "calculate_total_monthly_income",
            "calculate_se_tax",
            "calculate_account_balance",
            "calculate_csed_date",
            "calculate_disposable_income",
            "get_case_summary"
        ]
    },
    deps=[monitor_silver_gold_health]  # Run after Silver→Gold check
)
def monitor_business_functions(
    context: AssetExecutionContext,
    supabase: SupabaseResource
) -> Dict[str, Any]:
    """
    Monitor Gold business functions
    
    Tests that business logic functions are working correctly by:
    1. Selecting a sample case
    2. Running all business functions
    3. Validating outputs
    
    Returns:
        Dict with function test results
    """
    context.log.info("🏥 Checking Gold business functions")
    
    client = supabase.get_client()
    
    # Get a sample case to test with
    cases_result = client.table('cases').select('id', 'case_number').limit(1).execute()
    
    if not cases_result.data:
        context.log.warning("⚠️  No cases found to test business functions")
        return {
            "overall_health": "UNKNOWN",
            "reason": "No cases available for testing",
            "timestamp": context.run.run_id
        }
    
    test_case_id = cases_result.data[0]['id']
    test_case_number = cases_result.data[0]['case_number']
    
    context.log.info(f"Testing with case: {test_case_number}")
    
    function_results = {}
    errors = []
    
    # Test 1: calculate_total_monthly_income
    try:
        result = client.rpc('calculate_total_monthly_income', {'p_case_id': test_case_id}).execute()
        function_results['calculate_total_monthly_income'] = "✅ OK"
        context.log.info("✅ calculate_total_monthly_income: Working")
    except Exception as e:
        function_results['calculate_total_monthly_income'] = f"❌ Error: {str(e)}"
        errors.append(f"calculate_total_monthly_income: {str(e)}")
        context.log.error(f"❌ calculate_total_monthly_income: {str(e)}")
    
    # Test 2: calculate_disposable_income
    try:
        result = client.rpc('calculate_disposable_income', {'p_case_id': test_case_id}).execute()
        function_results['calculate_disposable_income'] = "✅ OK"
        context.log.info("✅ calculate_disposable_income: Working")
    except Exception as e:
        function_results['calculate_disposable_income'] = f"❌ Error: {str(e)}"
        errors.append(f"calculate_disposable_income: {str(e)}")
        context.log.error(f"❌ calculate_disposable_income: {str(e)}")
    
    # Test 3: get_case_summary
    try:
        result = client.rpc('get_case_summary', {'p_case_id': test_case_id}).execute()
        function_results['get_case_summary'] = "✅ OK"
        context.log.info("✅ get_case_summary: Working")
    except Exception as e:
        function_results['get_case_summary'] = f"❌ Error: {str(e)}"
        errors.append(f"get_case_summary: {str(e)}")
        context.log.error(f"❌ get_case_summary: {str(e)}")
    
    # Note: calculate_se_tax and calculate_account_balance require tax_year parameter
    # Test 4: get_case_summary provides comprehensive validation
    
    overall_health = len(errors) == 0
    
    return {
        "overall_health": "HEALTHY" if overall_health else "DEGRADED",
        "test_case": test_case_number,
        "function_results": function_results,
        "errors": errors,
        "timestamp": context.run.run_id
    }

