#!/bin/bash

# Test script for VolumeZ policy creation and updates
# This script tests both creating and updating policies

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# VolumeZ API Configuration
API_ENDPOINT="https://api.volumez.com"
TOKEN=""

# Test credentials
USERNAME="rventer@adaptivecomputing.com"
PASSWORD="AdaptiveAdmin@1"

# Policy configuration that's failing
POLICY_NAME="test-policy-update"  # Changed to avoid conflicts with existing hpc-policy
READ_IOPS=3600  # Fixed: Match VolumeZ validation (min 3600 for 450 bandwidth)
READ_BANDWIDTH=450
WRITE_IOPS=8000
WRITE_BANDWIDTH=450
READ_LATENCY=500
WRITE_LATENCY=500
CAPACITY_OPTIMIZATION="performance"
CAPACITY_RESERVATION=90
LOCAL_ZONE_READ="false"
ENCRYPTION="false"
RESILIENCY_MEDIA=0  # Changed from 1 to 0 to test update
RESILIENCY_NODE=0
RESILIENCY_ZONE=0

# Test mode: create, update, or both
TEST_MODE="both"  # Options: create, update, both

# Logging functions
print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

print_info() {
    echo -e "${NC}[INFO] $1${NC}"
}

print_debug() {
    echo -e "${BLUE}[DEBUG] $1${NC}"
}

# Authentication function
authenticate() {
    local username="$1"
    local password="$2"
    local payload
    local response

    print_info "Authenticating with VolumeZ API..."
    
    payload=$(jq -n \
        --arg username "$username" \
        --arg password "$password" \
        '{email: $username, password: $password}')
    
    print_debug "Sending authentication request to $API_ENDPOINT/signin..."
    response=$(curl -s -w "HTTP_CODE:%{http_code}" -X POST "$API_ENDPOINT/signin" \
        -H "content-type: application/json" \
        -d "$payload")
    
    # Extract HTTP code and response body
    http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    response_body=$(echo "$response" | sed 's/HTTP_CODE:[0-9]*$//')
    
    print_debug "HTTP Response Code: $http_code"
    
    if [ "$http_code" != "200" ]; then
        print_error "Authentication failed with HTTP code: $http_code"
        print_error "Response: $response_body"
        exit 1
    fi
    
    TOKEN=$(echo "$response_body" | jq -r '.IdToken // empty')
    if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
        print_error "Authentication failed - no valid token received"
        print_error "Full response: $response_body"
        exit 1
    fi
    
    # Mask token in output for security
    local masked_token="${TOKEN:0:10}...${TOKEN: -10}"
    print_success "Authentication successful! Token: $masked_token"
}

# Generate policy JSON
generate_policy_json() {
    local policy_data
    policy_data=$(printf '{
  "name": "%s",
  "bandwidthwrite": %d,
  "bandwidthread": %d,
  "iopswrite": %d,
  "iopsread": %d,
  "latencywrite": %d,
  "latencyread": %d,
  "localzoneread": %s,
  "capacityoptimization": "%s",
  "capacityreservation": %d,
  "resiliencymedia": %d,
  "resiliencynode": %d,
  "resiliencyzone": %d,
  "encryption": %s,
  "sed": false
}' "$POLICY_NAME" "$WRITE_BANDWIDTH" "$READ_BANDWIDTH" "$WRITE_IOPS" "$READ_IOPS" "$WRITE_LATENCY" "$READ_LATENCY" "$LOCAL_ZONE_READ" "$CAPACITY_OPTIMIZATION" "$CAPACITY_RESERVATION" "$RESILIENCY_MEDIA" "$RESILIENCY_NODE" "$RESILIENCY_ZONE" "$ENCRYPTION")
    
    echo "$policy_data"
}

# Test policy creation
test_policy_creation() {
    print_info "=== Testing Policy Creation ==="
    print_info "Policy Name: $POLICY_NAME"
    print_info "Read IOPS: $READ_IOPS"
    print_info "Read Bandwidth: $READ_BANDWIDTH MiB/s"
    print_info "Write IOPS: $WRITE_IOPS"
    print_info "Write Bandwidth: $WRITE_BANDWIDTH MiB/s"
    print_info "Read Latency: $READ_LATENCY μs"
    print_info "Write Latency: $WRITE_LATENCY μs"
    print_info "Capacity Optimization: $CAPACITY_OPTIMIZATION"
    print_info "Capacity Reservation: $CAPACITY_RESERVATION%"
    print_info "Local Zone Read: $LOCAL_ZONE_READ"
    print_info "Encryption: $ENCRYPTION"
    print_info "Media Resiliency: $RESILIENCY_MEDIA"
    print_info "Node Resiliency: $RESILIENCY_NODE"
    print_info "Zone Resiliency: $RESILIENCY_ZONE"
    
    # Create policy JSON
    local policy_data=$(generate_policy_json)
    
    print_debug "Generated policy JSON:"
    echo "$policy_data" | jq '.'
    
    # Make the API request
    print_info "Sending policy creation request..."
    local response
    response=$(curl -s -w "HTTP_CODE:%{http_code}" -X POST "$API_ENDPOINT/policies" \
        -H 'content-type: application/json' \
        -H "authorization: $TOKEN" \
        -d "$policy_data")
    
    # Extract HTTP code and response body
    local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    local response_body=$(echo "$response" | sed 's/HTTP_CODE:[0-9]*$//')
    
    print_debug "HTTP Response Code: $http_code"
    print_debug "Response Body: $response_body"
    
    if [ "$http_code" == "200" ] || [ "$http_code" == "201" ]; then
        print_success "Policy creation succeeded!"
        if [ -n "$response_body" ] && [ "$response_body" != "null" ]; then
            echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
        fi
        return 0
    else
        print_error "Policy creation failed with HTTP code: $http_code"
        print_error "Error details:"
        if [ -n "$response_body" ]; then
            # Try to pretty print JSON error, fallback to raw text
            echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
        fi
        
        # Check for common error patterns
        if echo "$response_body" | grep -q "bandwidth"; then
            print_warning "Error seems related to bandwidth configuration"
        fi
        if echo "$response_body" | grep -q "IOPS"; then
            print_warning "Error seems related to IOPS configuration"
        fi
        if echo "$response_body" | grep -q "validation"; then
            print_warning "Error seems to be a validation issue"
        fi
        if echo "$response_body" | grep -q "already exists" || echo "$response_body" | grep -q "duplicate"; then
            print_warning "Policy already exists - consider using update instead"
        fi
        return 1
    fi
}

# Test policy update
test_policy_update() {
    print_info "=== Testing Policy Update ==="
    
    # First, get the existing policy to see current values
    local existing_policy=$(get_existing_policy "$POLICY_NAME")
    if [ -z "$existing_policy" ]; then
        print_error "Policy '$POLICY_NAME' does not exist - cannot update"
        print_info "Run creation test first, or check policy name"
        return 1
    fi
    
    print_info "Found existing policy. Current values:"
    echo "$existing_policy" | jq '.'
    
    # Modify the resiliency value to test the update
    local original_resiliency=$(echo "$existing_policy" | jq -r '.resiliencymedia // 0')
    local new_resiliency=$((original_resiliency == 0 ? 1 : 0))
    
    print_info "Current resiliencymedia: $original_resiliency"
    print_info "Will update resiliencymedia to: $new_resiliency"
    
    # Generate updated policy JSON with the modified resiliency value
    RESILIENCY_MEDIA=$new_resiliency
    local updated_policy_data=$(generate_policy_json)
    
    print_info "Updated policy JSON to send:"
    echo "$updated_policy_data" | jq '.'
    
    # Use PATCH method as per VolumeZ documentation
    print_info "Attempting update via PATCH /policies/$POLICY_NAME (VolumeZ recommended method)..."
    local response
    response=$(curl -s -w "HTTP_CODE:%{http_code}" -X PATCH "$API_ENDPOINT/policies/$POLICY_NAME" \
        -H 'content-type: application/json' \
        -H "authorization: $TOKEN" \
        -d "$updated_policy_data")
    
    local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    local response_body=$(echo "$response" | sed 's/HTTP_CODE:[0-9]*$//')
    
    print_debug "PATCH /policies/$POLICY_NAME - HTTP Code: $http_code"
    print_debug "Response Body: $response_body"
    
    if [ "$http_code" == "200" ] || [ "$http_code" == "204" ]; then
        print_success "Policy update succeeded via PATCH!"
        if [ -n "$response_body" ] && [ "$response_body" != "null" ]; then
            echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
        fi
        
        # Verify the update by fetching the policy again
        print_info "Verifying the update..."
        local updated_policy=$(get_existing_policy "$POLICY_NAME")
        if [ -n "$updated_policy" ]; then
            local verified_resiliency=$(echo "$updated_policy" | jq -r '.resiliencymedia // 0')
            print_info "Verified resiliencymedia after update: $verified_resiliency"
            if [ "$verified_resiliency" == "$new_resiliency" ]; then
                print_success "Update verification successful!"
            else
                print_warning "Update may not have taken effect. Expected: $new_resiliency, Got: $verified_resiliency"
            fi
        fi
        
        return 0
    else
        print_error "Policy update failed with HTTP code: $http_code"
        print_error "Error details:"
        if [ -n "$response_body" ]; then
            echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
        fi
        
        # Check for common error patterns
        if echo "$response_body" | grep -q "bandwidth"; then
            print_warning "Error seems related to bandwidth configuration"
        fi
        if echo "$response_body" | grep -q "IOPS"; then
            print_warning "Error seems related to IOPS configuration"
        fi
        if echo "$response_body" | grep -q "authorization\|Authorization"; then
            print_warning "Error seems related to authorization - check token format"
        fi
        
        return 1
    fi
}

# Get existing policy by name
get_existing_policy() {
    local policy_name="$1"
    
    local response
    response=$(curl -s -w "HTTP_CODE:%{http_code}" -X GET "$API_ENDPOINT/policies" \
        -H 'content-type: application/json' \
        -H "authorization: $TOKEN")
    
    local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    local response_body=$(echo "$response" | sed 's/HTTP_CODE:[0-9]*$//')
    
    if [ "$http_code" == "200" ]; then
        echo "$response_body" | jq -r --arg name "$policy_name" '.[] | select(.name == $name)' 2>/dev/null
    fi
}

# Test getting existing policies (for debugging)
test_get_policies() {
    print_info "=== Testing Policy Listing ==="
    
    local response
    response=$(curl -s -w "HTTP_CODE:%{http_code}" -X GET "$API_ENDPOINT/policies" \
        -H 'content-type: application/json' \
        -H "authorization: $TOKEN")
    
    # Extract HTTP code and response body
    local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    local response_body=$(echo "$response" | sed 's/HTTP_CODE:[0-9]*$//')
    
    print_debug "GET Policies HTTP Response Code: $http_code"
    
    if [ "$http_code" == "200" ]; then
        print_success "Successfully retrieved policies list"
        local policy_count=$(echo "$response_body" | jq 'length' 2>/dev/null || echo "unknown")
        print_info "Found $policy_count existing policies"
        
        # List all policy names
        print_info "Existing policy names:"
        echo "$response_body" | jq -r '.[].name // empty' 2>/dev/null | while read policy; do
            if [ -n "$policy" ]; then
                print_info "  - $policy"
            fi
        done
        
        # Check if our target policy already exists
        local existing_policy=$(echo "$response_body" | jq -r --arg name "$POLICY_NAME" '.[] | select(.name == $name) | .name // empty' 2>/dev/null)
        if [ -n "$existing_policy" ]; then
            print_warning "Policy '$POLICY_NAME' already exists!"
            print_info "Current policy details:"
            echo "$response_body" | jq --arg name "$POLICY_NAME" '.[] | select(.name == $name)' 2>/dev/null
        else
            print_info "Policy '$POLICY_NAME' does not exist yet - creation should be possible"
        fi
    else
        print_error "Failed to retrieve policies with HTTP code: $http_code"
        print_error "Response: $response_body"
        return 1
    fi
}

# Test policy deletion (for cleanup)
test_policy_deletion() {
    local policy_name="${1:-$POLICY_NAME}"
    print_info "=== Testing Policy Deletion ==="
    print_warning "Attempting to delete policy: $policy_name"
    
    # Get policy ID if needed
    local existing_policy=$(get_existing_policy "$policy_name")
    if [ -z "$existing_policy" ]; then
        print_warning "Policy '$policy_name' does not exist - nothing to delete"
        return 0
    fi
    
    local policy_id=$(echo "$existing_policy" | jq -r '.id // .policyId // empty')
    
    # Try different deletion methods
    
    # Method 1: DELETE with policy name
    print_info "Attempting deletion via DELETE /policies/$policy_name..."
    local response1
    response1=$(curl -s -w "HTTP_CODE:%{http_code}" -X DELETE "$API_ENDPOINT/policies/$policy_name" \
        -H 'content-type: application/json' \
        -H "authorization: $TOKEN")
    
    local http_code1=$(echo "$response1" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    local response_body1=$(echo "$response1" | sed 's/HTTP_CODE:[0-9]*$//')
    
    if [ "$http_code1" == "200" ] || [ "$http_code1" == "204" ] || [ "$http_code1" == "404" ]; then
        print_success "Policy deletion succeeded (or policy didn't exist)"
        return 0
    fi
    
    # Method 2: DELETE with policy ID (if available)
    if [ -n "$policy_id" ] && [ "$policy_id" != "null" ]; then
        print_info "Attempting deletion via DELETE /policies/$policy_id..."
        local response2
        response2=$(curl -s -w "HTTP_CODE:%{http_code}" -X DELETE "$API_ENDPOINT/policies/$policy_id" \
            -H 'content-type: application/json' \
            -H "authorization: $TOKEN")
        
        local http_code2=$(echo "$response2" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
        local response_body2=$(echo "$response2" | sed 's/HTTP_CODE:[0-9]*$//')
        
        if [ "$http_code2" == "200" ] || [ "$http_code2" == "204" ] || [ "$http_code2" == "404" ]; then
            print_success "Policy deletion succeeded (or policy didn't exist)"
            return 0
        fi
    fi
    
    print_error "Policy deletion failed:"
    print_error "  DELETE /policies/$policy_name: HTTP $http_code1 - $response_body1"
    if [ -n "$policy_id" ]; then
        print_error "  DELETE /policies/$policy_id: HTTP $http_code2 - $response_body2"
    fi
    
    return 1
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --mode <create|update|both|delete>  Test mode (default: both)"
    echo "  --policy-name <name>                Policy name to test (default: hpc-policy)"
    echo "  --help                              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --mode create                    Only test policy creation"
    echo "  $0 --mode update                    Only test policy update"
    echo "  $0 --mode both                      Test both creation and update"
    echo "  $0 --mode delete                    Delete the test policy"
    echo "  $0 --policy-name my-test-policy     Use custom policy name"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            TEST_MODE="$2"
            shift 2
            ;;
        --policy-name)
            POLICY_NAME="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_info "=== VolumeZ Policy Management Test ==="
    print_info "Test Mode: $TEST_MODE"
    print_info "Policy Name: $POLICY_NAME"
    print_info "Target API: $API_ENDPOINT"
    print_info ""
    
    # Check dependencies
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed. Please install jq first."
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed. Please install curl first."
        exit 1
    fi
    
    # Step 1: Authenticate
    authenticate "$USERNAME" "$PASSWORD"
    print_info ""
    
    # Step 2: Get existing policies for context
    test_get_policies
    print_info ""
    
    # Step 3: Execute tests based on mode
    case $TEST_MODE in
        create)
            test_policy_creation
            ;;
        update)
            test_policy_update
            ;;
        both)
            print_info "Running creation test first..."
            if test_policy_creation; then
                print_info ""
                print_info "Creation succeeded, now testing update..."
                test_policy_update
            else
                print_info ""
                print_warning "Creation failed, but trying update anyway (policy might already exist)..."
                test_policy_update
            fi
            ;;
        delete)
            test_policy_deletion
            ;;
    esac
    
    print_info ""
    print_info "=== Test Complete ==="
}

# Run the test
main "$@"
