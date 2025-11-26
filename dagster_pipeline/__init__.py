"""
Dagster Pipeline for Tax Resolution Medallion Architecture

This pipeline orchestrates the Bronze → Silver → Gold data flow:
1. Bronze ingestion (calls APIs, stores raw data)
2. Silver monitoring (validates trigger processing)
3. Gold monitoring (validates business functions)

Architecture:
- Bronze: Raw API responses (immutable, replayable)
- Silver: Typed, enriched data (automatic via SQL triggers)
- Gold: Semantic, normalized business entities (automatic via SQL triggers)
"""

from dagster import Definitions

from dagster_pipeline.assets.bronze_assets import (
    bronze_at_data,
    bronze_wi_data,
    bronze_trt_data,
    bronze_interview_data,
)
from dagster_pipeline.assets.monitoring_assets import (
    monitor_bronze_silver_health,
    monitor_silver_gold_health,
    monitor_business_functions,
)
from dagster_pipeline.resources.supabase_resource import SupabaseResource
from dagster_pipeline.resources.tiparser_resource import TiParserResource
from dagster_pipeline.resources.casehelper_resource import CaseHelperResource
from dagster_pipeline.resources.pdf_storage_resource import pdf_storage_resource
from dagster_pipeline.sensors.case_sensor import new_case_sensor
from dagster_pipeline.schedules.health_check_schedule import (
    daily_health_check_schedule,
    health_check_job
)

# Define all Dagster components
defs = Definitions(
    assets=[
        # Bronze ingestion assets
        bronze_at_data,
        bronze_wi_data,
        bronze_trt_data,
        bronze_interview_data,
        
        # Monitoring assets
        monitor_bronze_silver_health,
        monitor_silver_gold_health,
        monitor_business_functions,
    ],
    resources={
        "supabase": SupabaseResource(),
        "tiparser": TiParserResource(),
        "casehelper": CaseHelperResource(),
        "pdf_storage": pdf_storage_resource,
    },
    jobs=[
        health_check_job,
    ],
    sensors=[
        new_case_sensor,
    ],
    schedules=[
        daily_health_check_schedule,
    ],
)

