#!/bin/bash
#
# Restore PBS/Torque to Default Configuration
# 
# This script removes our MPI tuning changes and restores PBS to default.
# The default configuration actually worked fine for multi-node jobs!
#
# Run on: COMPUTE NODES only (not head node)
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if sudo is available
if ! command -v sudo &> /dev/null; then
   log_error "sudo command not found."
   exit 1
fi

# Detect node type
if [[ -f /NODUS/.is_headnode ]]; then
    log_info "HEAD NODE - PBS MOM not configured here, skipping"
    exit 0
fi

log_info "COMPUTE NODE - Restoring PBS defaults"

MOM_CONFIG="/var/spool/torque/mom_priv/config"

# Remove our MPI tuning section
if [[ -f "$MOM_CONFIG" ]]; then
    log_info "Removing MPI tuning configuration..."
    sudo sed -i '/# MPI Job Tuning - Auto-generated/,/# End MPI Job Tuning/d' "$MOM_CONFIG"
    log_info "✓ MPI tuning configuration removed"
    
    # Show what's left
    if [[ -s "$MOM_CONFIG" ]]; then
        log_info "Remaining config:"
        sudo cat "$MOM_CONFIG"
    else
        log_info "Config file is now empty (using PBS defaults)"
    fi
else
    log_warn "No PBS MOM config file found"
fi

# Keep the system limits - they're helpful and don't cause issues
log_info "Keeping system limits (helpful for MPI)"

# Restart PBS MOM
log_info "Restarting PBS MOM..."
if sudo systemctl restart pbs_mom; then
    log_info "✓ PBS MOM restarted with default configuration"
else
    log_error "Failed to restart PBS MOM"
    exit 1
fi

echo ""
log_info "=========================================="
log_info "  PBS Restored to Defaults!"
log_info "=========================================="
log_info "PBS MOM is now using default configuration"
log_info "This configuration worked fine for multi-node jobs"
log_info "System limits remain in place (helpful, no issues)"
echo ""

exit 0
