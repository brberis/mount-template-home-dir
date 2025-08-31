#!/bin/bash

# Script to disable Kubernetes and free up network resources
# This script removes K3s, Docker, and all associated network interfaces

set -e

# Check if user has sudo access
if ! sudo -n true 2>/dev/null; then
    echo "ERROR: This script requires sudo access."
    echo "Please run: sudo -v"
    echo "Then run this script again as: ./disable_kubernetes.sh"
    exit 1
fi

# Create log file for unattended execution
LOG_FILE="/tmp/disable_kubernetes_$(date +%Y%m%d_%H%M%S).log"

echo "=== Kubernetes Disable Script (Unattended Mode) ==="
echo "Starting automatic Kubernetes cleanup process..."
echo "Timestamp: $(date)"
echo "Log file: $LOG_FILE"
echo "User: $(whoami) (with sudo access)"
echo ""

# Redirect all output to both console and log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to safely stop and disable services
stop_service() {
    local service_name=$1
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        log "Stopping $service_name service..."
        sudo systemctl stop "$service_name" || log "Warning: Failed to stop $service_name"
    fi
    
    if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        log "Disabling $service_name service..."
        sudo systemctl disable "$service_name" || log "Warning: Failed to disable $service_name"
    fi
}

# Function to remove network interface safely
remove_interface() {
    local interface=$1
    if ip link show "$interface" >/dev/null 2>&1; then
        log "Removing network interface: $interface"
        sudo ip link delete "$interface" 2>/dev/null || log "Warning: Failed to remove $interface"
    fi
}

# Function to kill processes by pattern
kill_processes() {
    local pattern=$1
    local pids=$(pgrep -f "$pattern" 2>/dev/null || true)
    if [ -n "$pids" ]; then
        log "Killing processes matching '$pattern': $pids"
        sudo kill -TERM $pids 2>/dev/null || true
        sleep 5
        # Force kill if still running
        pids=$(pgrep -f "$pattern" 2>/dev/null || true)
        if [ -n "$pids" ]; then
            log "Force killing processes: $pids"
            sudo kill -KILL $pids 2>/dev/null || true
        fi
    fi
}

# Step 1: Stop K3s service
log "Step 1: Stopping K3s service..."
stop_service "k3s"

# Step 2: Stop containerd service
log "Step 2: Stopping containerd service..."
stop_service "containerd"

# Step 3: Stop Docker service  
log "Step 3: Stopping Docker service..."
stop_service "docker"

# Step 4: Kill remaining Kubernetes processes
log "Step 4: Killing remaining Kubernetes processes..."
kill_processes "k3s"
kill_processes "containerd"
kill_processes "kubelet"
kill_processes "kube-proxy"
kill_processes "flannel"

# Step 5: Removing CNI network interfaces...
log "Step 5: Removing CNI network interfaces..."

# Remove main CNI interfaces
remove_interface "flannel.1"
remove_interface "cni0" 
remove_interface "docker0"

# Remove all veth interfaces (more aggressive cleanup)
log "Removing veth interfaces..."
for veth in $(ip link show type veth | grep -oE 'veth[a-zA-Z0-9]+' | head -20); do
    if [ -n "$veth" ]; then
        log "Removing veth interface: $veth"
        sudo ip link delete "$veth" 2>/dev/null || log "Warning: Failed to remove $veth"
    fi
done

# Remove any remaining flannel interfaces
for flannel in $(ip link show | grep -oE 'flannel\.[0-9]+' || true); do
    if [ -n "$flannel" ]; then
        remove_interface "$flannel"
    fi
done

# Remove veth interfaces
log "Removing veth interfaces..."
for veth in $(ip link show | grep "veth" | awk -F: '{print $2}' | awk '{print $1}'); do
    remove_interface "$veth"
done

# Step 6: Clean up network namespaces
log "Step 6: Cleaning up network namespaces..."
for ns in $(ip netns list 2>/dev/null | grep -E "cni-|sandbox-" | awk '{print $1}' || true); do
    log "Removing network namespace: $ns"
    sudo ip netns delete "$ns" 2>/dev/null || log "Warning: Failed to remove namespace $ns"
done

# Step 7: Unmount K3s and containerd mounts
log "Step 7: Unmounting K3s and containerd filesystems..."
# Get all k3s and containerd related mounts
for mount in $(mount | grep -E "/run/k3s|/var/lib/kubelet" | awk '{print $3}' | sort -r); do
    log "Unmounting: $mount"
    sudo umount -l "$mount" 2>/dev/null || log "Warning: Failed to unmount $mount"
done

# Step 8: Remove iptables rules
log "Step 8: Cleaning up iptables rules..."
# Flush CNI and K3s related chains
sudo iptables -t nat -F PREROUTING 2>/dev/null || true
sudo iptables -t nat -F POSTROUTING 2>/dev/null || true
sudo iptables -t filter -F FORWARD 2>/dev/null || true

# Remove custom chains
for chain in $(sudo iptables -t nat -L | grep -E "CNI|K3S|FLANNEL" | awk '{print $2}' || true); do
    sudo iptables -t nat -F "$chain" 2>/dev/null || true
    sudo iptables -t nat -X "$chain" 2>/dev/null || true
done

for chain in $(sudo iptables -t filter -L | grep -E "CNI|K3S|FLANNEL" | awk '{print $2}' || true); do
    sudo iptables -t filter -F "$chain" 2>/dev/null || true
    sudo iptables -t filter -X "$chain" 2>/dev/null || true
done

# Step 9: Remove routing rules
log "Step 9: Removing Kubernetes routing rules..."
# Remove routes for pod networks
sudo ip route del 10.42.0.0/24 2>/dev/null || true
sudo ip route del 172.17.0.0/16 2>/dev/null || true

# Step 10: Clean up directories (automatic removal)
log "Step 10: Removing K3s data directories..."
sudo rm -rf /var/lib/rancher/k3s 2>/dev/null || log "Warning: Failed to remove /var/lib/rancher/k3s"
sudo rm -rf /var/lib/kubelet 2>/dev/null || log "Warning: Failed to remove /var/lib/kubelet"
sudo rm -rf /etc/rancher 2>/dev/null || log "Warning: Failed to remove /etc/rancher"
sudo rm -rf /run/k3s 2>/dev/null || log "Warning: Failed to remove /run/k3s"

# Step 10.5: Final network cleanup (after data removal)
log "Step 10.5: Final network interface cleanup..."
sleep 2  # Give time for interfaces to settle
for veth in $(ip link show type veth | grep -oE 'veth[a-zA-Z0-9]+' 2>/dev/null || true); do
    if [ -n "$veth" ]; then
        log "Final cleanup of veth interface: $veth"
        sudo ip link delete "$veth" 2>/dev/null || true
    fi
done

# Step 11: Verify cleanup
log "Step 11: Verifying cleanup..."
echo "=== Verification Results ==="

echo "Services status:"
for service in k3s containerd docker; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "  $service: STILL RUNNING"
    else
        echo "  $service: STOPPED"
    fi
done

echo "Network interfaces:"
if ip link show | grep -E "flannel|cni|veth" >/dev/null; then
    echo "  WARNING: Some Kubernetes network interfaces still exist:"
    ip link show | grep -E "flannel|cni|veth" | head -5
else
    echo "  All Kubernetes network interfaces removed"
fi

echo "Processes:"
if pgrep -f "k3s|containerd|kubelet" >/dev/null; then
    echo "  WARNING: Some Kubernetes processes still running:"
    pgrep -f "k3s|containerd|kubelet" | head -5
else
    echo "  No Kubernetes processes running"
fi

echo "Routes:"
if ip route show | grep -E "10\.42\.|172\.17\." >/dev/null; then
    echo "  WARNING: Some Kubernetes routes still exist:"
    ip route show | grep -E "10\.42\.|172\.17\."
else
    echo "  No Kubernetes routes found"
fi

echo "Cleanup completed!"

