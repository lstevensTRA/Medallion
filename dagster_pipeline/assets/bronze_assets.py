"""
Bronze Layer Assets

These assets call external APIs and store raw responses in Bronze tables.
SQL triggers automatically transform Bronze → Silver → Gold.

Dagster's role:
1. Call APIs (TiParser, CaseHelper)
2. Insert into Bronze tables
3. Monitor that triggers processed correctly
4. Provide observability and lineage
"""

from dagster import asset, AssetExecutionContext, Config, OpExecutionContext
from dagster_pipeline.resources.supabase_resource import SupabaseResource
from dagster_pipeline.resources.tiparser_resource import TiParserResource
from typing import Dict, Any
from datetime import datetime


class BronzeAssetConfig(Config):
    """Configuration for Bronze ingestion assets"""
    case_id: str
    case_number: str


@asset(
    description="Fetch AT (Account Transcript) data from TiParser and store in Bronze layer",
    group_name="bronze_ingestion",
    compute_kind="api",
    metadata={
        "api_endpoint": "TiParser /analysis/at",
        "bronze_table": "bronze_at_raw",
        "triggers": "insert_bronze_at → silver_tax_years, account_activity, csed_tolling_events"
    }
)
def bronze_at_data(
    context: AssetExecutionContext,
    config: BronzeAssetConfig,
    supabase: SupabaseResource,
    tiparser: TiParserResource
) -> Dict[str, Any]:
    """
    Fetch AT (Account Transcript) data from TiParser API and store in Bronze.
    
    This asset:
    1. Calls TiParser AT endpoint
    2. Inserts raw JSON into bronze_at_raw
    3. SQL trigger automatically populates Silver tables:
       - tax_years
       - account_activity
       - csed_tolling_events
    
    Args:
        context: Dagster execution context
        config: Asset configuration (case_id, case_number)
        supabase: Supabase resource for database operations
        tiparser: TiParser resource for API calls
    
    Returns:
        Dict with bronze_id, case_id, document_count, processing_status
    
    Example:
        config = {"case_id": "uuid-here", "case_number": "CASE-001"}
        result = materialize([bronze_at_data], run_config={"ops": {"bronze_at_data": {"config": config}}})
    """
    case_id = config.case_id
    case_number = config.case_number
    
    context.log.info(f"📥 Fetching AT data for case {case_number} (ID: {case_id})")
    
    try:
        # 1. Call TiParser API (uses numeric case_id, not case_number)
        start_time = datetime.now()
        at_response = tiparser.get_at_analysis(case_id)
        api_duration = (datetime.now() - start_time).total_seconds()
        
        context.log.info(f"✅ TiParser AT API call successful ({api_duration:.2f}s)")
        
        # 2. Store in Bronze (trigger fires automatically)
        client = supabase.get_client()
        result = client.table('bronze_at_raw').insert({
            'case_id': case_id,  # Using numeric case_id
            'raw_response': at_response
            # Note: api_source, api_endpoint, inserted_at handled by defaults/triggers
        }).execute()
        
        bronze_id = result.data[0]['bronze_id']
        context.log.info(f"💾 Stored in Bronze: {bronze_id}")
        
        # 3. Wait a moment for trigger to process (if triggers exist)
        import time
        time.sleep(1)
        
        # 4. Note: Triggers will process automatically if Silver tables exist
        # For now, we just store in Bronze - triggers will be added later
        context.log.info("✅ Bronze storage complete - triggers will process if Silver tables exist")
        
        # 5. Count Silver records created (if Silver tables exist)
        silver_count_query = """
        SELECT COUNT(*) as count
        FROM account_activity aa
        WHERE aa.source_bronze_id = %s
        """
        # Note: Supabase Python client doesn't support parameterized raw SQL easily
        # So we'll just report the bronze_id
        
        return {
            "bronze_id": bronze_id,
            "case_id": case_id,
            "case_number": case_number,
            "document_count": len(at_response.get('records', [])) if isinstance(at_response, dict) else 0,
            "processing_status": "stored",  # Data stored in Bronze, triggers will process
            "processing_error": None,  # Will track errors when Silver tables exist
            "api_duration_seconds": api_duration,
            "timestamp": datetime.now().isoformat()
        }
        
    except Exception as e:
        context.log.error(f"❌ Failed to process AT data: {str(e)}")
        raise


@asset(
    description="Fetch WI (Wage & Income) data from TiParser and store in Bronze layer",
    group_name="bronze_ingestion",
    compute_kind="api",
    metadata={
        "api_endpoint": "TiParser /analysis/wi",
        "bronze_table": "bronze_wi_raw",
        "triggers": "insert_bronze_wi → silver_income_documents"
    }
)
def bronze_wi_data(
    context: AssetExecutionContext,
    config: BronzeAssetConfig,
    supabase: SupabaseResource,
    tiparser: TiParserResource
) -> Dict[str, Any]:
    """
    Fetch WI (Wage & Income) data from TiParser API and store in Bronze.
    
    This asset:
    1. Calls TiParser WI endpoint
    2. Inserts raw JSON into bronze_wi_raw
    3. SQL trigger automatically populates Silver tables:
       - income_documents (with wi_type_rules enrichment)
    
    Returns:
        Dict with bronze_id, case_id, form_count, processing_status
    """
    case_id = config.case_id
    case_number = config.case_number
    
    context.log.info(f"📥 Fetching WI data for case {case_number} (ID: {case_id})")
    
    try:
        # 1. Call TiParser API (uses numeric case_id, not case_number)
        start_time = datetime.now()
        try:
            wi_response = tiparser.get_wi_analysis(case_id)
            api_duration = (datetime.now() - start_time).total_seconds()
            context.log.info(f"✅ TiParser WI API call successful ({api_duration:.2f}s)")
        except Exception as api_error:
            context.log.warning(f"⚠️  TiParser WI API call failed: {str(api_error)}")
            context.log.info("ℹ️  Continuing without WI data (optional)")
            # Return early without storing
            return {
                "bronze_id": None,
                "case_id": case_id,
                "case_number": case_number,
                "form_count": 0,
                "processing_status": "skipped",
                "processing_error": None,  # Will track errors when Silver tables exist
                "timestamp": datetime.now().isoformat()
            }
        
        # 2. Store in Bronze
        client = supabase.get_client()
        result = client.table('bronze_wi_raw').insert({
            'case_id': case_id,
            'raw_response': wi_response
            # Note: api_source, api_endpoint, inserted_at handled by defaults/triggers
        }).execute()
        
        bronze_id = result.data[0]['bronze_id']
        context.log.info(f"💾 Stored in Bronze: {bronze_id}")
        
        # 3. Check processing status
        import time
        time.sleep(1)
        
        # Note: Processing status tracking will be added when Silver tables exist
        context.log.info("✅ Bronze storage complete - triggers will process if Silver tables exist")
        
        return {
            "bronze_id": bronze_id,
            "case_id": case_id,
            "case_number": case_number,
            "form_count": len(wi_response.get('forms', [])) if isinstance(wi_response, dict) else 0,
            "processing_status": "stored",  # Data stored in Bronze, triggers will process
            "processing_error": None,
            "api_duration_seconds": api_duration,
            "timestamp": datetime.now().isoformat()
        }
        
    except Exception as e:
        context.log.error(f"❌ Failed to process WI data: {str(e)}")
        raise


@asset(
    description="Fetch TRT (Tax Return Transcript) data from TiParser and store in Bronze layer",
    group_name="bronze_ingestion",
    compute_kind="api",
    metadata={
        "api_endpoint": "TiParser /analysis/trt",
        "bronze_table": "bronze_trt_raw",
        "triggers": "insert_bronze_trt → silver_trt_records"
    }
)
def bronze_trt_data(
    context: AssetExecutionContext,
    config: BronzeAssetConfig,
    supabase: SupabaseResource,
    tiparser: TiParserResource
) -> Dict[str, Any]:
    """
    Fetch TRT (Tax Return Transcript) data from TiParser API and store in Bronze.
    
    This asset:
    1. Calls TiParser TRT endpoint
    2. Inserts raw JSON into bronze_trt_raw
    3. SQL trigger automatically populates Silver tables:
       - trt_records
    
    Returns:
        Dict with bronze_id, case_id, record_count, processing_status
    """
    case_id = config.case_id
    case_number = config.case_number
    
    context.log.info(f"📥 Fetching TRT data for case {case_number} (ID: {case_id})")
    
    try:
        # 1. Call TiParser API (uses numeric case_id, not case_number)
        start_time = datetime.now()
        try:
            trt_response = tiparser.get_trt_analysis(case_id)
            api_duration = (datetime.now() - start_time).total_seconds()
            context.log.info(f"✅ TiParser TRT API call successful ({api_duration:.2f}s)")
        except Exception as api_error:
            context.log.warning(f"⚠️  TiParser TRT API call failed: {str(api_error)}")
            context.log.info("ℹ️  Continuing without TRT data (optional - may not exist for this case)")
            # Return early without storing
            return {
                "bronze_id": None,
                "case_id": case_id,
                "case_number": case_number,
                "record_count": 0,
                "processing_status": "skipped",
                "timestamp": datetime.now().isoformat()
            }
        
        # 2. Store in Bronze
        client = supabase.get_client()
        result = client.table('bronze_trt_raw').insert({
            'case_id': case_id,
            'raw_response': trt_response
            # Note: api_source, api_endpoint, inserted_at handled by defaults/triggers
        }).execute()
        
        bronze_id = result.data[0]['bronze_id']
        context.log.info(f"💾 Stored in Bronze: {bronze_id}")
        
        # 3. Check processing status
        import time
        time.sleep(1)
        
        # Note: Processing status tracking will be added when Silver tables exist
        context.log.info("✅ Bronze storage complete - triggers will process if Silver tables exist")
        
        return {
            "bronze_id": bronze_id,
            "case_id": case_id,
            "case_number": case_number,
            "record_count": len(trt_response.get('records', [])) if isinstance(trt_response, dict) else 0,
            "processing_status": "stored",  # Data stored in Bronze, triggers will process
            "processing_error": None,  # Will track errors when Silver tables exist
            "api_duration_seconds": api_duration,
            "timestamp": datetime.now().isoformat()
        }
        
    except Exception as e:
        context.log.error(f"❌ Failed to process TRT data: {str(e)}")
        raise


@asset(
    description="Fetch Interview data from TiParser and store in Bronze layer",
    group_name="bronze_ingestion",
    compute_kind="api",
    metadata={
        "api_endpoint": "TiParser /api/cases/{id}/interview",
        "bronze_table": "bronze_interview_raw",
        "triggers": "insert_bronze_interview → silver_logiqs_raw_data → gold_employment/household"
    }
)
def bronze_interview_data(
    context: AssetExecutionContext,
    config: BronzeAssetConfig,
    supabase: SupabaseResource,
    tiparser: TiParserResource
) -> Dict[str, Any]:
    """
    Fetch Interview data from TiParser API and store in Bronze.
    
    This asset:
    1. Calls TiParser Interview endpoint (/api/cases/{id}/interview)
    2. Inserts raw JSON into bronze_interview_raw
    3. SQL trigger automatically populates Silver tables:
       - logiqs_raw_data
    4. SQL trigger then populates Gold tables:
       - employment_information
       - household_information
    
    Returns:
        Dict with bronze_id, case_id, processing_status
    """
    case_id = config.case_id
    case_number = config.case_number
    
    context.log.info(f"📥 Fetching Interview data for case {case_number} (ID: {case_id})")
    
    try:
        # 1. Call TiParser API (uses numeric case_id)
        start_time = datetime.now()
        try:
            interview_response = tiparser.get_interview(case_id)
            api_duration = (datetime.now() - start_time).total_seconds()
            context.log.info(f"✅ TiParser Interview API call successful ({api_duration:.2f}s)")
        except Exception as api_error:
            context.log.warning(f"⚠️  TiParser Interview API call failed: {str(api_error)}")
            context.log.info("ℹ️  Continuing without interview data (optional)")
            # Return early without storing
            return {
                "bronze_id": None,
                "case_id": case_id,
                "case_number": case_number,
                "sections_received": [],
                "processing_status": "skipped",
                "processing_error": f"API error: {str(api_error)}",
                "timestamp": datetime.now().isoformat()
            }
        
        # 2. Store in Bronze
        client = supabase.get_client()
        result = client.table('bronze_interview_raw').insert({
            'case_id': case_id,
            'raw_response': interview_response
            # Note: api_source, api_endpoint, inserted_at handled by defaults/triggers
        }).execute()
        
        bronze_id = result.data[0]['bronze_id']
        context.log.info(f"💾 Stored in Bronze: {bronze_id}")
        
        # 3. Check processing status
        import time
        time.sleep(1)
        
        # Note: Processing status tracking will be added when Silver tables exist
        context.log.info("✅ Bronze storage complete - triggers will process if Silver tables exist")
        
        return {
            "bronze_id": bronze_id,
            "case_id": case_id,
            "case_number": case_number,
            "sections_received": list(interview_response.keys()) if isinstance(interview_response, dict) else [],
            "processing_status": "stored",  # Data stored in Bronze, triggers will process
            "processing_error": None,  # Will track errors when Silver tables exist
            "api_duration_seconds": api_duration,
            "timestamp": datetime.now().isoformat()
        }
        
    except Exception as e:
        context.log.error(f"❌ Failed to process Interview data: {str(e)}")
        raise

