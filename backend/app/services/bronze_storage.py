"""
Bronze Layer Storage Service
Handles insertion of raw API responses into Bronze layer tables
"""

from supabase import Client
from typing import Dict, Any, Optional
from datetime import datetime
import logging
import json

logger = logging.getLogger(__name__)


class BronzeStorage:
    """
    Bronze layer storage manager
    
    Responsibilities:
    1. Store raw API responses in Bronze tables (JSONB)
    2. Track processing status
    3. Provide replay capability
    
    Does NOT:
    - Parse or transform data (that's the trigger's job)
    - Validate business logic (that's Silver/Gold's job)
    """
    
    def __init__(self, supabase: Client):
        self.supabase = supabase
    
    def store_at_response(
        self,
        case_id: str,
        raw_response: Dict[str, Any],
        api_endpoint: Optional[str] = None,
        created_by: str = 'system'
    ) -> str:
        """
        Store Account Transcript (AT) raw response in Bronze layer
        
        Args:
            case_id: Case identifier (case_number)
            raw_response: Complete JSON response from TiParser AT endpoint
            api_endpoint: Optional API endpoint URL
            created_by: User/system that initiated the call
        
        Returns:
            bronze_id (UUID): Unique identifier for this Bronze record
        
        Example:
            >>> bronze = BronzeStorage(supabase)
            >>> raw_response = {"records": [...], "metadata": {...}}
            >>> bronze_id = bronze.store_at_response("CASE-001", raw_response)
            >>> print(f"Stored in Bronze: {bronze_id}")
            >>> # SQL trigger will automatically populate Silver tables
        """
        try:
            logger.info(f"📦 Storing AT raw response in Bronze for case {case_id}")
            
            # Insert into bronze_at_raw
            result = self.supabase.table('bronze_at_raw').insert({
                'case_id': case_id,
                'raw_response': raw_response,
                'api_source': 'tiparser',
                'api_endpoint': api_endpoint or '/analysis/at',
                'created_by': created_by,
                'processing_status': 'pending',  # Trigger will set to 'completed'
                'inserted_at': datetime.utcnow().isoformat()
            }).execute()
            
            bronze_id = result.data[0]['bronze_id']
            logger.info(f"✅ AT response stored in Bronze: {bronze_id}")
            
            return bronze_id
            
        except Exception as e:
            logger.error(f"❌ Failed to store AT response in Bronze: {e}")
            raise Exception(f"Bronze storage failed for AT: {str(e)}")
    
    def store_wi_response(
        self,
        case_id: str,
        raw_response: Dict[str, Any],
        api_endpoint: Optional[str] = None,
        created_by: str = 'system'
    ) -> str:
        """
        Store Wage & Income (WI) raw response in Bronze layer
        
        Args:
            case_id: Case identifier
            raw_response: Complete JSON response from TiParser WI endpoint
            api_endpoint: Optional API endpoint URL
            created_by: User/system that initiated the call
        
        Returns:
            bronze_id (UUID): Unique identifier for this Bronze record
        """
        try:
            logger.info(f"📦 Storing WI raw response in Bronze for case {case_id}")
            
            result = self.supabase.table('bronze_wi_raw').insert({
                'case_id': case_id,
                'raw_response': raw_response,
                'api_source': 'tiparser',
                'api_endpoint': api_endpoint or '/analysis/wi',
                'created_by': created_by,
                'processing_status': 'pending',
                'inserted_at': datetime.utcnow().isoformat()
            }).execute()
            
            bronze_id = result.data[0]['bronze_id']
            logger.info(f"✅ WI response stored in Bronze: {bronze_id}")
            
            return bronze_id
            
        except Exception as e:
            logger.error(f"❌ Failed to store WI response in Bronze: {e}")
            raise Exception(f"Bronze storage failed for WI: {str(e)}")
    
    def store_trt_response(
        self,
        case_id: str,
        raw_response: Dict[str, Any],
        api_endpoint: Optional[str] = None,
        created_by: str = 'system'
    ) -> str:
        """
        Store Tax Return Transcript (TRT) raw response in Bronze layer
        
        Args:
            case_id: Case identifier
            raw_response: Complete JSON response from TiParser TRT endpoint
            api_endpoint: Optional API endpoint URL
            created_by: User/system that initiated the call
        
        Returns:
            bronze_id (UUID): Unique identifier for this Bronze record
        """
        try:
            logger.info(f"📦 Storing TRT raw response in Bronze for case {case_id}")
            
            result = self.supabase.table('bronze_trt_raw').insert({
                'case_id': case_id,
                'raw_response': raw_response,
                'api_source': 'tiparser',
                'api_endpoint': api_endpoint or '/analysis/trt',
                'created_by': created_by,
                'processing_status': 'pending',
                'inserted_at': datetime.utcnow().isoformat()
            }).execute()
            
            bronze_id = result.data[0]['bronze_id']
            logger.info(f"✅ TRT response stored in Bronze: {bronze_id}")
            
            return bronze_id
            
        except Exception as e:
            logger.error(f"❌ Failed to store TRT response in Bronze: {e}")
            raise Exception(f"Bronze storage failed for TRT: {str(e)}")
    
    def store_interview_response(
        self,
        case_id: str,
        raw_response: Dict[str, Any],
        api_endpoint: Optional[str] = None,
        created_by: str = 'system'
    ) -> str:
        """
        Store CaseHelper Interview raw response in Bronze layer
        
        Args:
            case_id: Case identifier
            raw_response: Complete JSON response from CaseHelper Interview endpoint
            api_endpoint: Optional API endpoint URL
            created_by: User/system that initiated the call
        
        Returns:
            bronze_id (UUID): Unique identifier for this Bronze record
        """
        try:
            logger.info(f"📦 Storing Interview raw response in Bronze for case {case_id}")
            
            result = self.supabase.table('bronze_interview_raw').insert({
                'case_id': case_id,
                'raw_response': raw_response,
                'api_source': 'casehelper',
                'api_endpoint': api_endpoint or f'/api/cases/{case_id}/interview',
                'created_by': created_by,
                'processing_status': 'pending',
                'inserted_at': datetime.utcnow().isoformat()
            }).execute()
            
            bronze_id = result.data[0]['bronze_id']
            logger.info(f"✅ Interview response stored in Bronze: {bronze_id}")
            
            return bronze_id
            
        except Exception as e:
            logger.error(f"❌ Failed to store Interview response in Bronze: {e}")
            raise Exception(f"Bronze storage failed for Interview: {str(e)}")
    
    def get_bronze_record(
        self,
        bronze_table: str,
        bronze_id: str
    ) -> Optional[Dict[str, Any]]:
        """
        Retrieve a Bronze record by ID
        
        Args:
            bronze_table: Table name ('bronze_at_raw', 'bronze_wi_raw', etc.)
            bronze_id: Bronze record UUID
        
        Returns:
            Bronze record or None if not found
        """
        try:
            result = self.supabase.table(bronze_table).select('*').eq('bronze_id', bronze_id).execute()
            
            if result.data:
                return result.data[0]
            return None
            
        except Exception as e:
            logger.error(f"Failed to retrieve Bronze record: {e}")
            return None
    
    def get_bronze_by_case(
        self,
        bronze_table: str,
        case_id: str,
        limit: int = 10
    ) -> list:
        """
        Retrieve Bronze records for a case
        
        Args:
            bronze_table: Table name
            case_id: Case identifier
            limit: Maximum records to return
        
        Returns:
            List of Bronze records
        """
        try:
            result = self.supabase.table(bronze_table) \
                .select('*') \
                .eq('case_id', case_id) \
                .order('inserted_at', desc=True) \
                .limit(limit) \
                .execute()
            
            return result.data or []
            
        except Exception as e:
            logger.error(f"Failed to retrieve Bronze records: {e}")
            return []
    
    def mark_as_processed(
        self,
        bronze_table: str,
        bronze_id: str,
        status: str = 'completed',
        error: Optional[str] = None
    ) -> bool:
        """
        Mark a Bronze record as processed (or failed)
        
        Args:
            bronze_table: Table name
            bronze_id: Bronze record UUID
            status: 'completed' or 'failed'
            error: Optional error message if failed
        
        Returns:
            True if successful, False otherwise
        """
        try:
            self.supabase.table(bronze_table).update({
                'processing_status': status,
                'processed_at': datetime.utcnow().isoformat(),
                'processing_error': error
            }).eq('bronze_id', bronze_id).execute()
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to mark Bronze record as processed: {e}")
            return False
    
    def get_processing_summary(self) -> Dict[str, Any]:
        """
        Get Bronze layer processing summary
        
        Returns:
            Summary of Bronze ingestion and processing status
        """
        try:
            result = self.supabase.table('bronze_ingestion_summary') \
                .select('*') \
                .execute()
            
            summary = {}
            for row in result.data:
                summary[row['data_type']] = {
                    'total': row['total_records'],
                    'processed': row['processed'],
                    'pending': row['pending'],
                    'failed': row['failed'],
                    'first_ingestion': row['first_ingestion'],
                    'last_ingestion': row['last_ingestion']
                }
            
            return summary
            
        except Exception as e:
            logger.error(f"Failed to get processing summary: {e}")
            return {}
    
    def replay_bronze_to_silver(
        self,
        bronze_table: str,
        bronze_id: Optional[str] = None,
        case_id: Optional[str] = None
    ) -> int:
        """
        Replay Bronze records to Silver layer
        
        Useful when:
        - Trigger logic changes
        - Silver data was corrupted
        - Need to reprocess with new business rules
        
        Args:
            bronze_table: Table to replay from
            bronze_id: Optional specific record to replay
            case_id: Optional case to replay all records for
        
        Returns:
            Number of records replayed
        
        Note:
            This would typically trigger the Bronze → Silver SQL triggers manually
            For now, it marks records as 'pending' so triggers reprocess them
        """
        try:
            query = self.supabase.table(bronze_table).update({
                'processing_status': 'pending',
                'processed_at': None,
                'processing_error': None
            })
            
            if bronze_id:
                query = query.eq('bronze_id', bronze_id)
            elif case_id:
                query = query.eq('case_id', case_id)
            else:
                # Replay all failed records
                query = query.eq('processing_status', 'failed')
            
            result = query.execute()
            count = len(result.data) if result.data else 0
            
            logger.info(f"♻️  Marked {count} Bronze records for reprocessing")
            return count
            
        except Exception as e:
            logger.error(f"Failed to replay Bronze records: {e}")
            return 0


# Convenience functions for backward compatibility
def store_at_in_bronze(supabase: Client, case_id: str, raw_response: Dict[str, Any]) -> str:
    """Convenience function: Store AT response in Bronze"""
    bronze = BronzeStorage(supabase)
    return bronze.store_at_response(case_id, raw_response)


def store_wi_in_bronze(supabase: Client, case_id: str, raw_response: Dict[str, Any]) -> str:
    """Convenience function: Store WI response in Bronze"""
    bronze = BronzeStorage(supabase)
    return bronze.store_wi_response(case_id, raw_response)


def store_trt_in_bronze(supabase: Client, case_id: str, raw_response: Dict[str, Any]) -> str:
    """Convenience function: Store TRT response in Bronze"""
    bronze = BronzeStorage(supabase)
    return bronze.store_trt_response(case_id, raw_response)


def store_interview_in_bronze(supabase: Client, case_id: str, raw_response: Dict[str, Any]) -> str:
    """Convenience function: Store Interview response in Bronze"""
    bronze = BronzeStorage(supabase)
    return bronze.store_interview_response(case_id, raw_response)

