"""
Case Sensor

Monitors for new cases and automatically triggers Bronze ingestion.
"""

from dagster import sensor, RunRequest, SkipReason, SensorEvaluationContext
from dagster_pipeline.resources.supabase_resource import SupabaseResource


@sensor(
    name="new_case_sensor",
    description="Trigger Bronze ingestion when new cases are created",
    minimum_interval_seconds=60  # Check every minute
)
def new_case_sensor(context: SensorEvaluationContext):
    """
    Sensor that monitors for new cases and triggers Bronze data ingestion
    
    Logic:
    1. Query Supabase for cases created in last hour
    2. Check if Bronze data already exists
    3. If not, trigger Bronze ingestion assets
    
    Example Usage:
        This sensor runs automatically. When a new case is detected:
        - Triggers bronze_at_data
        - Triggers bronze_wi_data
        - Triggers bronze_trt_data
        - Triggers bronze_interview_data
    """
    # Note: In production, you'd get Supabase client from context
    # For now, this is a template that shows the pattern
    
    # Get last cursor (last checked timestamp)
    cursor = context.cursor or "2024-01-01T00:00:00Z"
    
    # In production:
    # supabase = SupabaseResource()
    # client = supabase.get_client()
    # new_cases = client.table('cases').select('id', 'case_number').gt('created_at', cursor).execute()
    
    # For demonstration:
    new_cases = []  # Would be populated from Supabase query
    
    if not new_cases:
        return SkipReason(f"No new cases since {cursor}")
    
    # Trigger Bronze ingestion for each new case
    run_requests = []
    for case in new_cases:
        run_requests.append(
            RunRequest(
                run_key=f"case_{case['id']}",
                run_config={
                    "ops": {
                        "bronze_at_data": {
                            "config": {
                                "case_id": case['id'],
                                "case_number": case['case_number']
                            }
                        },
                        "bronze_wi_data": {
                            "config": {
                                "case_id": case['id'],
                                "case_number": case['case_number']
                            }
                        },
                        "bronze_trt_data": {
                            "config": {
                                "case_id": case['id'],
                                "case_number": case['case_number']
                            }
                        },
                        "bronze_interview_data": {
                            "config": {
                                "case_id": case['id'],
                                "case_number": case['case_number']
                            }
                        }
                    }
                },
                tags={
                    "case_id": case['id'],
                    "case_number": case['case_number'],
                    "triggered_by": "new_case_sensor"
                }
            )
        )
    
    # Update cursor to current time
    import datetime
    new_cursor = datetime.datetime.utcnow().isoformat() + "Z"
    context.update_cursor(new_cursor)
    
    return run_requests

