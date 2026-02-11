#!/bin/bash
#
# Demo script for running and testing Flutter web app like a real user
#
# This script demonstrates the complete workflow:
# 1. Build the Flutter web app
# 2. Serve it locally
# 3. Run automated browser tests
# 4. Generate test report
#

set -e  # Exit on error

echo "════════════════════════════════════════════════════════════════"
echo "  Pangea Chat - Flutter Web App Testing Demo"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PORT=${PORT:-8080}
APP_URL="http://localhost:$PORT"

# Step 1: Check prerequisites
echo "→ Step 1: Checking prerequisites..."

if ! command -v flutter &> /dev/null; then
    echo -e "${RED}✗ Flutter is not installed${NC}"
    echo "  Please install Flutter from: https://docs.flutter.dev/get-started/install"
    exit 1
fi
echo -e "${GREEN}✓ Flutter is installed${NC}"

if ! command -v node &> /dev/null; then
    echo -e "${YELLOW}⚠ Node.js is not installed (needed for Playwright tests)${NC}"
    echo "  You can still build and serve the app, but automated tests won't run"
    SKIP_TESTS=true
else
    echo -e "${GREEN}✓ Node.js is installed${NC}"
    SKIP_TESTS=false
fi

echo ""

# Step 2: Install dependencies
echo "→ Step 2: Installing Flutter dependencies..."
flutter pub get
echo -e "${GREEN}✓ Flutter dependencies installed${NC}"
echo ""

# Step 3: Build the web app
echo "→ Step 3: Building Flutter web app..."
echo "  This may take a few minutes on first run..."
flutter build web --release

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Web app built successfully${NC}"
    echo "  Output: build/web/"
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi
echo ""

# Step 4: Start web server in background
echo "→ Step 4: Starting web server on port $PORT..."

# Kill any existing server on the port
lsof -ti:$PORT | xargs kill -9 2>/dev/null || true

# Start Python simple HTTP server
cd build/web
python3 -m http.server $PORT > /dev/null 2>&1 &
SERVER_PID=$!
cd ../..

# Wait for server to start
sleep 2

if ps -p $SERVER_PID > /dev/null; then
    echo -e "${GREEN}✓ Web server started (PID: $SERVER_PID)${NC}"
    echo "  Access the app at: $APP_URL"
else
    echo -e "${RED}✗ Failed to start web server${NC}"
    exit 1
fi
echo ""

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "→ Cleaning up..."
    if [ ! -z "$SERVER_PID" ]; then
        kill $SERVER_PID 2>/dev/null || true
        echo -e "${GREEN}✓ Web server stopped${NC}"
    fi
}
trap cleanup EXIT

# Step 5: Open browser for manual testing
echo "→ Step 5: Opening browser for manual inspection..."
if command -v xdg-open &> /dev/null; then
    xdg-open "$APP_URL" 2>/dev/null || true
elif command -v open &> /dev/null; then
    open "$APP_URL" 2>/dev/null || true
fi
echo "  You can manually test the app at: $APP_URL"
echo "  Press Ctrl+C to stop the server"
echo ""

# Step 6: Run automated tests if Node.js is available
if [ "$SKIP_TESTS" = false ]; then
    echo "→ Step 6: Installing Playwright dependencies..."
    cd e2e-tests
    
    if [ ! -d "node_modules" ]; then
        npm install
    fi
    
    if ! npx playwright --version &> /dev/null; then
        echo "  Installing Playwright browsers..."
        npx playwright install chromium
    fi
    
    echo -e "${GREEN}✓ Test dependencies ready${NC}"
    echo ""
    
    echo "→ Step 7: Running automated browser tests..."
    echo "  Testing the app like a real user..."
    
    # Export APP_URL for tests
    export APP_URL
    
    # Run tests
    if npx playwright test --project=chromium --reporter=list; then
        echo ""
        echo -e "${GREEN}✓ All tests passed!${NC}"
        echo ""
        echo "→ Step 8: Generating test report..."
        npx playwright show-report &
        echo -e "${GREEN}✓ Test report opened in browser${NC}"
    else
        echo ""
        echo -e "${YELLOW}⚠ Some tests failed${NC}"
        echo "  View detailed report with: cd e2e-tests && npm run test:report"
    fi
    
    cd ..
else
    echo -e "${YELLOW}→ Step 6-8: Skipped (Node.js not available)${NC}"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Demo Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  • Web app built: build/web/"
echo "  • Server running: $APP_URL"
echo "  • Manual testing: Open browser to $APP_URL"
if [ "$SKIP_TESTS" = false ]; then
    echo "  • Automated tests: See test-results/ directory"
    echo "  • Test report: playwright-report/"
fi
echo ""
echo "To stop the server, press Ctrl+C"
echo ""

# Keep server running
wait $SERVER_PID
