#!/bin/bash

# This script creates a Jupyter Lab launcher with a desktop icon
# It compiles a C program that launches Jupyter Lab inside a Singularity container
# Designed to be run as root or with sudo privileges on Ubuntu 22.04 or similar

set -e  # Exit immediately if a command exits with a non-zero status

##### GLOBAL VARIABLES #####

echo "=== Setting global variables... ==="

# Define the target template user where the template directory is located
TARGET_USER="mdcadmin1"

# Persistent storage for users VM Public IP
PERSISTENT_STORAGE_SERVICE_IP="10.53.0.15"

# Path to the Singularity image
SINGULARITY_IMAGE="/e4sonpremvm/E4S/24.02/e4s-cuda80-x86_64-24.11.sif"

##### CONFIGURE PACKAGE MANAGER #####

echo "=== Configuring needrestart ==="

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Pre-seed needrestart config to never prompt (if installed)
CONFIG_FILE="/etc/needrestart/needrestart.conf"

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

##### CREATE JUPYTER LAB LAUNCHER #####

echo "=== Creating Jupyter Lab launcher... ==="

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
    echo "GCC is not installed. Installing..."
    sudo apt update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    sudo apt install -y gcc -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
fi

# Ensure Singularity is installed
if ! command -v singularity &> /dev/null; then
    echo "Error: Singularity is not installed. Please install it before running this script."
    exit 1
fi

# Ensure zenity is installed (for the loading dialog)
if ! command -v zenity &> /dev/null; then
    echo "zenity is not installed. Installing..."
    sudo apt update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    sudo apt install -y zenity -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
fi

# Create the C program
cat <<EOF > "$C_FILE"
#include <stdlib.h>
#include <unistd.h>

int main() {
    // Show a "Loading..." dialog with no OK button
    system("zenity --progress --pulsate --text='Loading Jupyter Lab... Please wait.' --no-cancel --timeout=10 --width=500 &");

    // Execute the Singularity command with correct user home
    return system("singularity exec --nv $SINGULARITY_IMAGE bash -c \"cd && jupyter-lab\"");
}
EOF

# Compile the C program with sudo so it can write to /usr/local/bin
echo "Compiling launcher..."
sudo gcc -o "$BIN_PATH" "$C_FILE"

# Ensure the binary is executable and properly owned
sudo chmod +x "$BIN_PATH"
sudo chown root:root "$BIN_PATH"

echo "Binary created at $BIN_PATH"

# Create icons directory if it doesn't exist
sudo mkdir -p "$ICON_DIR"

# Download Jupyter icon if it doesn't exist
if [ ! -f "$ICON_PATH" ]; then
    echo "Downloading Jupyter icon..."
    sudo wget -q --show-progress -O "$ICON_PATH" "$ICON_URL"
    echo "Icon downloaded to $ICON_PATH"
else
    echo "Jupyter icon already exists at $ICON_PATH"
fi

# Ensure correct ownership of icon
sudo chmod 644 "$ICON_PATH"

# Create a .desktop file for Ubuntu UI
echo "Creating desktop entry..."
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

# Refresh Ubuntu's application database
sudo update-desktop-database "/usr/share/applications"

echo "=== Jupyter Lab launcher created successfully! ==="
echo "Application should now appear in your applications menu as 'Jupyter Lab'"
echo "You can also run it directly with: $BIN_PATH"
