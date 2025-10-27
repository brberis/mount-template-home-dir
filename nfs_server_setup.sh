#!/bin/bash
# NFS Server Setup Script for App VM (10.53.0.15)
# Run this on the App VM to configure NFS exports

set -e

echo "=== NFS Server Setup and Diagnostics ==="
echo ""

# Check if NFS server is installed
echo "1. Checking NFS server installation..."
if ! dpkg -l | grep -q nfs-kernel-server; then
    echo "   NFS server not installed. Installing..."
    sudo apt update
    sudo apt install -y nfs-kernel-server nfs-common
else
    echo "   ✓ NFS server is installed"
fi

# Create the directory to export if it doesn't exist
echo ""
echo "2. Setting up export directory..."
sudo mkdir -p /root
sudo chmod 755 /root

# Check current exports
echo ""
echo "3. Current NFS exports:"
cat /etc/exports || echo "   No exports configured"

# Backup existing exports
sudo cp /etc/exports /etc/exports.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

# Add export if not already present
echo ""
echo "4. Configuring NFS export for /root..."
if ! grep -q "^/root" /etc/exports; then
    echo "   Adding export entry..."
    # Export to the cluster subnet - adjust if your cluster uses a different subnet
    echo "/root 169.63.102.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
    echo "   ✓ Export added"
else
    echo "   ✓ Export already configured"
fi

# Show final exports configuration
echo ""
echo "5. Final exports configuration:"
cat /etc/exports

# Reload exports
echo ""
echo "6. Reloading NFS exports..."
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server

# Show active exports
echo ""
echo "7. Active NFS exports:"
sudo exportfs -v

# Check NFS server status
echo ""
echo "8. NFS server status:"
sudo systemctl status nfs-kernel-server --no-pager | head -15

# Check if firewall is active and configure if needed
echo ""
echo "9. Checking firewall configuration..."
if sudo ufw status | grep -q "Status: active"; then
    echo "   Firewall is active. Configuring NFS rules..."
    sudo ufw allow from 169.63.102.0/24 to any port nfs
    sudo ufw allow from 169.63.102.0/24 to any port 2049
    sudo ufw allow from 169.63.102.0/24 to any port 111
    sudo ufw allow from 169.63.102.0/24 to any port 20048
    echo "   ✓ Firewall rules added"
else
    echo "   Firewall is not active"
fi

# Show listening ports
echo ""
echo "10. NFS-related listening ports:"
sudo netstat -tulpn | grep -E '(nfs|rpc|mountd)' || echo "    No NFS ports found"

echo ""
echo "=== NFS Server Setup Complete ==="
echo ""
echo "To test from cluster node (169.63.102.231), run:"
echo "  sudo showmount -e 10.53.0.15"
echo "  sudo mount -t nfs 10.53.0.15:/root /e4sonpremvm"
