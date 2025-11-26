#!/bin/bash

# ============================================================================
# Hybrid Architecture Integration Test
# Tests the FastAPI → Dagster → Supabase flow
# ============================================================================

echo "============================================================================"
echo "🧪 TESTING HYBRID ARCHITECTURE INTEGRATION"
echo "============================================================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
FASTAPI_URL="http://localhost:8000"
DAGSTER_URL="http://localhost:3000"
TEST_CASE_ID="1295022"

# ============================================================================
# Step 1: Check if services are running
# ============================================================================

echo "📋 Step 1: Checking if services are running..."
echo ""

# Check Dagster
echo -n "  Checking Dagster (${DAGSTER_URL})... "
if curl -s "${DAGSTER_URL}" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
    echo ""
    echo "❌ Dagster is not running. Start it with:"
    echo "   cd /Users/lindseystevens/Medallion"
    echo "   dagster dev -m dagster_pipeline"
    echo ""
    exit 1
fi

# Check FastAPI
echo -n "  Checking FastAPI (${FASTAPI_URL})... "
if curl -s "${FASTAPI_URL}/docs" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
    echo ""
    echo "❌ FastAPI is not running. Start it with:"
    echo "   cd /Users/lindseystevens/Medallion/backend"
    echo "   uvicorn app.main:app --reload"
    echo ""
    exit 1
fi

echo ""

# ============================================================================
# Step 2: Test Dagster health endpoint
# ============================================================================

echo "📋 Step 2: Testing Dagster health endpoint..."
echo ""

HEALTH_RESPONSE=$(curl -s "${FASTAPI_URL}/api/dagster/health")
echo "  Response: ${HEALTH_RESPONSE}"

if echo "${HEALTH_RESPONSE}" | grep -q "healthy"; then
    echo -e "  ${GREEN}✓ Health check passed${NC}"
else
    echo -e "  ${YELLOW}⚠ Health check returned unexpected response${NC}"
fi

echo ""

# ============================================================================
# Step 3: Check current status of test case
# ============================================================================

echo "📋 Step 3: Checking current status of case ${TEST_CASE_ID}..."
echo ""

STATUS_RESPONSE=$(curl -s "${FASTAPI_URL}/api/dagster/status/${TEST_CASE_ID}")
echo "  ${STATUS_RESPONSE}" | python3 -m json.tool 2>/dev/null || echo "  ${STATUS_RESPONSE}"

echo ""

# ============================================================================
# Step 4: Trigger extraction (async mode)
# ============================================================================

echo "📋 Step 4: Triggering extraction for case ${TEST_CASE_ID}..."
echo ""

TRIGGER_RESPONSE=$(curl -s -X POST "${FASTAPI_URL}/api/dagster/cases/${TEST_CASE_ID}/extract")
echo "  ${TRIGGER_RESPONSE}" | python3 -m json.tool 2>/dev/null || echo "  ${TRIGGER_RESPONSE}"

if echo "${TRIGGER_RESPONSE}" | grep -q "triggered"; then
    echo ""
    echo -e "  ${GREEN}✓ Extraction triggered successfully!${NC}"
    echo ""
    echo "  📊 Monitor progress in Dagster UI: ${DAGSTER_URL}/runs"
else
    echo ""
    echo -e "  ${RED}✗ Failed to trigger extraction${NC}"
    echo ""
    echo "  Check the response above for error details."
    exit 1
fi

echo ""

# ============================================================================
# Step 5: Poll for status updates
# ============================================================================

echo "📋 Step 5: Monitoring extraction progress..."
echo ""

MAX_ATTEMPTS=12  # 12 attempts × 5 seconds = 1 minute
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    sleep 5
    ATTEMPT=$((ATTEMPT + 1))
    
    echo -n "  Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: Checking status... "
    
    STATUS=$(curl -s "${FASTAPI_URL}/api/dagster/status/${TEST_CASE_ID}")
    CURRENT_STATUS=$(echo "${STATUS}" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    
    if [ "${CURRENT_STATUS}" = "complete" ]; then
        echo -e "${GREEN}✓ Complete!${NC}"
        echo ""
        echo "  Final status:"
        echo "  ${STATUS}" | python3 -m json.tool 2>/dev/null || echo "  ${STATUS}"
        echo ""
        echo -e "${GREEN}✅ INTEGRATION TEST PASSED!${NC}"
        echo ""
        echo "============================================================================"
        exit 0
    elif [ "${CURRENT_STATUS}" = "not_started" ]; then
        echo -e "${YELLOW}Waiting (not started yet)${NC}"
    elif [ "${CURRENT_STATUS}" = "bronze_only" ]; then
        echo -e "${YELLOW}Processing (Bronze → Silver)${NC}"
    elif [ "${CURRENT_STATUS}" = "silver_only" ]; then
        echo -e "${YELLOW}Processing (Silver → Gold)${NC}"
    else
        echo -e "${YELLOW}Unknown status: ${CURRENT_STATUS}${NC}"
    fi
done

echo ""
echo -e "${YELLOW}⚠ Extraction is still running after 1 minute${NC}"
echo ""
echo "This is normal for large cases. Check Dagster UI for progress:"
echo "  ${DAGSTER_URL}/runs"
echo ""
echo "Or continue monitoring with:"
echo "  watch -n 5 curl -s ${FASTAPI_URL}/api/dagster/status/${TEST_CASE_ID}"
echo ""
echo "============================================================================"

