#!/bin/bash

# Medallion Architecture - Start All Services
# Starts both the FastAPI backend and Dagster orchestration

echo "🚀 Starting Medallion Architecture System..."
echo ""

# Load environment variables
if [ -f ".env" ]; then
    echo "✅ Loading environment variables from .env"
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "❌ No .env file found!"
    exit 1
fi

# Check if already running
if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null ; then
    echo "⚠️  Backend already running on port 8000"
else
    echo "🌐 Starting FastAPI Backend (port 8000)..."
    (cd backend && python main.py) &
    BACKEND_PID=$!
    echo "   Backend PID: $BACKEND_PID"
fi

sleep 2

if lsof -Pi :3000 -sTCP:LISTEN -t >/dev/null ; then
    echo "⚠️  Dagster already running on port 3000"
else
    echo "🎨 Starting Dagster (port 3000)..."
    export DAGSTER_HOME=/Users/lindseystevens/Medallion/dagster_home
    dagster dev -m dagster_pipeline &
    DAGSTER_PID=$!
    echo "   Dagster PID: $DAGSTER_PID"
fi

sleep 3

echo ""
echo "=" | tr -d '\n' | sed 's/.*/&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&/'
echo ""
echo "✅ Medallion Architecture System Running!"
echo ""
echo "📡 Services:"
echo "   Backend API:    http://localhost:8000"
echo "   API Docs:       http://localhost:8000/docs"
echo "   Dagster UI:     http://localhost:3000"
echo ""
echo "🧪 Quick Test:"
echo "   curl http://localhost:8000/health"
echo "   curl http://localhost:8000/api/dagster/health"
echo ""
echo "🛑 To stop:"
echo "   Press Ctrl+C or run: kill $BACKEND_PID $DAGSTER_PID"
echo ""
echo "=" | tr -d '\n' | sed 's/.*/&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&/'
echo ""

# Wait for processes
wait

