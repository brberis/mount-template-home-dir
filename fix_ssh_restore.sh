#!/bin/bash
#
# Emergency SSH Restore Script
# Fixes SSH daemon if it was broken by previous setup
#

set -e

echo "Restoring SSH configuration..."

# Remove any broken SSH config additions
if [[ -f /etc/ssh/sshd_config.backup ]]; then
    echo "Restoring from backup..."
    cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
else
    echo "Removing MPI additions from sshd_config..."
    # Remove the MPI configuration block
    sed -i '/# MPI Configuration/,/IgnoreUserKnownHosts yes/d' /etc/ssh/sshd_config 2>/dev/null || true
fi

# Test SSH config
echo "Testing SSH configuration..."
sshd -t

if [ $? -eq 0 ]; then
    echo "✓ SSH configuration is valid"
    
    # Restart SSH service
    echo "Restarting SSH service..."
    if systemctl is-active --quiet sshd; then
        systemctl restart sshd
        echo "✓ SSH service restarted (sshd)"
    elif systemctl is-active --quiet ssh; then
        systemctl restart ssh
        echo "✓ SSH service restarted (ssh)"
    fi
    
    echo "✓ SSH service restored successfully!"
else
    echo "✗ SSH configuration still has errors"
    echo "Showing last 20 lines of sshd_config:"
    tail -20 /etc/ssh/sshd_config
    exit 1
fi
