#!/bin/bash
#
# Update nginx certificate on uooddc via bastion (orthus)
#
# Usage: bash update_nginx_cert.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

BASTION="barberis@orthus.nic.uoregon.edu"
TARGET="uooddc"
CERT_FILE="oaciss.uoregon.edu.crt"

log_section "Nginx Certificate Update on uooddc"

# Step 1: Copy certificate from orthus to uooddc
log_info "Step 1: Copying certificate from orthus to uooddc..."
ssh $BASTION "scp /home/users/barberis/$CERT_FILE $TARGET:/tmp/"
log_info "✓ Certificate copied to uooddc:/tmp/"

# Step 2: Find nginx certificate location
log_info "Step 2: Locating nginx certificate configuration..."
ssh $BASTION "ssh $TARGET 'sudo find /etc/nginx /etc/ssl /etc/pki -name \"*oaciss*\" -o -name \"*uoregon*\" 2>/dev/null | head -20'" || true

# Step 3: Check nginx config for SSL certificate paths
log_info "Step 3: Checking nginx SSL configuration..."
ssh $BASTION "ssh $TARGET 'sudo grep -r \"ssl_certificate\" /etc/nginx/ 2>/dev/null | grep -v \"#\" | grep -v ssl_certificate_key'" || true

# Step 4: List sites-enabled to find the config
log_info "Step 4: Checking nginx sites configuration..."
ssh $BASTION "ssh $TARGET 'sudo ls -la /etc/nginx/sites-enabled/ 2>/dev/null || sudo ls -la /etc/nginx/conf.d/ 2>/dev/null'" || true

log_section "Manual Steps Required"
echo "Based on the output above, you need to:"
echo "1. Identify the current certificate path"
echo "2. Backup the existing certificate"
echo "3. Copy the new certificate to the nginx location"
echo "4. Reload nginx"
echo ""
echo "Example commands (adjust paths as needed):"
echo "  ssh $BASTION 'ssh $TARGET \"sudo cp /etc/ssl/certs/oaciss.uoregon.edu.crt /etc/ssl/certs/oaciss.uoregon.edu.crt.backup\"'"
echo "  ssh $BASTION 'ssh $TARGET \"sudo cp /tmp/$CERT_FILE /etc/ssl/certs/oaciss.uoregon.edu.crt\"'"
echo "  ssh $BASTION 'ssh $TARGET \"sudo nginx -t\"'"
echo "  ssh $BASTION 'ssh $TARGET \"sudo systemctl reload nginx\"'"
