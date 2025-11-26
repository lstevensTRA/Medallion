"""
CaseHelper API Resource for Dagster

Wraps the existing CaseHelper client logic from:
- backend/app/services/interview_fetcher.py
- backend/app/services/casehelper_auth.py
"""

import os
from dagster import ConfigurableResource
from pydantic import Field
import httpx
from typing import Dict, Any, Optional, List
import re


class TranscriptFile:
    """Represents a transcript PDF file with metadata"""
    def __init__(self, type: str, year: str, suffix: str, document_entry: Dict[str, Any]):
        self.type = type  # 'WI', 'AT', 'TRT'
        self.year = year
        self.suffix = suffix
        self.document_entry = document_entry
        self.file_name = document_entry.get("file_name", "")
        self.case_document_id = document_entry.get("case_document_id", "")
    
    def __repr__(self):
        return f"TranscriptFile(type={self.type}, year={self.year}, file={self.file_name})"


class CaseHelperResource(ConfigurableResource):
    """
    Dagster resource for CaseHelper API operations
    
    This wraps the existing InterviewFetcher and CaseHelperAuth patterns
    from backend/app/services/
    
    Usage:
        @asset
        def my_asset(casehelper: CaseHelperResource):
            interview_data = casehelper.get_interview('CASE-001')
    """
    
    casehelper_base_url: str = Field(
        description="CaseHelper API base URL",
        default_factory=lambda: os.getenv("CASEHELPER_API_URL", "https://your-casehelper-url.com")
    )
    
    casehelper_username: str = Field(
        description="CaseHelper username",
        default_factory=lambda: os.getenv("CASEHELPER_USERNAME", "your-username")
    )
    
    casehelper_password: str = Field(
        description="CaseHelper password (keep secret!)",
        default_factory=lambda: os.getenv("CASEHELPER_PASSWORD", "your-password")
    )
    
    casehelper_app_type: str = Field(
        description="CaseHelper application type",
        default_factory=lambda: os.getenv("CASEHELPER_APP_TYPE", "your-app-type")
    )
    
    api_key: Optional[str] = Field(
        description="Optional CaseHelper API key",
        default=None
    )
    
    timeout: int = Field(
        description="Request timeout in seconds",
        default=60
    )
    
    _cookies: Optional[Dict[str, str]] = None
    
    def _authenticate(self) -> Dict[str, str]:
        """
        Authenticate with CaseHelper and get cookies
        
        Returns:
            Authentication cookies
        
        Raises:
            httpx.HTTPError: If authentication fails
        """
        if self._cookies:
            return self._cookies
        
        url = f"{self.casehelper_base_url}/v2/auth/login"
        payload = {
            "username": self.casehelper_username,
            "password": self.casehelper_password,
            "appType": self.casehelper_app_type
        }
        
        with httpx.Client(timeout=self.timeout) as client:
            response = client.post(url, json=payload)
            response.raise_for_status()
            self._cookies = dict(response.cookies)
            return self._cookies
    
    def _get_auth_headers(self) -> Dict[str, str]:
        """
        Get authentication headers (cookies + optional API key)
        
        Returns:
            Headers dictionary
        """
        headers = {}
        
        if self.api_key:
            headers["X-API-Key"] = self.api_key
        
        return headers
    
    def get_interview(self, case_id: str) -> Dict[str, Any]:
        """
        Get interview data from CaseHelper
        
        Args:
            case_id: Case identifier
        
        Returns:
            JSON response with interview data
        
        Example:
            interview_data = casehelper.get_interview('CASE-001')
            # Returns: {
            #   "employment": {...},
            #   "household": {...},
            #   "assets": {...},
            #   "income": {...},
            #   "expenses": {...}
            # }
        """
        # Authenticate first
        cookies = self._authenticate()
        headers = self._get_auth_headers()
        
        url = f"{self.casehelper_base_url}/api/cases/{case_id}/interview"
        
        with httpx.Client(timeout=self.timeout) as client:
            response = client.get(url, cookies=cookies, headers=headers)
            response.raise_for_status()
            return response.json()
    
    def health_check(self) -> bool:
        """
        Check if CaseHelper API is healthy
        
        Returns:
            True if API is reachable and auth works, False otherwise
        """
        try:
            self._authenticate()
            return True
        except Exception as e:
            print(f"CaseHelper health check failed: {e}")
            return False
    
    def get_document_list(self, case_id: str) -> List[Dict[str, Any]]:
        """
        Get list of all documents/files for a case
        
        Args:
            case_id: Case identifier
        
        Returns:
            List of document entries with metadata
        
        Example:
            documents = casehelper.get_document_list('1295022')
            # Returns: [
            #   {"file_name": "AT 21.pdf", "case_document_id": "123", ...},
            #   {"file_name": "WI 20.pdf", "case_document_id": "456", ...}
            # ]
        """
        cookies = self._authenticate()
        headers = self._get_auth_headers()
        
        url = f"{self.casehelper_base_url}/v2/blobs/{case_id}/walk"
        
        with httpx.Client(timeout=self.timeout) as client:
            response = client.get(url, cookies=cookies, headers=headers)
            
            # Re-authenticate if cookies expired
            if response.status_code == 401:
                self._cookies = None
                cookies = self._authenticate()
                response = client.get(url, cookies=cookies, headers=headers)
            
            response.raise_for_status()
            data = response.json()
            return data.get("data", [])
    
    def filter_transcript_files(self, documents: List[Dict[str, Any]]) -> List[TranscriptFile]:
        """
        Filter documents to find transcript PDFs (AT, WI, TRT)
        
        Pattern matches: "WI 15.pdf", "AT 21 E.pdf", "TRT 2020.pdf"
        
        Args:
            documents: List of document entries from get_document_list
        
        Returns:
            List of TranscriptFile objects sorted by type and year
        
        Example:
            documents = casehelper.get_document_list('1295022')
            transcripts = casehelper.filter_transcript_files(documents)
            # Returns: [TranscriptFile(type='AT', year='2021', ...), ...]
        """
        transcript_pattern = re.compile(r'^(WI|AT|TRT)\s+(\d{2,4})(\s+(\w+))?\.pdf$', re.IGNORECASE)
        
        transcript_files = []
        
        for doc in documents:
            file_name = doc.get("file_name", "")
            match = transcript_pattern.match(file_name)
            
            if match:
                file_type = match.group(1).upper()
                year_str = match.group(2)
                suffix = match.group(4) if match.group(4) else ""
                
                # Convert 2-digit year to 4-digit
                if len(year_str) == 2:
                    year = f"20{year_str}"
                else:
                    year = year_str
                
                transcript_files.append(TranscriptFile(
                    type=file_type,
                    year=year,
                    suffix=suffix,
                    document_entry=doc
                ))
        
        # Sort by type (AT first, then WI, then TRT), then by year (descending)
        type_order = {"AT": 0, "WI": 1, "TRT": 2}
        transcript_files.sort(key=lambda x: (
            type_order.get(x.type, 99),
            -int(x.year)  # Negative for descending (newest first)
        ))
        
        return transcript_files
    
    def download_pdf(self, case_id: str, document_entry: Dict[str, Any]) -> bytes:
        """
        Download a single PDF file from CaseHelper blob storage
        
        Args:
            case_id: Case identifier
            document_entry: Document entry from get_document_list (must include full metadata)
        
        Returns:
            PDF content as bytes
        
        Raises:
            httpx.HTTPError: If download fails
        
        Example:
            documents = casehelper.get_document_list('1295022')
            pdf_bytes = casehelper.download_pdf('1295022', documents[0])
            # pdf_bytes contains the PDF file content
        """
        cookies = self._authenticate()
        headers = self._get_auth_headers()
        headers["accept"] = "application/pdf"
        
        url = f"{self.casehelper_base_url}/v2/blobs/{case_id}/download"
        
        # CaseHelper expects the document list wrapped in a response structure
        request_body = {
            "status": 200,
            "data": [document_entry]
        }
        
        with httpx.Client(timeout=self.timeout) as client:
            response = client.post(url, cookies=cookies, headers=headers, json=request_body)
            
            # Re-authenticate if cookies expired
            if response.status_code == 401:
                self._cookies = None
                cookies = self._authenticate()
                response = client.post(url, cookies=cookies, headers=headers, json=request_body)
            
            response.raise_for_status()
            return response.content

