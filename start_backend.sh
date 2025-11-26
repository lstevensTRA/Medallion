#!/bin/bash

# Medallion Architecture Backend Startup Script

echo "🚀 Starting Medallion Architecture Backend..."
echo ""

# Load environment variables
if [ -f ".env" ]; then
    echo "✅ Loading environment variables from .env"
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "⚠️  No .env file found - using system environment variables"
fi

# Check if in virtual environment
if [ -z "$VIRTUAL_ENV" ]; then
    echo "⚠️  Not in virtual environment. Consider activating one:"
    echo "   source venv/bin/activate"
    echo ""
fi

# Install dependencies if needed
if ! python -c "import fastapi" 2>/dev/null; then
    echo "📦 Installing dependencies..."
    pip install -r backend/requirements.txt
fi

# Start the backend
echo ""
echo "=" | tr -d '\n' | sed 's/.*/&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&/'
echo ""
echo "🌐 Medallion Architecture Backend"
echo ""
echo "   API:    http://localhost:8000"
echo "   Docs:   http://localhost:8000/docs"
echo "   Health: http://localhost:8000/health"
echo ""
echo "=" | tr -d '\n' | sed 's/.*/&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&/'
echo ""

# Change to backend directory and start
cd backend
python main.py

