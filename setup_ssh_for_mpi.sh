#!/bin/bash
#
# MPI SSH Setup Script for PBS/Torque Cluster with NIS
# 
# This script configures SSH connectivity between compute nodes for MPI jobs.
# Works with NIS (Network Information Service) - configures SSH for ALL users
# (current and future) without needing to run the script again.
#
# Can be run by crew user (non-root) - uses sudo for privileged operations.
# 
# Usage: bash setup_ssh_for_mpi.sh
#
# Deployment order:
#   1. Run on head node first (detects /NODUS/.is_headnode)
#   2. Run on each compute node after head node is ready
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if sudo is available
if ! command -v sudo &> /dev/null; then
   log_error "sudo command not found. This script requires sudo to be installed."
   exit 1
fi

# Detect node type
IS_HEADNODE=false
if [[ -f /NODUS/.is_headnode ]]; then
    IS_HEADNODE=true
    log_info "Detected HEAD NODE"
else
    log_info "Detected COMPUTE NODE"
fi

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
    log_error "No sudoers users found (UID >= 1000)"
    log_error "Please ensure users are in 'sudo' or 'wheel' group"
    exit 1
fi

log_info "Found $(echo "$SUDOERS_USERS" | wc -l) sudoers user(s): $(echo $SUDOERS_USERS | tr '\n' ' ')"

get_cluster_nodes() {
    local nodes=""
    if command -v pbsnodes &> /dev/null; then
        nodes=$(pbsnodes -a 2>/dev/null | grep -E "^[a-z]" | grep -v "^$" || echo "")
    fi
    
    if [[ -z "$nodes" ]]; then
        log_warn "Could not get node list from PBS, will only configure current node"
        nodes=$(hostname)
    fi
    
    echo "$nodes"
}

# Configure SSH for a single user
configure_user_ssh() {
    local user=$1
    local user_home="/home/${user}"
    local ssh_dir="${user_home}/.ssh"
    local known_hosts="${ssh_dir}/known_hosts"
    local authorized_keys="${ssh_dir}/authorized_keys"
    local private_key="${ssh_dir}/id_rsa"
    local public_key="${ssh_dir}/id_rsa.pub"
    local ssh_config="${ssh_dir}/config"
    
    log_info "Configuring SSH for user: ${user}"
    
    # Step 1: Create SSH directory with proper permissions
    sudo -u "$user" mkdir -p "$ssh_dir"
    sudo -u "$user" chmod 700 "$ssh_dir"
    
    # Step 2: Generate SSH key pair if it doesn't exist
    if [[ ! -f "$private_key" ]]; then
        log_info "  Generating SSH key pair for ${user}..."
        sudo -u "$user" ssh-keygen -t rsa -b 4096 -f "$private_key" -N "" -C "${user}@mpi-cluster"
        log_info "  SSH key pair generated"
    else
        log_info "  SSH key pair already exists"
    fi
    
    # Step 3: Add own public key to authorized_keys (for localhost SSH)
    if [[ -f "$public_key" ]]; then
        sudo -u "$user" touch "$authorized_keys"
        if ! sudo grep -qF "$(sudo cat $public_key)" "$authorized_keys" 2>/dev/null; then
            sudo -u "$user" cat "$public_key" >> "$authorized_keys"
            log_info "  Added public key to authorized_keys"
        fi
        sudo -u "$user" chmod 600 "$authorized_keys"
    fi
    
    # Step 4: Configure SSH client settings
    sudo -u "$user" cat > "$ssh_config" << 'EOF'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    PasswordAuthentication no
    IdentityFile ~/.ssh/id_rsa
EOF
    sudo -u "$user" chmod 600 "$ssh_config"
    log_info "  SSH client config created"
    
    # Step 5: Add all cluster nodes to known_hosts
    log_info "  Adding cluster nodes to known_hosts..."
    sudo -u "$user" bash -c "> $known_hosts"
    
    for node in $CLUSTER_NODES; do
        # Try to scan the node
        if sudo ssh-keyscan -H "$node" 2>/dev/null | sudo -u "$user" tee -a "$known_hosts" > /dev/null; then
            log_info "    ✓ Added $node"
        else
            log_warn "    ✗ Could not scan $node (may not be ready)"
        fi
        
        # Also try with IP if node resolves
        node_ip=$(getent hosts "$node" 2>/dev/null | awk '{print $1}' | head -1)
        if [[ -n "$node_ip" && "$node_ip" != "$node" ]]; then
            sudo ssh-keyscan -H "$node_ip" 2>/dev/null | sudo -u "$user" tee -a "$known_hosts" > /dev/null 2>&1
        fi
    done
    
    # Add localhost
    sudo ssh-keyscan -H localhost 2>/dev/null | sudo -u "$user" tee -a "$known_hosts" > /dev/null 2>&1
    sudo ssh-keyscan -H 127.0.0.1 2>/dev/null | sudo -u "$user" tee -a "$known_hosts" > /dev/null 2>&1
    
    sudo -u "$user" chmod 600 "$known_hosts"
    log_info "  Known hosts configured ($(sudo wc -l < $known_hosts) entries)"
    
    # Step 6: If on head node, distribute public key to compute nodes
    if [[ "$IS_HEADNODE" == "true" ]]; then
        log_info "  [HEAD NODE] Distributing SSH keys to compute nodes..."
        
        for node in $CLUSTER_NODES; do
            if [[ "$node" == "$(hostname)" || "$node" == "$(hostname -s)" ]]; then
                continue  # Skip self
            fi
            
            # Try to copy the public key to the remote node
            if timeout 10 sudo -u "$user" ssh -o ConnectTimeout=5 "$node" "mkdir -p ~/.ssh && chmod 700 ~/.ssh" 2>/dev/null; then
                if timeout 10 sudo -u "$user" scp -o ConnectTimeout=5 "$public_key" "${node}:~/.ssh/id_rsa.pub.headnode" 2>/dev/null; then
                    timeout 10 sudo -u "$user" ssh -o ConnectTimeout=5 "$node" "cat ~/.ssh/id_rsa.pub.headnode >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && rm ~/.ssh/id_rsa.pub.headnode" 2>/dev/null
                    log_info "    ✓ Key distributed to $node"
                else
                    log_warn "    ✗ Could not copy key to $node"
                fi
            else
                log_warn "    ✗ Could not connect to $node (may not be ready)"
            fi
        done
    fi
    
    log_info "  ✓ Configuration complete for ${user}"
    echo ""
}

# Get cluster nodes
CLUSTER_NODES=$(get_cluster_nodes)
log_info "Cluster nodes found: $(echo $CLUSTER_NODES | wc -w) nodes"
log_info "Nodes: $(echo $CLUSTER_NODES | tr '\n' ' ')"
echo ""

# Configure SSH for each sudoers user
log_info "=========================================="
log_info "Configuring SSH for all sudoers users"
log_info "=========================================="
echo ""

for user in $SUDOERS_USERS; do
    configure_user_ssh "$user"
done

log_info "=========================================="
log_info "Testing SSH connectivity for all users"
log_info "=========================================="
echo ""

TOTAL_TESTS=0
PASSED_TESTS=0

for user in $SUDOERS_USERS; do
    log_info "Testing user: ${user}"
    for node in $CLUSTER_NODES; do
        ((TOTAL_TESTS++))
        if timeout 5 sudo -u "$user" ssh -o ConnectTimeout=3 "$node" "hostname" &>/dev/null; then
            log_info "  ✓ SSH to $node: SUCCESS"
            ((PASSED_TESTS++))
        else
            log_warn "  ✗ SSH to $node: FAILED (may not be ready yet)"
        fi
    done
    echo ""
done

# Summary
echo ""
log_info "=========================================="
log_info "  SSH MPI Setup Complete!"
log_info "=========================================="
log_info "Node type: $(if [[ "$IS_HEADNODE" == "true" ]]; then echo "HEAD NODE"; else echo "COMPUTE NODE"; fi)"
log_info "Configured users: $(echo "$SUDOERS_USERS" | wc -l)"
log_info "SSH tests: ${PASSED_TESTS}/${TOTAL_TESTS} passed"
echo ""

for user in $SUDOERS_USERS; do
    user_home="/home/${user}"
    ssh_dir="${user_home}/.ssh"
    known_hosts="${ssh_dir}/known_hosts"
    
    log_info "User: ${user}"
    log_info "  - Private key: ${ssh_dir}/id_rsa"
    log_info "  - Public key: ${ssh_dir}/id_rsa.pub"
    log_info "  - Authorized keys: ${ssh_dir}/authorized_keys"
    log_info "  - Known hosts: ${known_hosts} ($(sudo wc -l < $known_hosts 2>/dev/null || echo 0) entries)"
    log_info "  - Config: ${ssh_dir}/config"
done

if [[ $PASSED_TESTS -lt $TOTAL_TESTS ]]; then
    log_warn ""
    log_warn "Some SSH connections failed. This is normal if:"
    log_warn "  1. Compute nodes are still being deployed"
    log_warn "  2. PBS is not fully configured yet"
    log_warn "  3. Network is still initializing"
    log_warn ""
    log_warn "Re-run this script after all nodes are deployed and PBS is running."
fi

echo ""
log_info "To manually test SSH (example):"
FIRST_USER=$(echo "$SUDOERS_USERS" | head -1)
log_info "  sudo -u ${FIRST_USER} ssh <node> hostname"
echo ""

exit 0
