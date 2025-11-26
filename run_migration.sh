#!/bin/bash
# Script to apply the migration using psql

set -e

echo "============================================================================"
echo "APPLYING INTERVIEW & EXCEL MIGRATION"
echo "============================================================================"
echo ""

# Check if DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
    echo "❌ DATABASE_URL not set"
    echo ""
    echo "To get your database connection string:"
    echo "1. Go to: https://supabase.com/dashboard/project/egxjuewegzdctsfwuslf/settings/database"
    echo "2. Copy the 'Connection string' (URI format)"
    echo "3. Set it as: export DATABASE_URL='postgresql://...'"
    echo ""
    echo "OR set SUPABASE_DB_PASSWORD and run:"
    echo "   python3 apply_migration_direct.py"
    exit 1
fi

echo "✅ DATABASE_URL found"
echo "🔌 Connecting to database..."
echo ""

# Apply migration
psql "$DATABASE_URL" -f APPLY_INTERVIEW_AND_EXCEL_MIGRATIONS.sql

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Migration applied successfully!"
    echo ""
    echo "Verifying functions..."
    psql "$DATABASE_URL" -c "
        SELECT proname 
        FROM pg_proc 
        WHERE proname IN (
            'calculate_total_monthly_income',
            'calculate_total_monthly_expenses',
            'calculate_disposable_income',
            'get_cell_value',
            'process_bronze_interview'
        )
        ORDER BY proname;
    "
    echo ""
    echo "🎉 Done!"
else
    echo ""
    echo "❌ Migration failed - check errors above"
    exit 1
fi

