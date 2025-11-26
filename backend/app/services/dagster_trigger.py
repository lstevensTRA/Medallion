"""
Dagster Trigger Service

Service to trigger Dagster pipeline jobs from FastAPI.
Bridges the FastAPI backend with the Dagster orchestration layer.
"""

import os
import subprocess
import asyncio
from typing import Dict, Any, Optional
from pathlib import Path
import logging

logger = logging.getLogger(__name__)


class DagsterTriggerService:
    """
    Service for triggering Dagster pipeline jobs from FastAPI
    
    This allows FastAPI to initiate data ingestion jobs that are
    orchestrated by Dagster, providing better observability and
    retry logic.
    """
    
    def __init__(self):
        """Initialize the Dagster trigger service"""
        # Path: backend/app/services/dagster_trigger.py → /Users/lindseystevens/Medallion/
        self.project_root = Path(__file__).parent.parent.parent.parent
        self.trigger_script = self.project_root / "trigger_case_ingestion.py"
        self.dagster_home = self.project_root / "dagster_home"
        
        # Ensure DAGSTER_HOME exists
        self.dagster_home.mkdir(exist_ok=True)
    
    async def trigger_case_extraction(
        self,
        case_id: str,
        case_number: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Trigger Dagster to extract data for a specific case
        
        This runs the Bronze ingestion pipeline asynchronously via Dagster.
        
        Args:
            case_id: Case ID (e.g., "1295022")
            case_number: Optional case number for logging (e.g., "CASE-1295022")
        
        Returns:
            Dict with:
            - status: "triggered", "running", or "failed"
            - case_id: The case ID
            - case_number: The case number
            - message: Status message
            - dagster_ui: URL to view progress in Dagster UI
        
        Example:
            service = DagsterTriggerService()
            result = await service.trigger_case_extraction("1295022")
            # Returns: {
            #   "status": "triggered",
            #   "case_id": "1295022",
            #   "case_number": "CASE-1295022",
            #   "message": "Data extraction started",
            #   "dagster_ui": "http://localhost:3000/runs"
            # }
        """
        if not case_number:
            case_number = f"CASE-{case_id}"
        
        logger.info(f"🚀 Triggering Dagster extraction for case {case_number} (ID: {case_id})")
        
        try:
            # Set up environment
            env = os.environ.copy()
            env["DAGSTER_HOME"] = str(self.dagster_home)
            
            # Run trigger script in background
            # Using subprocess instead of direct Python call to isolate Dagster's dependencies
            process = await asyncio.create_subprocess_exec(
                "python3",
                str(self.trigger_script),
                case_id,
                case_number,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env,
                cwd=str(self.project_root)
            )
            
            # Don't wait for completion - let it run in background
            # FastAPI will return immediately
            logger.info(f"✅ Dagster job triggered for case {case_number} (PID: {process.pid})")
            
            return {
                "status": "triggered",
                "case_id": case_id,
                "case_number": case_number,
                "message": f"Data extraction started for case {case_number}. Check Dagster UI for progress.",
                "dagster_ui": "http://localhost:3000/runs",
                "process_id": process.pid
            }
            
        except FileNotFoundError:
            logger.error(f"❌ Trigger script not found: {self.trigger_script}")
            return {
                "status": "failed",
                "case_id": case_id,
                "case_number": case_number,
                "message": "Dagster trigger script not found. Please check installation.",
                "error": "FileNotFoundError"
            }
        
        except Exception as e:
            logger.error(f"❌ Failed to trigger Dagster job: {str(e)}")
            return {
                "status": "failed",
                "case_id": case_id,
                "case_number": case_number,
                "message": f"Failed to trigger extraction: {str(e)}",
                "error": str(e)
            }
    
    async def trigger_case_extraction_sync(
        self,
        case_id: str,
        case_number: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Trigger Dagster extraction and WAIT for completion
        
        Use this for synchronous operations where you need to know
        when the extraction is complete.
        
        Args:
            case_id: Case ID
            case_number: Optional case number
        
        Returns:
            Dict with status and results
        
        Warning:
            This will block the FastAPI endpoint until completion.
            Use trigger_case_extraction() for async operations.
        """
        if not case_number:
            case_number = f"CASE-{case_id}"
        
        logger.info(f"🚀 Triggering SYNCHRONOUS Dagster extraction for case {case_number}")
        
        try:
            env = os.environ.copy()
            env["DAGSTER_HOME"] = str(self.dagster_home)
            
            # Run and wait for completion
            process = await asyncio.create_subprocess_exec(
                "python3",
                str(self.trigger_script),
                case_id,
                case_number,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env,
                cwd=str(self.project_root)
            )
            
            stdout, stderr = await process.communicate()
            
            if process.returncode == 0:
                logger.info(f"✅ Dagster extraction completed successfully for case {case_number}")
                return {
                    "status": "completed",
                    "case_id": case_id,
                    "case_number": case_number,
                    "message": f"Data extraction completed for case {case_number}",
                    "output": stdout.decode('utf-8')
                }
            else:
                logger.error(f"❌ Dagster extraction failed for case {case_number}")
                return {
                    "status": "failed",
                    "case_id": case_id,
                    "case_number": case_number,
                    "message": f"Data extraction failed for case {case_number}",
                    "error": stderr.decode('utf-8')
                }
        
        except Exception as e:
            logger.error(f"❌ Failed to run Dagster extraction: {str(e)}")
            return {
                "status": "failed",
                "case_id": case_id,
                "case_number": case_number,
                "message": f"Failed to run extraction: {str(e)}",
                "error": str(e)
            }
    
    def get_dagster_ui_url(self) -> str:
        """Get the URL for Dagster UI"""
        return "http://localhost:3000"
    
    def get_run_url(self, run_id: str) -> str:
        """Get URL for a specific Dagster run"""
        return f"http://localhost:3000/runs/{run_id}"


# Singleton instance
dagster_service = DagsterTriggerService()

