"""
PDF Storage Service

Handles downloading, storing, and retrieving PDF files in Supabase Storage.
Works with bronze_pdf_raw table to maintain metadata.
"""

import os
import hashlib
from typing import Optional, Dict, Any, BinaryIO
from datetime import datetime
from supabase import Client
import httpx
from pathlib import Path


class PDFStorageService:
    """Service for managing PDF storage in Supabase Storage"""
    
    def __init__(self, supabase_client: Client):
        """
        Initialize PDF Storage Service
        
        Args:
            supabase_client: Initialized Supabase client
        """
        self.client = supabase_client
        self.bucket_name = "case-pdfs"
    
    def calculate_file_hash(self, file_content: bytes) -> str:
        """
        Calculate SHA-256 hash of file content
        
        Args:
            file_content: Binary content of file
        
        Returns:
            Hex string of SHA-256 hash
        """
        return hashlib.sha256(file_content).hexdigest()
    
    def generate_storage_path(
        self,
        case_id: str,
        document_type: str,
        file_name: str,
        tax_year: Optional[str] = None
    ) -> str:
        """
        Generate standardized storage path for PDF
        
        Format: {case_id}/{document_type}/{tax_year}/{filename}
        Or: {case_id}/{document_type}/{filename}
        
        Args:
            case_id: Case identifier
            document_type: Type of document (AT, WI, TRT, Interview)
            file_name: Original filename
            tax_year: Optional tax year for organization
        
        Returns:
            Storage path string
        """
        # Sanitize inputs
        case_id = str(case_id).replace('/', '_')
        document_type = document_type.upper()
        file_name = Path(file_name).name  # Remove any path components
        
        if tax_year:
            return f"{case_id}/{document_type}/{tax_year}/{file_name}"
        else:
            return f"{case_id}/{document_type}/{file_name}"
    
    def check_duplicate(self, file_hash: str) -> Optional[Dict[str, Any]]:
        """
        Check if a PDF with this hash already exists
        
        Args:
            file_hash: SHA-256 hash of file content
        
        Returns:
            Existing bronze_pdf_raw record if found, None otherwise
        """
        result = self.client.table('bronze_pdf_raw') \
            .select('*') \
            .eq('file_hash', file_hash) \
            .limit(1) \
            .execute()
        
        return result.data[0] if result.data else None
    
    def upload_pdf(
        self,
        file_content: bytes,
        case_id: str,
        document_type: str,
        file_name: str,
        source_system: str = 'casehelper',
        source_url: Optional[str] = None,
        tax_year: Optional[str] = None,
        form_type: Optional[str] = None,
        download_metadata: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Upload PDF to Supabase Storage and create metadata record
        
        Args:
            file_content: Binary content of PDF file
            case_id: Case identifier
            document_type: Type (AT, WI, TRT, Interview, Other)
            file_name: Original filename
            source_system: Where PDF came from
            source_url: Original URL where PDF was downloaded
            tax_year: Optional tax year
            form_type: Optional form type (for WI documents)
            download_metadata: Additional metadata
        
        Returns:
            Dict with bronze_pdf_id, storage_path, and other metadata
        
        Raises:
            Exception: If upload fails
        """
        # Calculate file hash
        file_hash = self.calculate_file_hash(file_content)
        
        # Check for duplicates
        existing = self.check_duplicate(file_hash)
        if existing:
            print(f"⚠️  Duplicate PDF detected (hash: {file_hash[:8]}...). Using existing record.")
            return {
                "bronze_pdf_id": existing['bronze_pdf_id'],
                "storage_path": existing['storage_path'],
                "is_duplicate": True,
                "existing_record": existing
            }
        
        # Generate storage path
        storage_path = self.generate_storage_path(
            case_id=case_id,
            document_type=document_type,
            file_name=file_name,
            tax_year=tax_year
        )
        
        # Upload to Supabase Storage
        try:
            # Upload file
            upload_response = self.client.storage.from_(self.bucket_name).upload(
                path=storage_path,
                file=file_content,
                file_options={"content-type": "application/pdf"}
            )
            
            print(f"✅ Uploaded PDF to {storage_path}")
            
        except Exception as e:
            # If file exists, we can still create metadata record
            if "already exists" in str(e).lower():
                print(f"⚠️  File already exists at {storage_path}, creating metadata record")
            else:
                raise Exception(f"Failed to upload PDF: {str(e)}")
        
        # Create metadata record in bronze_pdf_raw
        metadata_record = {
            'case_id': str(case_id),
            'document_type': document_type.upper(),
            'tax_year': tax_year,
            'form_type': form_type,
            'storage_path': storage_path,
            'storage_bucket': self.bucket_name,
            'file_size_bytes': len(file_content),
            'file_name': file_name,
            'mime_type': 'application/pdf',
            'source_system': source_system,
            'source_url': source_url,
            'download_metadata': download_metadata or {},
            'processing_status': 'stored',
            'file_hash': file_hash,
            'inserted_at': datetime.utcnow().isoformat()
        }
        
        result = self.client.table('bronze_pdf_raw').insert(metadata_record).execute()
        
        if not result.data:
            raise Exception("Failed to create bronze_pdf_raw metadata record")
        
        return {
            "bronze_pdf_id": result.data[0]['bronze_pdf_id'],
            "storage_path": storage_path,
            "file_hash": file_hash,
            "file_size_bytes": len(file_content),
            "is_duplicate": False
        }
    
    def download_pdf_from_url(
        self,
        url: str,
        case_id: str,
        document_type: str,
        file_name: Optional[str] = None,
        headers: Optional[Dict[str, str]] = None,
        timeout: int = 120
    ) -> Dict[str, Any]:
        """
        Download PDF from URL and store it
        
        Args:
            url: URL to download PDF from
            case_id: Case identifier
            document_type: Type of document
            file_name: Optional filename (will be generated if not provided)
            headers: Optional HTTP headers for download
            timeout: Download timeout in seconds
        
        Returns:
            Dict with bronze_pdf_id and storage metadata
        
        Raises:
            Exception: If download or upload fails
        """
        # Generate filename if not provided
        if not file_name:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            file_name = f"{document_type.lower()}_{case_id}_{timestamp}.pdf"
        
        # Download PDF
        print(f"📥 Downloading PDF from {url}")
        
        with httpx.Client(timeout=timeout) as client:
            response = client.get(url, headers=headers or {}, follow_redirects=True)
            response.raise_for_status()
            
            # Verify it's actually a PDF
            content_type = response.headers.get('content-type', '')
            if 'pdf' not in content_type.lower():
                print(f"⚠️  Warning: Content-Type is '{content_type}', not PDF. Proceeding anyway.")
            
            file_content = response.content
        
        print(f"✅ Downloaded {len(file_content)} bytes")
        
        # Store the PDF
        download_metadata = {
            'download_url': url,
            'download_timestamp': datetime.utcnow().isoformat(),
            'content_type': content_type,
            'content_length': len(file_content),
            'response_headers': dict(response.headers)
        }
        
        return self.upload_pdf(
            file_content=file_content,
            case_id=case_id,
            document_type=document_type,
            file_name=file_name,
            source_system='casehelper',
            source_url=url,
            download_metadata=download_metadata
        )
    
    def get_pdf_content(self, bronze_pdf_id: str) -> bytes:
        """
        Retrieve PDF content from storage
        
        Args:
            bronze_pdf_id: UUID of bronze_pdf_raw record
        
        Returns:
            Binary content of PDF
        
        Raises:
            Exception: If retrieval fails
        """
        # Get storage path from metadata
        result = self.client.table('bronze_pdf_raw') \
            .select('storage_path') \
            .eq('bronze_pdf_id', bronze_pdf_id) \
            .single() \
            .execute()
        
        if not result.data:
            raise Exception(f"No PDF record found for bronze_pdf_id: {bronze_pdf_id}")
        
        storage_path = result.data['storage_path']
        
        # Download from storage
        file_content = self.client.storage.from_(self.bucket_name).download(storage_path)
        
        return file_content
    
    def get_pdf_signed_url(self, bronze_pdf_id: str, expires_in: int = 3600) -> str:
        """
        Generate signed URL for temporary PDF access
        
        Args:
            bronze_pdf_id: UUID of bronze_pdf_raw record
            expires_in: Expiration time in seconds (default 1 hour)
        
        Returns:
            Signed URL string
        
        Raises:
            Exception: If generation fails
        """
        # Get storage path from metadata
        result = self.client.table('bronze_pdf_raw') \
            .select('storage_path') \
            .eq('bronze_pdf_id', bronze_pdf_id) \
            .single() \
            .execute()
        
        if not result.data:
            raise Exception(f"No PDF record found for bronze_pdf_id: {bronze_pdf_id}")
        
        storage_path = result.data['storage_path']
        
        # Generate signed URL
        signed_url = self.client.storage.from_(self.bucket_name).create_signed_url(
            path=storage_path,
            expires_in=expires_in
        )
        
        return signed_url['signedURL']
    
    def link_pdf_to_parsed_data(self, bronze_pdf_id: str, parsed_bronze_id: str) -> None:
        """
        Link a stored PDF to its parsed data record
        
        Args:
            bronze_pdf_id: UUID of bronze_pdf_raw record
            parsed_bronze_id: UUID of bronze_*_raw parsed data record
        """
        self.client.table('bronze_pdf_raw').update({
            'parsed_bronze_id': parsed_bronze_id,
            'processing_status': 'parsed',
            'parsed_at': datetime.utcnow().isoformat()
        }).eq('bronze_pdf_id', bronze_pdf_id).execute()
        
        print(f"✅ Linked PDF {bronze_pdf_id} to parsed data {parsed_bronze_id}")
    
    def get_case_pdfs(self, case_id: str) -> list[Dict[str, Any]]:
        """
        Get all PDFs for a case
        
        Args:
            case_id: Case identifier
        
        Returns:
            List of PDF metadata records
        """
        result = self.client.table('bronze_pdf_raw') \
            .select('*') \
            .eq('case_id', str(case_id)) \
            .order('inserted_at', desc=True) \
            .execute()
        
        return result.data

