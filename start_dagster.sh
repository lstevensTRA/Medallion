#!/bin/bash

# Start Dagster Development Server
# This script sets up and launches the Dagster UI

echo "🚀 Starting Dagster for Tax Resolution Medallion Architecture"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found"
    echo "Please create .env file with your credentials"
    exit 1
fi

# Load environment variables
export $(cat .env | grep -v '^#' | xargs)

echo "✅ Environment variables loaded"
echo ""

# Check if dagster is installed
if ! command -v dagster &> /dev/null; then
    echo "⚠️  Dagster not installed. Installing..."
    pip install -e .
fi

echo "🎯 Starting Dagster dev server..."
echo "📊 Open browser to: http://localhost:3000"
echo ""

# Start Dagster
dagster dev -m dagster_pipeline

