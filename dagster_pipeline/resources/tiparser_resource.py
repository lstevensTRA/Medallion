"""
TiParser API Resource for Dagster

Wraps the existing TiParser client logic from backend/app/services/transcript_pipeline.py
"""

import os
from pathlib import Path
from dotenv import load_dotenv
from dagster import ConfigurableResource
from pydantic import Field
import httpx
from typing import Dict, Any, Optional

# Load environment variables from .env file
env_path = Path(__file__).parent.parent.parent / ".env"
load_dotenv(env_path)


class TiParserResource(ConfigurableResource):
    """
    Dagster resource for TiParser API operations
    
    This wraps the existing parse_pdf_with_tiparser() pattern from
    backend/app/services/transcript_pipeline.py
    
    Usage:
        @asset
        def my_asset(tiparser: TiParserResource):
            at_data = tiparser.get_at_analysis('CASE-001')
            wi_data = tiparser.get_wi_analysis('CASE-001')
    """
    
    tiparser_url: str = Field(
        description="TiParser API base URL",
        default_factory=lambda: os.getenv("TIPARSER_URL", "https://tiparser.onrender.com")
    )
    
    tiparser_api_key: str = Field(
        description="TiParser API key (keep secret!)",
        default_factory=lambda: os.getenv("TIPARSER_API_KEY", "your-api-key")
    )
    
    timeout: int = Field(
        description="Request timeout in seconds",
        default=120
    )
    
    def _make_request(
        self, 
        endpoint: str, 
        case_id: str, 
        method: str = "GET"
    ) -> Dict[str, Any]:
        """
        Make authenticated request to TiParser API
        
        Tries GET first, falls back to POST if 405 Method Not Allowed.
        
        Args:
            endpoint: API endpoint (e.g., 'analysis/at')
            case_id: Case identifier
            method: HTTP method (GET or POST) - GET is tried first
        
        Returns:
            JSON response from API
        
        Raises:
            httpx.HTTPError: If request fails
        """
        url = f"{self.tiparser_url}/{endpoint}/{case_id}"
        headers = {
            "x-api-key": self.tiparser_api_key,  # Use x-api-key header
            "Content-Type": "application/json"
        }
        
        with httpx.Client(timeout=self.timeout) as client:
            # Try GET first (TiParser analysis endpoints use GET)
            try:
                response = client.get(url, headers=headers)
                response.raise_for_status()
                return response.json()
            except httpx.HTTPStatusError as e:
                # If GET returns 405, try POST
                if e.response.status_code == 405:
                    response = client.post(url, headers=headers, json={})
                    response.raise_for_status()
                    return response.json()
                elif e.response.status_code == 403:
                    # Log the actual error message for 403
                    error_detail = e.response.text if hasattr(e.response, 'text') else 'No details'
                    raise Exception(f"TiParser API authentication failed (403): {error_detail}. Check TIPARSER_API_KEY environment variable.")
                else:
                    # Re-raise other HTTP errors
                    raise
    
    def get_at_analysis(self, case_id: str) -> Dict[str, Any]:
        """
        Get Account Transcript analysis from TiParser
        
        Args:
            case_id: Case identifier
        
        Returns:
            JSON response with AT data
        
        Example:
            at_data = tiparser.get_at_analysis('1295022')
            # Returns: {"records": [...], "metadata": {...}}
        """
        return self._make_request("analysis/at", case_id, method="GET")
    
    def get_wi_analysis(self, case_id: str) -> Dict[str, Any]:
        """
        Get Wage & Income analysis from TiParser
        
        Args:
            case_id: Case identifier
        
        Returns:
            JSON response with WI data
        
        Example:
            wi_data = tiparser.get_wi_analysis('1295022')
            # Returns: {"forms": [...], "metadata": {...}}
        """
        return self._make_request("analysis/wi", case_id, method="GET")
    
    def get_trt_analysis(self, case_id: str) -> Dict[str, Any]:
        """
        Get Tax Return Transcript analysis from TiParser
        
        Args:
            case_id: Case identifier
        
        Returns:
            JSON response with TRT data
        
        Example:
            trt_data = tiparser.get_trt_analysis('1295022')
            # Returns: {"records": [...], "metadata": {...}}
        """
        return self._make_request("analysis/trt", case_id, method="GET")
    
    def get_interview(self, case_id: str) -> Dict[str, Any]:
        """
        Get Interview data from TiParser
        
        Args:
            case_id: Case identifier
        
        Returns:
            JSON response with interview data
        
        Example:
            interview_data = tiparser.get_interview('1295022')
            # Returns: {"employment": {...}, "expenses": {...}, ...}
        """
        # Interview endpoint uses /api/cases/{id}/interview
        url = f"{self.tiparser_url}/api/cases/{case_id}/interview"
        headers = {
            "x-api-key": self.tiparser_api_key,
            "Content-Type": "application/json"
        }
        
        with httpx.Client(timeout=self.timeout) as client:
            response = client.get(url, headers=headers)
            response.raise_for_status()
            return response.json()
    
    def health_check(self) -> bool:
        """
        Check if TiParser API is healthy
        
        Returns:
            True if API is reachable, False otherwise
        """
        try:
            url = f"{self.tiparser_url}/health"
            headers = {"Authorization": f"Bearer {self.tiparser_api_key}"}
            
            with httpx.Client(timeout=10) as client:
                response = client.get(url, headers=headers)
                return response.status_code == 200
        except Exception as e:
            print(f"TiParser health check failed: {e}")
            return False

