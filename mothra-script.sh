#!/bin/bash
APP_IP="128.223.202.65"

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

# Remove any existing NVIDIA drivers
sudo apt purge -y nvidia-*

# Install NVIDIA driver
sudo apt install -y nvidia-driver-535-server

# Rebuild DKMS modules
sudo dkms autoinstall

# Blacklist Nouveau
echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
echo "options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf

# Update initramfs
sudo update-initramfs -u

# Remove and load necessary kernel modules
sudo modprobe -r nouveau || true
sudo modprobe nvidia || true

# Restart GPU manager
sudo systemctl restart gpu-manager || echo "GPU manager restart failed, continuing."

# Verify NVIDIA driver
echo "Verifying NVIDIA driver installation..."
if nvidia-smi &>/dev/null; then
    echo "NVIDIA driver successfully activated."
else
    echo "Failed to activate NVIDIA driver. Ensure installation was successful."
fi

# Enable NVIDIA persistence mode (optional)
sudo nvidia-smi -pm 1

echo "NVIDIA driver installation complete!"

######### SINGULARITY #########
# Install Singularity
sudo apt-get update
sudo apt-get update && sudo apt-get install -y \
    build-essential \
    libssl-dev \
    uuid-dev \
    libgpgme11-dev \
    squashfs-tools \
    libseccomp-dev \
    pkg-config

sudo apt-get install -y build-essential libssl-dev uuid-dev libgpgme11-dev \
    squashfs-tools libseccomp-dev wget pkg-config git cryptsetup debootstrap
wget https://dl.google.com/go/go1.13.linux-amd64.tar.gz
sudo tar --directory=/usr/local -xzvf go1.13.linux-amd64.tar.gz
export PATH=/usr/local/go/bin:$PATH

wget https://github.com/singularityware/singularity/releases/download/v3.5.3/singularity-3.5.3.tar.gz
tar -xzvf singularity-3.5.3.tar.gz
cd singularity
./mconfig
cd builddir
make
sudo make install

#If you want support for tab completion of Singularity commands, you need to source the appropriate file and add it to the bash completion directory in /etc so that it will be sourced automatically when you start another shell.
. etc/bash_completion.d/singularity
sudo cp etc/bash_completion.d/singularity /etc/bash_completion.d/


#Mount E4S App VM (but only after /etc/exports" on the E4S App has been updated with the new head Node  IP and NFS was started on the E4S App VM
sudo mkdir /e4s
sudo mount -t nfs "$APP_IP":/opt/acm/images /e4s

##### DISABLE UBUNTU UPDATE PROMPTS #####
sudo sed -i 's/^Prompt=.*$/Prompt=never/' /etc/update-manager/release-upgrades

# use as 
# singularity run --nv /e4s/e4s-cuda80-x86_64-24.11.sif 