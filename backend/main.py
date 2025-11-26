"""
Medallion Architecture Backend - Main Application
FastAPI backend for tax resolution data processing with Dagster orchestration.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging
from dotenv import load_dotenv

from app.config import settings, validate_settings
from app.database import check_database_connection
from app.routers import dagster_extraction

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=getattr(logging, settings.log_level),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application startup and shutdown events
    """
    # Startup
    logger.info("=" * 80)
    logger.info(f"🚀 Starting {settings.app_name} v{settings.app_version}")
    logger.info("=" * 80)
    
    # Validate configuration
    validation = validate_settings()
    if validation["errors"]:
        logger.error("❌ Configuration errors detected:")
        for error in validation["errors"]:
            logger.error(f"   - {error}")
        logger.warning("⚠️  Application may not function correctly")
    
    if validation["warnings"]:
        logger.warning("⚠️  Configuration warnings:")
        for warning in validation["warnings"]:
            logger.warning(f"   - {warning}")
    
    if validation["valid"]:
        logger.info("✅ Configuration validated successfully")
    
    # Check database connection
    logger.info("🔌 Checking database connection...")
    db_connected = check_database_connection()
    
    if not db_connected:
        logger.error("❌ Database connection failed - check your Supabase settings")
    
    logger.info("=" * 80)
    logger.info(f"📡 API Server: http://{settings.host}:{settings.port}")
    logger.info(f"📚 API Docs: http://{settings.host}:{settings.port}/docs")
    logger.info(f"🎨 Dagster UI: {settings.dagster_ui_url}")
    logger.info("=" * 80)
    
    yield
    
    # Shutdown
    logger.info("👋 Shutting down Medallion Architecture API...")


# Create FastAPI app
app = FastAPI(
    title=settings.app_name,
    description="""
    Production-ready Bronze → Silver → Gold medallion architecture API.
    
    ## Features
    
    * 🎯 **Dagster Orchestration** - Automated data pipeline execution
    * 📊 **Medallion Architecture** - Bronze, Silver, Gold data layers
    * 🔄 **SQL Triggers** - Automatic data transformation in database
    * 📄 **PDF Storage** - Blob storage for raw documents
    * 🔍 **Data Lineage** - Track data from source to destination
    * 📈 **Monitoring** - Real-time pipeline health checks
    
    ## Endpoints
    
    * `/api/dagster/cases/{case_id}/extract` - Trigger data extraction
    * `/api/dagster/status/{case_id}` - Check processing status
    * `/api/dagster/health` - Health check
    
    ## Architecture
    
    ```
    TiParser API / CaseHelper API
              ↓
         Bronze Layer (Raw JSON + PDFs)
              ↓ [SQL Triggers]
         Silver Layer (Typed + Enriched)
              ↓ [SQL Triggers]
         Gold Layer (Normalized Business Entities)
    ```
    """,
    version=settings.app_version,
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(
    dagster_extraction.router,
    tags=["Dagster Orchestration"]
)


@app.get("/")
async def root():
    """
    Root endpoint - API information
    """
    validation = validate_settings()
    
    return {
        "name": settings.app_name,
        "version": settings.app_version,
        "environment": settings.environment,
        "docs": "/docs",
        "dagster_ui": settings.dagster_ui_url,
        "status": {
            "configuration": "valid" if validation["valid"] else "invalid",
            "database": "connected" if check_database_connection() else "disconnected"
        }
    }


@app.get("/health")
async def health_check():
    """
    Health check endpoint
    """
    db_healthy = check_database_connection()
    
    return {
        "status": "healthy" if db_healthy else "degraded",
        "database": "connected" if db_healthy else "disconnected",
        "version": settings.app_version
    }


@app.get("/config")
async def get_config():
    """
    Get current configuration (non-sensitive values only)
    """
    validation = validate_settings()
    
    return {
        "environment": settings.environment,
        "supabase_url": settings.supabase_url,
        "tiparser_url": settings.tiparser_url,
        "dagster_ui_url": settings.dagster_ui_url,
        "log_level": settings.log_level,
        "validation": validation
    }


if __name__ == "__main__":
    import uvicorn
    
    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        reload=True,
        log_level=settings.log_level.lower()
    )

