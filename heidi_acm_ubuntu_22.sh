#!/bin/bash

# This script is intended to be run as a provision script of a cluster.
# It installs NVIDIA drivers, configures system settings, and sets up a Jupyter Lab launcher.
# It also mounts a template directory for new users and limits CPU usage per user.
# It is designed to be run as root or with sudo privileges.
# It is assumed that the script is run on a system with Ubuntu 22.04 or similar.

##### GLOBAL VARIABLES #####

echo "=== Setting global variables... ==="
# CPU quota as a percentage of total CPU cores per user
CPU_LIMIT=4800

# Need Sharing and Template directories to be mounted in the user's home directory
# If false it will not mount the directories and TARGET_USER, IGNORE_USERS and PUBLIC_IP will be ignored
MOUNTING=false

# Define the target template user where the template directory is located
TARGET_USER="hccsadmin1"

# Persistent storage for users VM Public IP
PUBLIC_IP="10.53.0.15"

# Ignore users who should not have the template or shared directories mounted
IGNORE_USERS=("root" "ubuntu" "oddcadmin2")




##### IP VERIFICATION #####

# Check if current local IP matches server.nodus.com IP in /etc/hosts
check_server_ip() {
  echo "=== Verifying server identity... ==="
  # Get the IP for server.nodus.com from /etc/hosts
  SERVER_IP=$(grep -w "server.nodus.com" /etc/hosts | awk '{print $1}')
  if [ -z "$SERVER_IP" ]; then
    echo "Warning: server.nodus.com not in /etc/hosts – assuming non-head node."
    return 1
  fi
  
  # Check if any of the local IPs match the server IP
  MATCH_FOUND=0
  echo "Server IP from /etc/hosts: $SERVER_IP"
  echo "Checking local IP addresses:"
  
  for IP in $(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1"); do
    echo " - Found local IP: $IP"
    if [ "$IP" == "$SERVER_IP" ]; then
      echo " - MATCH: This IP matches server.nodus.com in /etc/hosts"
      MATCH_FOUND=1
      break
    fi
  done
  
  if [ "$MATCH_FOUND" -eq 0 ]; then
    echo "Warning: This is not server.nodus.com (no IP match). Skipping rest of script."
    return 1
  fi
  
  echo "IP check passed: This server is correctly identified as server.nodus.com"
  return 0
}

# Run the IP check before proceeding
if ! check_server_ip; then
  exit 0
fi


set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Configuring  needrestart ==="

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Pre-seed needrestart config to never prompt (if installed)
CONFIG_FILE="/etc/needrestart/needrestart.conf"
TEMP_FILE="$(mktemp)"

if command -v needrestart >/dev/null 2>&1; then
  if [[ -f "$CONFIG_FILE" ]]; then
    sudo sed -i "s|^#\$nrconf{restart} = .;|\$nrconf{restart} = 'a';|" "$CONFIG_FILE"
    echo "Updated $CONFIG_FILE to set \$nrconf{restart} = 'a';"
  else
    echo "\$nrconf{restart} = 'a';" | sudo tee "$CONFIG_FILE"
    echo "Created $CONFIG_FILE to set \$nrconf{restart} = 'a';"
  fi
fi

# Preseed debconf to never prompt for library restarts
echo '* libraries/restart-without-asking boolean true' | sudo debconf-set-selections

# Always ensure needrestart never prompts, even if installed later
sudo bash -c 'echo "$nrconf{restart} = '\''a'\'';" > /etc/needrestart/needrestart.conf'

##### NVIDIA DRIVER INSTALLATION #####

set -e  # Exit immediately if a command exits with a non-zero status
export DEBIAN_FRONTEND=noninteractive

# --- Begin: Fix NVIDIA package conflicts and held packages ---
echo "Cleaning up old/conflicting NVIDIA packages and held packages..."

# Unhold any held NVIDIA packages
sudo apt-mark unhold nvidia-driver nvidia-driver-535 nvidia-driver-535-server libnvidia-common libnvidia-common-535 libnvidia-common-535-server || true

# Remove conflicting NVIDIA packages
sudo apt-get purge -y 'nvidia-*' 'libnvidia-*' || true

# Clean up broken dependencies
sudo apt-get autoremove -y
sudo apt-get autoclean -y
sudo apt-get clean

# Remove any residual config
sudo dpkg --purge $(dpkg -l | awk '/^rc/ { print $2 }') || true

# Update package lists
sudo apt-get update -y
# --- End: Fix NVIDIA package conflicts and held packages ---

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

# Disable MIG
sudo nvidia-smi -mig 0

echo "NVIDIA driver installation complete!"

# Function to print status messages
echo_status() {
    echo -e "\e[1;32m$1\e[0m"
}

###### FIX FIREFOX ######

# Step 1: Remove Snap Firefox if installed
echo_status "Removing Snap version of Firefox..."
sudo snap remove firefox

# Step 2: Remove Snap cache to prevent auto reinstallation
echo_status "Clearing Snap cache..."
sudo rm -rf /var/cache/snapd

# Step 3: Ensure APT does not install Snap versions of Firefox
echo_status "Creating APT preferences to prioritize PPA version..."
echo -e 'Package: firefox*\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 501' | sudo tee /etc/apt/preferences.d/mozilla-firefox

# Step 4: Remove any existing Firefox installation
echo_status "Purging any existing Firefox package..."
sudo apt purge -y firefox
sudo apt autoremove -y

# Step 5: Add Mozilla PPA
echo_status "Adding Mozilla PPA..."
sudo add-apt-repository -y ppa:mozillateam/ppa

# Step 6: Update package lists
echo_status "Updating package lists..."
sudo apt update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# Step 7: Check if correct Firefox package is available
echo_status "Checking available Firefox versions..."
apt policy firefox

# Step 8: Install Firefox from the PPA
echo_status "Installing Firefox from Mozilla PPA..."
sudo apt install -y firefox -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# Step 9: Verify installation
echo_status "Verifying Firefox installation..."
which firefox && firefox --version

# Step 10: Prevent Snap from reinstalling Firefox automatically
echo_status "Marking Firefox package to prevent auto-update to Snap version..."
sudo apt-mark hold firefox

echo_status "Firefox installation completed successfully."


######### SINGULARITY #########
# Install Singularity
sudo apt-get update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
sudo apt-get update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" && sudo apt-get install -y \
    build-essential \
    libssl-dev \
    uuid-dev \
    libgpgme11-dev \
    squashfs-tools \
    libseccomp-dev \
    pkg-config \
    -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

sudo apt-get install -y build-essential libssl-dev uuid-dev libgpgme11-dev \
    squashfs-tools libseccomp-dev wget pkg-config git cryptsetup debootstrap \
    -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
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

#Mount E4S App VM (but only after /etc/exports" on the E4S App has been updated with the new head Node Public IP and NFS was started on the E4S App VM
#Updating /etc/exports on E4S VM run "vi /etc/exports" and add line "/root <public ip>(rw,sync,no_root_squash)" and run "systemctl restart nfs.service"
sudo mkdir /e4sonpremvm
sudo mount "$PUBLIC_IP":/root /e4sonpremvm


##### CREATE JUPYTER LAB LAUNCHER #####

APP_NAME="jupyter_launcher"
C_FILE="/tmp/$APP_NAME.c"
BIN_PATH="/usr/local/bin/$APP_NAME"
DESKTOP_FILE="/usr/share/applications/jupyter-lab.desktop"
ICON_DIR="/usr/share/pixmaps/"
ICON_PATH="$ICON_DIR/jupyter.png"
ICON_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/3/38/Jupyter_logo.svg/800px-Jupyter_logo.png"

# Ensure the target user is set
if [ -z "$TARGET_USER" ]; then
    echo "Error: TARGET_USER environment variable is not set."
    exit 1
fi

# Ensure GCC is installed
if ! command -v gcc &> /dev/null; then
    echo "Error: GCC is not installed. Installing..."
    sudo apt update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" && sudo apt install -y gcc -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
fi

# Ensure Singularity is installed
if ! command -v singularity &> /dev/null; then
    echo "Error: Singularity is not installed. Please install it before running this script."
    exit 1
fi

# Create the C program
cat <<EOF > "$C_FILE"
#include <stdlib.h>
#include <unistd.h>

int main() {
    // Show a "Loading..." dialog with no OK button
    system("zenity --progress --pulsate --text='Loading Jupyter Lab... Please wait.' --no-cancel --timeout=10 --width=500 &");

    // Execute the Singularity command with correct user home
    return system("singularity exec --nv /e4sonpremvm/E4S/24.02/e4s-cuda80-x86_64-24.11.sif bash -c \"cd && jupyter-lab\"");
}
EOF

# Compile the C program with sudo so it can write to /usr/local/bin
sudo gcc -o "$BIN_PATH" "$C_FILE"

# Ensure the binary is executable and properly owned
sudo chmod +x "$BIN_PATH"
sudo chown root:root "$BIN_PATH"  # Root should own global binaries

# Create icons directory if it doesn't exist
sudo mkdir -p "$ICON_DIR"

# Download Jupyter icon if it doesn't exist
if [ ! -f "$ICON_PATH" ]; then
    echo "Downloading Jupyter icon..."
    sudo wget -q --show-progress -O "$ICON_PATH" "$ICON_URL"
fi

# Ensure correct ownership of icon
sudo chmod 644 "$ICON_PATH"

# Create a .desktop file for Ubuntu UI
sudo tee "$DESKTOP_FILE" > /dev/null <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Jupyter Lab
Comment=Launch Jupyter Lab in Singularity
Exec=$BIN_PATH
Icon=$ICON_PATH
Terminal=false
Categories=Development;Science;
EOF

# Ensure the desktop file has correct permissions
sudo chmod 644 "$DESKTOP_FILE"

# Refresh UbuntuÃ¢ÂÂs application database
sudo update-desktop-database "/usr/share/applications"

echo "Ã¢ÂÂ Jupyter Lab launcher created successfully for all users."





##### MOUNTING OR COPYING TEMPLATE DIRECTORY ######
if [ "$MOUNTING" = true ]; then

    # This installation script can be run as a non-root user.
    # It uses sudo where necessary.

    # Install inotify-tools if not present
    if ! command -v inotifywait &> /dev/null; then
        sudo apt update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
        sudo apt install -y inotify-tools -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    fi


    # Combine arrays and append the literal TARGET_USER (escaped so it stays unexpanded in the generated script)
    # combined=( "${IGNORE_USERS[@]}" "'$TARGET_USER'" )

    # # Convert the array to a string with each element quoted
    # joined=$(printf '"%s" ' "${combined[@]}")
    # joined=${joined% }  # remove the trailing space


    # Create the service script at /usr/local/bin/user_mount_service.sh
    # First part: Expand TARGET_USER so its value is printed
    sudo tee /usr/local/bin/user_mount_service.sh > /dev/null <<EOF
#!/bin/bash
# user_mount_service.sh (Polling Version using fast copy)
# This version polls for new users and copies the template directory
# to the /home/<user>/Lab/ directory.

# Configuration
TARGET_USER="${TARGET_USER}"
IGNORE_USERS="${IGNORE_USERS[@]}"
EOF

    # Second part: Append the rest of the script with literal variables (using a quoted heredoc)
    sudo tee -a /usr/local/bin/user_mount_service.sh > /dev/null <<'EOF'
TEMPLATE_DIR="/e4sonpremvm/instructor_data/$TARGET_USER/LabTemplate"  # Source template directory
SHARE_DIR="/e4sonpremvm/instructor_data/$TARGET_USER/Share"  # Shared directory (read-execute only)
RETRIES=10
WAIT_TIME=2
POLL_INTERVAL=10


# Helper Functions
is_ignored_user() {
    local user="$1"
    for ignored in "${IGNORE_USERS[@]}"; do
        if [[ "$user" == "$ignored" ]]; then
            return 0
        fi
    done
    return 1
}

copy_template() {
    local user="$1"
    local lab_dir="/home/$user/Lab"
    mkdir -p "$lab_dir"
    if tar cf - -C "$TEMPLATE_DIR" . | tar xf - --no-same-owner --no-same-permissions -C "$lab_dir"; then
        chown -R "$user:$user" "$lab_dir"
        echo "[$(date)] Successfully copied '$TEMPLATE_DIR' to '$lab_dir' for user '$user'."
        return 0
    else
        echo "[$(date)] ERROR: Failed to copy '$TEMPLATE_DIR' to '$lab_dir' for user '$user'."
        return 1
    fi
}

create_share_symlink() {
    local user="$1"
    local home_dir="/home/$user"
    local share_link="$home_dir/Share"
    if [ ! -L "$share_link" ] || [ "$(stat -c %U "$share_link")" != "$user" ]; then
        sudo ln -sf "$SHARE_DIR" "$share_link"
        sudo chown -h "$user":"$user" "$share_link"
        echo "[$(date)] Created/fixed symlink to 'Share' in '$home_dir' for user '$user'."
    else
        echo "[$(date)] Symlink to 'Share' already correct in '$home_dir' for user '$user'."
    fi
}

process_user() {
    local user="$1"
    local home_dir=$(getent passwd "$user" | cut -d: -f6)

    if [[ -z "$home_dir" || "$home_dir" != /home/* ]]; then
        echo "[$(date)] Skipping user '$user' because their home directory '$home_dir' is not in /home/."
        return 1
    fi

    echo "[$(date)] Processing user '$user'."
    if [[ "$user" == "$TARGET_USER" ]]; then
        # Special handling for target user
        sudo rm -rf "$home_dir/Documents"
        sudo ln -sf "/e4sonpremvm/instructor_data/$user/Documents" "$home_dir/Documents"
        sudo ln -sf "/e4sonpremvm/instructor_data/$user/LabTemplate" "$home_dir/LabTemplate"
        sudo ln -sf "/e4sonpremvm/instructor_data/$user/Share" "$home_dir/Share"
        sudo chown -h "$user":"$user" "$home_dir/Documents" "$home_dir/LabTemplate" "$home_dir/Share"
        sudo chown -R "$user":"$user" "/e4sonpremvm/instructor_data/$user"
        sudo chmod -R 755 "/e4sonpremvm/instructor_data/$user/LabTemplate" "/e4sonpremvm/instructor_data/$user/Share"
    else
        # Other users get Lab and Share
        copy_template "$user"
        create_share_symlink "$user"
    fi
}

process_existing_users() {
    echo "[$(date)] Processing existing users..."
    while IFS=: read -r username _ uid _ _ home_dir _; do
        if [ "$uid" -ge 1000 ] && ! is_ignored_user "$username"; then
            if [[ "$home_dir" == /home/* ]]; then
                process_user "$username"
            fi
        fi
    done < /etc/passwd
}

poll_for_new_users() {
    local previous_users current_users new_users
    previous_users=$(awk -F: '{print $1}' /etc/passwd)
    echo "[$(date)] Starting polling for new users..."
    while true; do
        sleep "$POLL_INTERVAL"
        current_users=$(awk -F: '{print $1}' /etc/passwd)
        new_users=$(comm -13 <(echo "$previous_users" | sort) <(echo "$current_users" | sort))
        if [ -n "$new_users" ]; then
            echo "[$(date)] Detected new user(s): $new_users"
            for user in $new_users; do
                if ! is_ignored_user "$user"; then
                    process_user "$user"
                fi
            done
        fi
        previous_users="$current_users"
    done
}

# Main Execution
process_existing_users
poll_for_new_users
EOF

    # Make the service script executable
    sudo chmod +x /usr/local/bin/user_mount_service.sh

    # Create the systemd service file at /etc/systemd/system/user-mount.service
    sudo tee /etc/systemd/system/user-mount.service > /dev/null << EOF
[Unit]
Description=Mount template directory to new users' home directories (Polling Mode)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/user_mount_service.sh
Restart=always
RestartSec=5
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd, enable, and start the service
    sudo systemctl daemon-reload
    sudo systemctl enable user-mount.service
    sudo systemctl start user-mount.service

fi


###### LIMIT CORES PER USER ######

SLICE_NAME="custom.slice"
SLICE_FILE="/etc/systemd/system/$SLICE_NAME"

# Create or update the slice configuration file
echo "[Slice]
CPUQuota=${CPU_LIMIT}%" | sudo tee "$SLICE_FILE" > /dev/null

# Reload systemd to apply changes
sudo systemctl daemon-reload
sudo systemctl restart systemd-logind.service

# Verify the slice configuration
echo "Slice configuration applied. Checking status..."
systemctl show "$SLICE_NAME" | grep CPUQuota


##### DISABLE UBUNTU UPDATE PROMPTS #####
sudo sed -i 's/^Prompt=.*$/Prompt=never/' /etc/update-manager/release-upgrades

