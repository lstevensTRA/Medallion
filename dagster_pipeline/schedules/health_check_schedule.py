"""
Health Check Schedule

Runs daily health checks on the Bronze → Silver → Gold data flow.
"""

from dagster import (
    schedule,
    RunRequest,
    ScheduleEvaluationContext,
    AssetSelection,
    define_asset_job
)


# Define a job that materializes all monitoring assets
health_check_job = define_asset_job(
    name="health_check_job",
    selection=AssetSelection.groups("monitoring"),
    description="Daily health check of Bronze → Silver → Gold data flow"
)


@schedule(
    name="daily_health_check",
    cron_schedule="0 8 * * *",  # Every day at 8:00 AM
    job=health_check_job,
    description="Daily health check of data pipeline"
)
def daily_health_check_schedule(context: ScheduleEvaluationContext):
    """
    Schedule that runs health checks daily
    
    Checks:
    1. Bronze → Silver trigger health
    2. Silver → Gold trigger health
    3. Gold business functions
    
    Runs at 8:00 AM every day
    """
    return RunRequest(
        run_key=f"health_check_{context.scheduled_execution_time.isoformat()}",
        tags={
            "schedule": "daily_health_check",
            "execution_time": context.scheduled_execution_time.isoformat()
        }
    )

