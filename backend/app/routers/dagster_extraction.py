"""
Dagster Extraction Router

FastAPI endpoints for triggering Dagster-orchestrated data extraction.
This is the new recommended way to extract case data using the medallion architecture.
"""

from fastapi import APIRouter, HTTPException, BackgroundTasks, Depends
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any
from datetime import datetime
import logging

from app.services.dagster_trigger import dagster_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/dagster", tags=["dagster"])


# Request/Response Models
class ExtractionRequest(BaseModel):
    """Request to trigger data extraction"""
    case_id: str = Field(..., description="Case ID to extract data for")
    case_number: Optional[str] = Field(None, description="Optional case number for tracking")
    async_mode: bool = Field(True, description="Run asynchronously (recommended) or wait for completion")


class ExtractionResponse(BaseModel):
    """Response from extraction trigger"""
    status: str = Field(..., description="Status: triggered, running, completed, or failed")
    case_id: str
    case_number: str
    message: str
    dagster_ui: Optional[str] = Field(None, description="URL to view progress in Dagster UI")
    process_id: Optional[int] = Field(None, description="Process ID of Dagster job")
    timestamp: str = Field(default_factory=lambda: datetime.now().isoformat())


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    dagster_ui: str
    message: str


# Endpoints
@router.post("/extract", response_model=ExtractionResponse)
async def trigger_extraction(request: ExtractionRequest):
    """
    Trigger Dagster to extract data for a case
    
    This endpoint triggers the Bronze ingestion pipeline which:
    1. Calls TiParser API (AT, WI, TRT data)
    2. Calls CaseHelper API (Interview data)
    3. Stores raw data in Bronze layer
    4. SQL triggers automatically populate Silver layer
    5. SQL triggers automatically populate Gold layer
    
    **Async Mode (Recommended):**
    - Returns immediately with "triggered" status
    - Job runs in background
    - Check Dagster UI for progress
    
    **Sync Mode (Blocks until complete):**
    - Waits for job to finish
    - Returns "completed" or "failed" status
    - May timeout on large cases
    
    Example Request:
    ```json
    {
        "case_id": "1295022",
        "case_number": "CASE-1295022",
        "async_mode": true
    }
    ```
    
    Example Response:
    ```json
    {
        "status": "triggered",
        "case_id": "1295022",
        "case_number": "CASE-1295022",
        "message": "Data extraction started...",
        "dagster_ui": "http://localhost:3000/runs",
        "process_id": 12345,
        "timestamp": "2025-11-24T10:00:00"
    }
    ```
    """
    logger.info(f"📨 Extraction request received for case {request.case_id}")
    
    try:
        if request.async_mode:
            # Async mode - return immediately
            result = await dagster_service.trigger_case_extraction(
                case_id=request.case_id,
                case_number=request.case_number
            )
        else:
            # Sync mode - wait for completion
            result = await dagster_service.trigger_case_extraction_sync(
                case_id=request.case_id,
                case_number=request.case_number
            )
        
        return ExtractionResponse(**result)
    
    except Exception as e:
        logger.error(f"❌ Failed to trigger extraction: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to trigger extraction: {str(e)}"
        )


@router.post("/cases/{case_id}/extract", response_model=ExtractionResponse)
async def trigger_extraction_by_id(case_id: str, async_mode: bool = True):
    """
    Trigger extraction for a case by ID (simplified endpoint)
    
    Convenience endpoint that takes case_id as path parameter.
    
    Example:
    ```
    POST /api/dagster/cases/1295022/extract
    ```
    
    Query Parameters:
    - async_mode: Run asynchronously (default: true)
    """
    request = ExtractionRequest(
        case_id=case_id,
        case_number=f"CASE-{case_id}",
        async_mode=async_mode
    )
    return await trigger_extraction(request)


@router.get("/health", response_model=HealthResponse)
async def dagster_health():
    """
    Check if Dagster is running and accessible
    
    Returns:
    ```json
    {
        "status": "healthy",
        "dagster_ui": "http://localhost:3000",
        "message": "Dagster is running"
    }
    ```
    """
    try:
        import httpx
        
        # Check if Dagster UI is responding
        async with httpx.AsyncClient(timeout=2.0) as client:
            response = await client.get("http://localhost:3000")
            
            if response.status_code == 200:
                return HealthResponse(
                    status="healthy",
                    dagster_ui=dagster_service.get_dagster_ui_url(),
                    message="Dagster is running and accessible"
                )
            else:
                return HealthResponse(
                    status="unhealthy",
                    dagster_ui=dagster_service.get_dagster_ui_url(),
                    message=f"Dagster UI returned status {response.status_code}"
                )
    
    except Exception as e:
        return HealthResponse(
            status="unreachable",
            dagster_ui=dagster_service.get_dagster_ui_url(),
            message=f"Cannot reach Dagster: {str(e)}"
        )


@router.get("/ui")
async def dagster_ui_redirect():
    """
    Redirect to Dagster UI
    
    Opens the Dagster monitoring dashboard in a new tab.
    """
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url=dagster_service.get_dagster_ui_url())


@router.get("/status/{case_id}")
async def get_extraction_status(case_id: str) -> Dict[str, Any]:
    """
    Get extraction status for a case
    
    Checks the Bronze/Silver/Gold tables to see if data exists for this case.
    
    Returns:
    ```json
    {
        "case_id": "1295022",
        "bronze": {"at": true, "wi": true, "trt": true, "interview": true},
        "silver": {"tax_years": 5, "income_documents": 12},
        "gold": {"employment": 2, "household": 1},
        "status": "complete"
    }
    ```
    """
    try:
        from app.database import get_supabase_client
        
        client = get_supabase_client()
        
        # Check Bronze layer
        bronze_at = client.table('bronze_at_raw').select('bronze_id', count='exact').eq('case_id', case_id).execute()
        bronze_wi = client.table('bronze_wi_raw').select('bronze_id', count='exact').eq('case_id', case_id).execute()
        bronze_trt = client.table('bronze_trt_raw').select('bronze_id', count='exact').eq('case_id', case_id).execute()
        bronze_interview = client.table('bronze_interview_raw').select('bronze_id', count='exact').eq('case_id', case_id).execute()
        
        # Check Silver layer
        silver_tax_years = client.table('tax_years').select('id', count='exact').eq('case_id', case_id).execute()
        silver_income = client.table('income_documents').select('id', count='exact').eq('case_id', case_id).execute()
        
        # Check Gold layer
        gold_employment = client.table('employment_information').select('id', count='exact').eq('case_id', case_id).execute()
        gold_household = client.table('household_information').select('id', count='exact').eq('case_id', case_id).execute()
        
        bronze_count = (bronze_at.count or 0) + (bronze_wi.count or 0) + (bronze_trt.count or 0) + (bronze_interview.count or 0)
        silver_count = (silver_tax_years.count or 0) + (silver_income.count or 0)
        gold_count = (gold_employment.count or 0) + (gold_household.count or 0)
        
        # Determine status
        if bronze_count == 0:
            status = "not_started"
        elif silver_count == 0:
            status = "bronze_only"
        elif gold_count == 0:
            status = "silver_only"
        else:
            status = "complete"
        
        return {
            "case_id": case_id,
            "bronze": {
                "at": (bronze_at.count or 0) > 0,
                "wi": (bronze_wi.count or 0) > 0,
                "trt": (bronze_trt.count or 0) > 0,
                "interview": (bronze_interview.count or 0) > 0,
                "total_records": bronze_count
            },
            "silver": {
                "tax_years": silver_tax_years.count or 0,
                "income_documents": silver_income.count or 0,
                "total_records": silver_count
            },
            "gold": {
                "employment": gold_employment.count or 0,
                "household": gold_household.count or 0,
                "total_records": gold_count
            },
            "status": status,
            "message": {
                "not_started": "No data found. Trigger extraction to begin.",
                "bronze_only": "Raw data ingested. Triggers are processing...",
                "silver_only": "Typed data ready. Gold layer processing...",
                "complete": "Data fully processed and ready to use."
            }[status]
        }
    
    except Exception as e:
        logger.error(f"❌ Failed to get status: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get extraction status: {str(e)}"
        )

