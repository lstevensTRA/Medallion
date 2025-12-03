#!/bin/bash
# Start frontend on port 3005

cd "$(dirname "$0")"
echo "🚀 Starting frontend on port 3005..."
echo ""
echo "📁 Directory: $(pwd)"
echo "🌐 URL: http://localhost:3005"
echo ""
echo "Press Ctrl+C to stop"
echo ""

npm run dev

