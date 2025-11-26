"""
Configuration Module
Application settings and environment configuration.
"""

import os
from pathlib import Path
from typing import Optional
from pydantic_settings import BaseSettings
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()


class Settings(BaseSettings):
    """
    Application settings loaded from environment variables
    """
    
    # Application
    app_name: str = "Medallion Architecture API"
    app_version: str = "1.0.0"
    environment: str = os.getenv("ENVIRONMENT", "development")
    
    # Server
    host: str = os.getenv("HOST", "0.0.0.0")
    port: int = int(os.getenv("PORT", "8000"))
    
    # CORS
    cors_origins: list = [
        "http://localhost:3000",
        "http://localhost:5173",
        os.getenv("FRONTEND_URL", "http://localhost:3000"),
    ]
    
    # Supabase
    supabase_url: str = os.getenv("SUPABASE_URL", "")
    supabase_service_role_key: str = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
    supabase_anon_key: str = os.getenv("SUPABASE_ANON_KEY", "")
    
    # TiParser API
    tiparser_url: str = os.getenv("TIPARSER_URL", "https://tiparser.onrender.com")
    tiparser_api_key: str = os.getenv("TIPARSER_API_KEY", "")
    
    # CaseHelper API
    casehelper_api_url: str = os.getenv("CASEHELPER_API_URL", "")
    casehelper_username: str = os.getenv("CASEHELPER_USERNAME", "")
    casehelper_password: str = os.getenv("CASEHELPER_PASSWORD", "")
    casehelper_app_type: str = os.getenv("CASEHELPER_APP_TYPE", "")
    
    # Dagster
    dagster_home: Path = Path(os.getenv("DAGSTER_HOME", "/Users/lindseystevens/Medallion/dagster_home"))
    dagster_ui_url: str = os.getenv("DAGSTER_UI_URL", "http://localhost:3000")
    
    # Paths
    project_root: Path = Path("/Users/lindseystevens/Medallion")
    
    # Logging
    log_level: str = os.getenv("LOG_LEVEL", "INFO")
    
    class Config:
        env_file = ".env"
        case_sensitive = False


# Global settings instance
settings = Settings()


def validate_settings() -> dict:
    """
    Validate that all required settings are configured
    
    Returns:
        Dict with validation results
    """
    issues = []
    
    # Check critical settings
    if not settings.supabase_url:
        issues.append("SUPABASE_URL is not set")
    
    if not settings.supabase_service_role_key:
        issues.append("SUPABASE_SERVICE_ROLE_KEY is not set")
    
    if not settings.tiparser_api_key:
        issues.append("⚠️  TIPARSER_API_KEY is not set (TiParser calls will fail)")
    
    if not settings.casehelper_api_url:
        issues.append("⚠️  CASEHELPER_API_URL is not set (CaseHelper calls will fail)")
    
    return {
        "valid": len(issues) == 0,
        "issues": issues,
        "warnings": [i for i in issues if i.startswith("⚠️")],
        "errors": [i for i in issues if not i.startswith("⚠️")]
    }

