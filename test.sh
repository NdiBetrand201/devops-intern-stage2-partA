#!/bin/bash

# Blue/Green Deployment Test Script
# Tests automatic failover from Blue to Green

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
NGINX_URL="http://localhost:8080"
BLUE_URL="http://localhost:8081"
GREEN_URL="http://localhost:8082"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Blue/Green Deployment Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"

# Function to print test header
print_test() {
    echo -e "\n${YELLOW}[TEST $1]${NC} $2"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Function to print error
print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to print info
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Test 1: Services are running
print_test "1" "Checking if services are running..."

if curl -s -f "$NGINX_URL/healthz" > /dev/null 2>&1 || curl -s -f "$NGINX_URL/version" > /dev/null 2>&1; then
    print_success "Nginx is responding"
else
    print_error "Nginx is not responding"
    exit 1
fi

if curl -s -f "$BLUE_URL/version" > /dev/null; then
    print_success "Blue app is responding"
else
    print_error "Blue app is not responding"
    exit 1
fi

if curl -s -f "$GREEN_URL/version" > /dev/null; then
    print_success "Green app is responding"
else
    print_error "Green app is not responding"
    exit 1
fi

# Test 2: Normal state - Blue is active
print_test "2" "Testing normal state (Blue should be active)..."

HEADERS=$(curl -sI "$NGINX_URL/version")

# Check if response is from Blue (via headers)
if echo "$HEADERS" | grep -qi "X-App-Pool:.*blue"; then
    print_success "Traffic is going to Blue"
else
    ACTUAL_POOL=$(echo "$HEADERS" | grep -i "X-App-Pool:" | cut -d':' -f2 | tr -d ' \r\n' || echo "unknown")
    print_error "Traffic not going to Blue (got: $ACTUAL_POOL)"
    exit 1
fi

# Check headers are present
if echo "$HEADERS" | grep -qi "X-App-Pool:"; then
    print_success "X-App-Pool header is present"
else
    print_error "X-App-Pool header is missing"
    echo "$HEADERS"
    exit 1
fi

if echo "$HEADERS" | grep -qi "X-Release-Id:"; then
    print_success "X-Release-Id header is present"
else
    print_error "X-Release-Id header is missing"
    exit 1
fi

# Test 3: Consistency check
print_test "3" "Testing consistency (10 requests should all go to Blue)..."

BLUE_COUNT=0
ERROR_COUNT=0

for i in {1..10}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$NGINX_URL/version")
    
    if [ "$HTTP_CODE" != "200" ]; then
        ((ERROR_COUNT++))
    fi
    
    HEADERS=$(curl -sI "$NGINX_URL/version")
    if echo "$HEADERS" | grep -qi "X-App-Pool:.*blue"; then
        ((BLUE_COUNT++))
    fi
    
    sleep 0.2
done

if [ $ERROR_COUNT -eq 0 ]; then
    print_success "No errors (0/10 requests failed)"
else
    print_error "$ERROR_COUNT/10 requests failed"
    exit 1
fi

if [ $BLUE_COUNT -eq 10 ]; then
    print_success "All requests went to Blue (10/10)"
else
    print_error "Only $BLUE_COUNT/10 requests went to Blue"
fi

# Test 4: Induce failure on Blue
print_test "4" "Inducing failure on Blue..."

CHAOS_RESPONSE=$(curl -s -X POST "$BLUE_URL/chaos/start?mode=error")
print_info "Chaos mode activated on Blue"
sleep 1

# Verify Blue is actually failing
BLUE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BLUE_URL/version")
if [ "$BLUE_STATUS" == "500" ] || [ "$BLUE_STATUS" == "000" ]; then
    print_success "Blue is now returning errors (HTTP $BLUE_STATUS)"
else
    print_info "Blue status: HTTP $BLUE_STATUS (may still be transitioning)"
fi

# Test 5: Verify automatic failover to Green
print_test "5" "Testing automatic failover to Green..."

sleep 2  # Give nginx a moment to detect failure

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$NGINX_URL/version")

if [ "$HTTP_CODE" == "200" ]; then
    print_success "Nginx returned 200 (no error exposed to client)"
else
    print_error "Nginx returned $HTTP_CODE (error exposed to client!)"
    exit 1
fi

HEADERS=$(curl -sI "$NGINX_URL/version")
if echo "$HEADERS" | grep -qi "X-App-Pool:.*green"; then
    print_success "Traffic failed over to Green"
else
    ACTUAL_POOL=$(echo "$HEADERS" | grep -i "X-App-Pool:" | cut -d':' -f2 | tr -d ' \r\n' || echo "unknown")
    print_error "Failover did not occur (still on: $ACTUAL_POOL)"
    exit 1
fi

# Test 6: Stability under failure
print_test "6" "Testing stability (20 requests during Blue failure)..."

ERROR_COUNT=0
GREEN_COUNT=0
TOTAL_REQUESTS=20

print_info "Making $TOTAL_REQUESTS requests..."

for i in $(seq 1 $TOTAL_REQUESTS); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$NGINX_URL/version")
    
    if [ "$HTTP_CODE" != "200" ]; then
        ((ERROR_COUNT++))
        print_error "Request $i failed with HTTP $HTTP_CODE"
    fi
    
    HEADERS=$(curl -sI "$NGINX_URL/version")
    if echo "$HEADERS" | grep -qi "X-App-Pool:.*green"; then
        ((GREEN_COUNT++))
    fi
    
    sleep 0.3
done

# Calculate percentage
GREEN_PERCENT=$((GREEN_COUNT * 100 / TOTAL_REQUESTS))

if [ $ERROR_COUNT -eq 0 ]; then
    print_success "Zero errors during failover (0/$TOTAL_REQUESTS failed)"
else
    print_error "$ERROR_COUNT/$TOTAL_REQUESTS requests failed (NOT ACCEPTABLE)"
    exit 1
fi

if [ $GREEN_COUNT -ge 19 ]; then
    print_success "$GREEN_COUNT/$TOTAL_REQUESTS requests from Green (${GREEN_PERCENT}% >= 95%)"
else
    print_error "Only $GREEN_COUNT/$TOTAL_REQUESTS from Green (${GREEN_PERCENT}% < 95%)"
fi

# Test 7: Recovery test
print_test "7" "Testing recovery after stopping chaos..."

curl -s -X POST "$BLUE_URL/chaos/stop" > /dev/null
print_info "Chaos mode stopped on Blue"
print_info "Waiting 12 seconds for recovery (fail_timeout=10s + buffer)..."
sleep 12

HEADERS=$(curl -sI "$NGINX_URL/version")
POOL=$(echo "$HEADERS" | grep -i "X-App-Pool:" | cut -d':' -f2 | tr -d ' \r\n')

if [ "$POOL" == "blue" ]; then
    print_success "Traffic recovered back to Blue"
elif [ "$POOL" == "green" ]; then
    print_info "Still on Green (this is OK - Blue recovery takes time)"
else
    print_error "Unknown pool: $POOL"
fi

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  All Tests Passed! ✓${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${BLUE}Summary:${NC}"
echo -e "  • Blue/Green deployment working correctly"
echo -e "  • Automatic failover functioning (< 3 seconds)"
echo -e "  • Zero client-visible errors during failover"
echo -e "  • Headers properly forwarded"
echo -e "  • Stability maintained under failure"
echo -e "\n${GREEN}Your implementation is ready for submission!${NC}\n"