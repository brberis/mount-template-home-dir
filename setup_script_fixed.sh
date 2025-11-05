#!/bin/bash -e
#
# Torque PBS and K3s Service Configuration Script
#
# Description:
#   This script configures Torque PBS Mom service for shared home directory support
#   and ensures K3s service is started. Designed to run via Terraform provisioners
#   or similar automation tools where interactive authentication is not available.
#
# Features:
#   - Creates homedir installation directory structure
#   - Configures PBS Mom with home directory copy settings
#   - Captures running services snapshot
#   - Starts K3s service with proper sudo privileges
#
# Usage:
#   bash setup_script_fixed.sh
#
# Requirements:
#   - Must be run by a user with sudo privileges
#   - PBS/Torque (optional - only configured if running)
#   - K3s installed on the system
#
# Notes:
#   All systemctl and service commands use sudo to avoid polkit authentication
#   prompts that can timeout in non-interactive provisioning contexts.
#

sudo mkdir -p /opt/homedir-install
#cd /tmp
#VER=1.12
#F=v$VER.tar.gz
#wget -q https://github.com/ParaToolsInc/e4s-cloud-examples/archive/refs/tags/$F
#tar xzf $F
#rm -rf $F
#sudo mv e4s-cloud-examples-$VER /opt/homedir-install/.


F=/var/spool/torque/mom_priv/config

if sudo systemctl --type=service --state=running | cat | grep pbs_mom ; then
sudo tee -a $F >/dev/null <<'EOF'
$usecp *:/home /home
$spool_as_final_name true
EOF
sudo service pbs_mom restart
fi

sudo systemctl --type=service --state=running | cat > /tmp/provisioner-running-services.txt

sudo systemctl start k3s
