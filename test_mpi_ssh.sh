#!/bin/bash
#
# Test MPI SSH Connectivity
# 
# This script tests if SSH is properly configured for MPI jobs
# Run as crew user (uses sudo)
#

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get list of sudoers users (excluding system users)
get_sudoers_users() {
    local users=""
    
    # Get users from sudo group
    if getent group sudo &>/dev/null; then
        users=$(getent group sudo | cut -d: -f4 | tr ',' '\n')
    fi
    
    # Also get users from wheel group (common on RHEL/CentOS)
    if getent group wheel &>/dev/null; then
        wheel_users=$(getent group wheel | cut -d: -f4 | tr ',' '\n')
        users=$(echo -e "${users}\n${wheel_users}" | sort -u)
    fi
    
    # Filter out system users (UID < 1000) and empty lines
    local filtered_users=""
    for user in $users; do
        if [[ -n "$user" ]]; then
            uid=$(id -u "$user" 2>/dev/null || echo 0)
            if [[ $uid -ge 1000 ]]; then
                filtered_users="${filtered_users}${user}\n"
            fi
        fi
    done
    
    echo -e "$filtered_users" | grep -v "^$" | sort -u
}

SUDOERS_USERS=$(get_sudoers_users)

if [[ -z "$SUDOERS_USERS" ]]; then
    echo -e "${RED}ERROR: No sudoers users found (UID >= 1000)${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  MPI SSH Connectivity Test${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Get cluster nodes
if command -v pbsnodes &> /dev/null; then
    NODES=$(pbsnodes -a 2>/dev/null | grep -E "^[a-z]" | grep -v "^$" || hostname)
else
    NODES=$(hostname)
fi

echo "Testing SSH connectivity for sudoers users"
echo "Users: $(echo "$SUDOERS_USERS" | wc -l) ($(echo $SUDOERS_USERS | tr '\n' ' '))"
echo "Cluster nodes found: $(echo $NODES | wc -w)"
echo ""

PASS=0
FAIL=0

for user in $SUDOERS_USERS; do
    echo -e "${GREEN}Testing user: ${user}${NC}"
    for node in $NODES; do
        echo -n "  $node ... "
        if timeout 5 sudo -u "$user" ssh -o ConnectTimeout=3 -o BatchMode=yes "$node" "hostname" &>/dev/null; then
            echo -e "${GREEN}✓ PASS${NC}"
            ((PASS++))
        else
            echo -e "${RED}✗ FAIL${NC}"
            ((FAIL++))
        fi
    done
    echo ""
done

echo -e "${GREEN}========================================${NC}"
echo "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo -e "${GREEN}========================================${NC}"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}Some tests failed. Troubleshooting:${NC}"
    echo "1. Ensure setup_ssh_for_mpi.sh has been run on all nodes"
    echo "2. Check if all nodes are online and PBS is running"
    echo "3. Verify network connectivity between nodes"
    FIRST_USER=$(echo "$SUDOERS_USERS" | head -1)
    echo "4. Check logs: sudo -u ${FIRST_USER} ssh -v <failed_node> hostname"
    exit 1
else
    echo ""
    echo -e "${GREEN}✓ All SSH connectivity tests passed!${NC}"
    echo "Your cluster is ready for multi-node MPI jobs."
    exit 0
fi
