#!/bin/bash

# WireGuard VPN and E4S Mount Setup Script
# This script installs WireGuard VPN and mounts the E4S On-Prem VM
# Designed to be run as root or with sudo privileges on Ubuntu 22.04 or similar
# WARNING: Contains hardcoded VPN credentials - can only be used in one cluster at a time

set -e  # Exit immediately if a command exits with a non-zero status

####################
# CONFIGURE NON-INTERACTIVE MODE
####################

echo "=== Configuring non-interactive mode ==="

# Set environment variables for non-interactive mode
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Configure needrestart to never prompt
CONFIG_FILE="/etc/needrestart/needrestart.conf"
if command -v needrestart >/dev/null 2>&1; then
  if [[ -f "$CONFIG_FILE" ]]; then
    sudo sed -i "s|^#\$nrconf{restart} = .*|\$nrconf{restart} = 'a';|" "$CONFIG_FILE"
    sudo sed -i "s|^\$nrconf{restart} = .*|\$nrconf{restart} = 'a';|" "$CONFIG_FILE"
    echo "Updated $CONFIG_FILE to set \$nrconf{restart} = 'a';"
  else
    echo "\$nrconf{restart} = 'a';" | sudo tee "$CONFIG_FILE"
    echo "Created $CONFIG_FILE to set \$nrconf{restart} = 'a';"
  fi
fi

# Set debconf to never prompt
echo '* libraries/restart-without-asking boolean true' | sudo debconf-set-selections
sudo bash -c 'echo "$nrconf{restart} = '\''a'\'';" > /etc/needrestart/needrestart.conf'

####################
# CONFIGURATION VARIABLES
####################

echo "=== Setting configuration variables ==="

# E4S On-Prem VM IP address (change if needed)
PERSISTENT_STORAGE_SERVICE_IP="10.53.0.15"

# E4S mount point
E4S_MOUNT_POINT="/e4sonpremvm"

# WireGuard configuration file path
WIREGUARD_CONFIG_FILE="/etc/wireguard/hccs.conf"

####################
# FIX APT REPOSITORY CONFLICTS
####################

echo "=== Fixing APT repository conflicts ==="

# Fix Microsoft repository conflicts (VS Code repo)
if [ -f /etc/apt/sources.list.d/vscode.list ]; then
    echo "Fixing Microsoft VS Code repository configuration..."
    sudo rm -f /etc/apt/sources.list.d/vscode.list
    sudo rm -f /etc/apt/keyrings/packages.microsoft.gpg 2>/dev/null || true
    sudo rm -f /usr/share/keyrings/microsoft.gpg 2>/dev/null || true
fi

# Run apt update with error handling
echo "Updating package lists..."
if ! sudo apt-get update -y 2>&1 | grep -v "Conflicting values"; then
    echo "Warning: apt update had some errors, but continuing..."
fi

####################
# WIREGUARD VPN INSTALLATION
####################

echo "=== Installing WireGuard VPN ==="

# Install wireguard and resolvconf with non-interactive flags
sudo DEBIAN_FRONTEND=noninteractive apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" wireguard
sudo DEBIAN_FRONTEND=noninteractive apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" resolvconf

echo "WireGuard installed successfully."

####################
# WIREGUARD VPN CONFIGURATION
####################

echo "=== Configuring WireGuard VPN ==="

# Define the WireGuard configuration content
WIREGUARD_CONFIG="[Interface]
PrivateKey = wFoBjApA+hjucEitRLT6KotGbqkcqr40GRIjlHfOdWc=
Address = 192.168.53.20/24
DNS = 10.53.0.1
MTU = 1420

[Peer]
PublicKey = YQPduLQPYRfjxD8K/FT6nbV+LG++FeVTpdsRbxSSnUk=
PresharedKey = 6R8TJTKF9GNvDBw1OglDfoA48JTg8sFwCoNyY8aec9k=
AllowedIPs = 10.53.0.0/24, 192.168.53.0/24
PersistentKeepalive = 25
Endpoint = picaas.adaptivecomputing.com:51853"

# Create WireGuard configuration directory if it doesn't exist
sudo mkdir -p /etc/wireguard

# Write the WireGuard configuration content to the file
echo "$WIREGUARD_CONFIG" | sudo tee "$WIREGUARD_CONFIG_FILE" > /dev/null

# Set proper permissions for the configuration file
sudo chmod 600 "$WIREGUARD_CONFIG_FILE"

echo "WireGuard configuration file created at $WIREGUARD_CONFIG_FILE"

####################
# CONFIGURE FIREWALL
####################

echo "=== Configuring firewall for WireGuard ==="

# Update UFW firewall settings to allow WireGuard traffic
if command -v ufw &> /dev/null; then
    sudo ufw allow 51820/udp
    echo "UFW firewall rule added for WireGuard."
else
    echo "UFW not installed, skipping firewall configuration."
fi

####################
# START WIREGUARD SERVICE
####################

echo "=== Starting WireGuard service ==="

# Enable the WireGuard interface to start on boot
sudo systemctl enable wg-quick@hccs

# Start the WireGuard interface
sudo systemctl start wg-quick@hccs

# Check WireGuard status
if sudo systemctl is-active --quiet wg-quick@hccs; then
    echo "✓ WireGuard VPN is running successfully."
else
    echo "✗ Warning: WireGuard VPN may not be running correctly."
    sudo systemctl status wg-quick@hccs || true
fi

####################
# INSTALL NFS CLIENT
####################

echo "=== Installing NFS client ==="

# Install NFS common tools
sudo DEBIAN_FRONTEND=noninteractive apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nfs-common

echo "NFS client installed successfully."

####################
# MOUNT E4S ON-PREM VM
####################

echo "=== Mounting E4S On-Prem VM ==="

# Create mount point directory
sudo mkdir -p "$E4S_MOUNT_POINT"

# Test connection to NFS server
echo "Testing connection to E4S server at $PERSISTENT_STORAGE_SERVICE_IP..."
if ping -c 3 -W 5 "$PERSISTENT_STORAGE_SERVICE_IP" > /dev/null 2>&1; then
    echo "✓ E4S server is reachable."
else
    echo "✗ Warning: E4S server is not reachable. Please check network connectivity."
    echo "  Make sure WireGuard VPN is connected."
    exit 1
fi

# Mount the E4S NFS share
echo "Mounting E4S NFS share..."
if sudo mount "$PERSISTENT_STORAGE_SERVICE_IP":/root "$E4S_MOUNT_POINT"; then
    echo "✓ E4S NFS mounted successfully at $E4S_MOUNT_POINT"
    
    # Add to /etc/fstab for automatic mounting at boot
    if ! grep -q "$E4S_MOUNT_POINT" /etc/fstab; then
        echo "Adding E4S mount to /etc/fstab for automatic mounting at boot..."
        echo "$PERSISTENT_STORAGE_SERVICE_IP:/root $E4S_MOUNT_POINT nfs defaults,_netdev 0 0" | sudo tee -a /etc/fstab
        echo "✓ E4S mount added to /etc/fstab"
    else
        echo "E4S mount already exists in /etc/fstab"
    fi
else
    echo "✗ ERROR: Failed to mount E4S NFS share."
    echo "  Please check:"
    echo "  1. WireGuard VPN is connected"
    echo "  2. E4S server has updated /etc/exports with this machine's IP"
    echo "  3. NFS service is running on E4S server"
    exit 1
fi

####################
# VERIFY MOUNT
####################

echo "=== Verifying E4S mount ==="

# List contents of mounted directory
if ls "$E4S_MOUNT_POINT" > /dev/null 2>&1; then
    echo "✓ E4S mount verified. Contents:"
    ls -la "$E4S_MOUNT_POINT" | head -10
else
    echo "✗ Warning: Cannot access E4S mount directory."
fi

####################
# SUMMARY
####################

echo ""
echo "========================================="
echo "  WireGuard and E4S Setup Complete!"
echo "========================================="
echo ""
echo "✓ WireGuard VPN installed and configured"
echo "✓ WireGuard service enabled and started"
echo "✓ NFS client installed"
echo "✓ E4S On-Prem VM mounted at $E4S_MOUNT_POINT"
echo "✓ E4S mount added to /etc/fstab for persistence"
echo ""
echo "WireGuard Status:"
sudo wg show || echo "  (Unable to show WireGuard status)"
echo ""
echo "E4S Mount Status:"
df -h "$E4S_MOUNT_POINT" || echo "  (Unable to show mount status)"
echo ""
echo "========================================="
