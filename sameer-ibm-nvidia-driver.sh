#!/bin/bash
# Install Nvidia Drivers
# Function to print status messages
echo_status() {
    echo -e "\e[1;32m$1\e[0m"
}

##### NVIDIA DRIVER INSTALLATION #####

set -e  # Exit immediately if a command exits with a non-zero status
export DEBIAN_FRONTEND=noninteractive

echo "Checking for NVIDIA GPU..."
if ! lspci | grep -i nvidia &>/dev/null; then
    echo "No NVIDIA GPU detected. Skipping NVIDIA driver installation."
    exit 0
fi

# Suppress service restart prompts
if [ -f /etc/needrestart/needrestart.conf ]; then
    sudo sed -i 's/#$nrconf{restart} = .*/$nrconf{restart} = "a";/' /etc/needrestart/needrestart.conf
fi
echo '* libraries/restart-without-asking boolean true' | sudo debconf-set-selections

# Update and upgrade packages
sudo apt update -y
# sudo apt upgrade -y
sudo apt --fix-broken install -y

# Install required kernel headers
sudo apt install -y linux-headers-$(uname -r)

# Stop any services that might be using NVIDIA
echo "Stopping services that might use NVIDIA..."
sudo systemctl stop nvidia-persistenced || true
sudo systemctl stop gpu-manager || true

# Kill any processes using NVIDIA
echo "Terminating processes using NVIDIA driver..."
sudo fuser -k /dev/nvidia* || true
sudo lsof /dev/nvidia* 2>/dev/null | awk 'NR>1 {print $2}' | xargs -r sudo kill -9 || true

# Unload all NVIDIA kernel modules (must be done before purge for clean removal)
echo "Unloading existing NVIDIA kernel modules..."
sudo modprobe -r nvidia_drm || true
sudo modprobe -r nvidia_modeset || true
sudo modprobe -r nvidia_uvm || true
sudo modprobe -r nvidia || true
sudo rmmod nvidia_drm || true
sudo rmmod nvidia_modeset || true
sudo rmmod nvidia_uvm || true
sudo rmmod nvidia || true

# Remove any existing NVIDIA drivers and related packages
echo "Removing old NVIDIA packages..."
sudo apt purge -y nvidia-* libnvidia-* || true
sudo apt autoremove -y
sudo apt autoclean

# Install NVIDIA driver
echo "Installing NVIDIA driver 535-server..."
sudo apt install -y nvidia-driver-535-server

# Rebuild DKMS modules
sudo dkms autoinstall

# Blacklist Nouveau
echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
echo "options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf

# Update initramfs
sudo update-initramfs -u

# Remove nouveau if loaded
echo "Removing nouveau driver..."
sudo modprobe -r nouveau || true

# Ensure all old NVIDIA modules are completely unloaded
echo "Ensuring all old NVIDIA modules are unloaded..."
for i in {1..3}; do
    sudo modprobe -r nvidia_drm 2>/dev/null || true
    sudo modprobe -r nvidia_modeset 2>/dev/null || true
    sudo modprobe -r nvidia_uvm 2>/dev/null || true
    sudo modprobe -r nvidia 2>/dev/null || true
    sleep 1
done

# Load the newly installed NVIDIA kernel modules
echo "Loading new NVIDIA kernel modules..."
sudo modprobe nvidia
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to load nvidia module. Checking for issues..."
    dmesg | tail -20
    exit 1
fi

sudo modprobe nvidia_uvm
sudo modprobe nvidia_modeset  
sudo modprobe nvidia_drm

# Verify modules are loaded
echo "Verifying NVIDIA modules are loaded..."
lsmod | grep nvidia

# Create device nodes if they don't exist
if [ ! -e /dev/nvidia0 ]; then
    echo "Creating NVIDIA device nodes..."
    sudo nvidia-modprobe || true
fi

# Restart GPU manager
sudo systemctl restart gpu-manager || echo "GPU manager restart failed, continuing."

# Start NVIDIA persistence daemon
sudo systemctl start nvidia-persistenced || echo "Persistence daemon not available."

# Wait a moment for everything to initialize
sleep 2

# Verify NVIDIA driver
echo "Verifying NVIDIA driver installation..."
if nvidia-smi; then
    echo "✓ NVIDIA driver successfully activated!"
    
    # Enable NVIDIA persistence mode
    echo "Enabling NVIDIA persistence mode..."
    sudo nvidia-smi -pm 1 || echo "Failed to enable persistence mode."
    
    # Disable MIG if supported
    echo "Disabling MIG mode..."
    sudo nvidia-smi -mig 0 || echo "MIG mode not supported or already disabled."
    
    echo "NVIDIA driver installation complete!"
    echo_status "All provisioning steps completed successfully."
else
    echo "ERROR: NVIDIA driver installed but nvidia-smi failed."
    echo "Checking system logs..."
    dmesg | grep -i nvidia | tail -20
    exit 1
fi
