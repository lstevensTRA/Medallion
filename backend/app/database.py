"""
Database Module
Supabase client configuration and connection management.
"""

import os
from supabase import create_client, Client
from functools import lru_cache
import logging

logger = logging.getLogger(__name__)


@lru_cache()
def get_supabase_client() -> Client:
    """
    Get Supabase client instance (singleton pattern)
    
    Returns:
        Supabase Client configured with URL and service role key
    
    Raises:
        ValueError: If required environment variables are not set
    """
    supabase_url = os.getenv("SUPABASE_URL")
    supabase_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    
    if not supabase_url:
        raise ValueError("SUPABASE_URL environment variable is not set")
    
    if not supabase_key:
        raise ValueError("SUPABASE_SERVICE_ROLE_KEY environment variable is not set")
    
    logger.info(f"Connecting to Supabase: {supabase_url}")
    
    return create_client(supabase_url, supabase_key)


def check_database_connection() -> bool:
    """
    Check if database connection is working
    
    Returns:
        True if connection successful, False otherwise
    """
    try:
        client = get_supabase_client()
        # Simple query to test connection
        client.table('cases').select('case_id', count='exact').limit(1).execute()
        logger.info("✅ Database connection successful")
        return True
    except Exception as e:
        logger.error(f"❌ Database connection failed: {str(e)}")
        return False

