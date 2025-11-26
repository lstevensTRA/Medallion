"""
Supabase Resource for Dagster

Wraps the existing Supabase client from backend/app/database.py
"""

import os
from pathlib import Path
from dotenv import load_dotenv
from dagster import ConfigurableResource
from supabase import create_client, Client
from pydantic import Field

# Load environment variables from .env file
env_path = Path(__file__).parent.parent.parent / ".env"
load_dotenv(env_path)


class SupabaseResource(ConfigurableResource):
    """
    Dagster resource for Supabase database operations
    
    This wraps the existing get_supabase_client() pattern but makes it
    configurable via Dagster's environment system.
    
    Usage:
        @asset
        def my_asset(supabase: SupabaseResource):
            client = supabase.get_client()
            result = client.table('cases').select('*').execute()
    """
    
    supabase_url: str = Field(
        description="Supabase project URL",
        default_factory=lambda: os.getenv("SUPABASE_URL", "https://your-project.supabase.co")
    )
    
    supabase_key: str = Field(
        description="Supabase service role key (keep secret!)",
        default_factory=lambda: os.getenv("SUPABASE_SERVICE_ROLE_KEY", "your-service-role-key")
    )
    
    def get_client(self) -> Client:
        """
        Get Supabase client instance
        
        Returns:
            Authenticated Supabase client
        
        Example:
            client = supabase.get_client()
            cases = client.table('cases').select('*').execute()
        """
        return create_client(self.supabase_url, self.supabase_key)
    
    def health_check(self) -> bool:
        """
        Check if Supabase connection is healthy
        
        Returns:
            True if connection works, False otherwise
        """
        try:
            client = self.get_client()
            # Try a simple query
            result = client.table('cases').select('id').limit(1).execute()
            return True
        except Exception as e:
            print(f"Supabase health check failed: {e}")
            return False

