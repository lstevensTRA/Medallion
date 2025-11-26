"""
PDF Storage Resource

Dagster resource wrapper for PDFStorageService.
Provides PDF download and storage capabilities to Dagster assets.
"""

import os
from dagster import ConfigurableResource
from pydantic import Field
import sys
from pathlib import Path

# Add backend to path so we can import the service
backend_path = Path(__file__).parent.parent.parent / "backend"
sys.path.insert(0, str(backend_path))

from app.services.pdf_storage import PDFStorageService


class PDFStorageResource(ConfigurableResource):
    """
    Dagster resource for PDF storage operations
    
    Wraps the PDFStorageService to provide PDF download and storage
    capabilities to Dagster assets.
    
    Configuration is loaded from environment variables via SupabaseResource.
    """
    
    def get_service(self, supabase_client) -> PDFStorageService:
        """
        Get an initialized PDFStorageService
        
        Args:
            supabase_client: Supabase client from SupabaseResource
        
        Returns:
            Initialized PDFStorageService instance
        """
        return PDFStorageService(supabase_client)


# Create a simple instance for use in Dagster
pdf_storage_resource = PDFStorageResource()

