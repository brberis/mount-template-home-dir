#!/bin/bash
#
# fix_compute_hosts.sh - Synchronize /etc/hosts across all Slurm compute nodes
#
# This script:
# 1. Extracts all compute node hostnames and IPs from the head node's /etc/hosts
# 2. Ensures each compute node has entries for ALL other compute nodes
# 3. Works with any cluster ID format (ac-XXXX-0-N) and any number of nodes
#
# Usage: ./fix_compute_hosts.sh
# Must be run from the Slurm head node with sudo access to compute nodes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Compute Node /etc/hosts Synchronization${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Get list of compute nodes from Slurm
echo -e "${YELLOW}Step 1: Discovering compute nodes from Slurm...${NC}"
COMPUTE_NODES=$(sinfo -N -h -o "%N" | sort -u)

if [ -z "$COMPUTE_NODES" ]; then
    echo -e "${RED}ERROR: No compute nodes found in Slurm configuration${NC}"
    exit 1
fi

NODE_COUNT=$(echo "$COMPUTE_NODES" | wc -l)
echo -e "${GREEN}Found $NODE_COUNT compute node(s):${NC}"
echo "$COMPUTE_NODES" | sed 's/^/  - /'
echo ""

# Extract compute node entries from head node's /etc/hosts
echo -e "${YELLOW}Step 2: Extracting compute node entries from /etc/hosts...${NC}"
COMPUTE_ENTRIES=$(grep -E "ac-[0-9a-f]{4}-0-[0-9]+" /etc/hosts | grep "#NODUS" || true)

if [ -z "$COMPUTE_ENTRIES" ]; then
    echo -e "${RED}ERROR: No compute node entries found in /etc/hosts${NC}"
    echo -e "${RED}Expected format: IP_ADDRESS    ac-XXXX-0-N    #NODUS${NC}"
    exit 1
fi

echo -e "${GREEN}Found compute node entries:${NC}"
echo "$COMPUTE_ENTRIES" | sed 's/^/  /'
echo ""

# Create a temporary file with all compute node entries
TEMP_HOSTS=$(mktemp)
echo "$COMPUTE_ENTRIES" > "$TEMP_HOSTS"

# For each compute node, check and update /etc/hosts
echo -e "${YELLOW}Step 3: Synchronizing /etc/hosts on each compute node...${NC}"
echo ""

for NODE in $COMPUTE_NODES; do
    echo -e "${BLUE}Processing node: $NODE${NC}"
    
    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=5 "$NODE" "echo 'OK'" &>/dev/null; then
        echo -e "${RED}  ✗ Cannot connect to $NODE via SSH${NC}"
        continue
    fi
    
    # Get current /etc/hosts from compute node
    CURRENT_HOSTS=$(ssh "$NODE" "cat /etc/hosts")
    
    # Check each compute node entry
    ADDED_COUNT=0
    while IFS= read -r ENTRY; do
        # Extract hostname from entry
        HOSTNAME=$(echo "$ENTRY" | awk '{print $2}')
        
        # Skip if it's the current node (should already exist)
        if [ "$HOSTNAME" == "$NODE" ]; then
            continue
        fi
        
        # Check if entry exists
        if ! echo "$CURRENT_HOSTS" | grep -q "^[^#]*\s$HOSTNAME\s"; then
            echo -e "${YELLOW}  + Adding entry for $HOSTNAME${NC}"
            ssh "$NODE" "echo '$ENTRY' | sudo tee -a /etc/hosts > /dev/null"
            ((ADDED_COUNT++))
        fi
    done < "$TEMP_HOSTS"
    
    if [ $ADDED_COUNT -eq 0 ]; then
        echo -e "${GREEN}  ✓ Already up to date${NC}"
    else
        echo -e "${GREEN}  ✓ Added $ADDED_COUNT entr(ies)${NC}"
    fi
    
    echo ""
done

# Cleanup
rm -f "$TEMP_HOSTS"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Synchronization Complete!${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Verify connectivity between nodes
echo -e "${YELLOW}Step 4: Verifying inter-node connectivity...${NC}"
echo ""

VERIFICATION_FAILED=0
for NODE in $COMPUTE_NODES; do
    echo -e "${BLUE}Testing from $NODE:${NC}"
    
    for TARGET_NODE in $COMPUTE_NODES; do
        if [ "$NODE" == "$TARGET_NODE" ]; then
            continue
        fi
        
        # Test hostname resolution and ping
        if ssh "$NODE" "ping -c 1 -W 2 $TARGET_NODE" &>/dev/null; then
            echo -e "${GREEN}  ✓ Can reach $TARGET_NODE${NC}"
        else
            echo -e "${RED}  ✗ Cannot reach $TARGET_NODE${NC}"
            VERIFICATION_FAILED=1
        fi
    done
    echo ""
done

if [ $VERIFICATION_FAILED -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}All nodes can communicate successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
else
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}WARNING: Some connectivity issues detected${NC}"
    echo -e "${YELLOW}========================================${NC}"
fi
