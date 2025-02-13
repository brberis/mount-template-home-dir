#!/bin/bash
# This installation script can be run as a non-root user.
# It uses sudo where necessary.

# Install inotify-tools if not present
if ! command -v inotifywait &> /dev/null; then
    sudo apt update
    sudo apt install -y inotify-tools
fi

# Create the service script at /usr/local/bin/user_mount_service.sh
sudo tee /usr/local/bin/user_mount_service.sh > /dev/null << 'EOF'
#!/bin/bash
# user_mount_service.sh (Polling Version using fast copy)
# This version polls for new users and copies the template directory
# to the new userâs home. It uses tar to copy files and then fixes ownership.
#
# Configuration
TEMPLATE_DIR="/home/user"         # Directory to copy to each new user's home
IGNORE_USERS=("root" "ubuntu")    # Users to ignore (adjust as needed)
RETRIES=10                        # Number of times to check for a new user's home directory
WAIT_TIME=2                       # Seconds to wait between checks for home directory appearance
POLL_INTERVAL=10                  # Seconds between polls for new users

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
    local home_dir="$2"
    local retries=$RETRIES

    while [ $retries -gt 0 ]; do
        if [ -d "$home_dir" ]; then
            break
        else
            echo "[$(date)] Home directory '$home_dir' not found for user '$user'. Retrying in ${WAIT_TIME}s... ($retries left)"
            sleep $WAIT_TIME
            retries=$((retries - 1))
        fi
    done

    if [ ! -d "$home_dir" ]; then
        echo "[$(date)] ERROR: Home directory '$home_dir' still does not exist for user '$user' after retries. Skipping copy."
        return 1
    fi

    # Use tar to copy and force all files to be owned by $user.
    if tar cf - -C "$TEMPLATE_DIR" . | tar xf - --no-same-owner --no-same-permissions -C "$home_dir"; then
        chown -R "$user:$user" "$home_dir"
        echo "[$(date)] Successfully copied '$TEMPLATE_DIR' to '$home_dir' for user '$user'."
        return 0
    else
        echo "[$(date)] ERROR: Failed to copy '$TEMPLATE_DIR' to '$home_dir' for user '$user'."
        return 1
    fi
}

process_user() {
    local user="$1"
    local home_dir
    home_dir=$(getent passwd "$user" | cut -d: -f6)

    if [[ -z "$home_dir" || "$home_dir" != /home/* ]]; then
        echo "[$(date)] Skipping user '$user' because their home directory '$home_dir' is not in /home/."
        return 1
    fi

    echo "[$(date)] Processing user '$user' with home directory '$home_dir'."
    copy_template "$user" "$home_dir"
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

# Polling function to detect new users
poll_for_new_users() {
    local previous_users current_users new_users

    previous_users=$(awk -F: '{print $1}' /etc/passwd)
    echo "[$(date)] Starting polling for new users..."

    while true; do
        sleep "$POLL_INTERVAL"
        current_users=$(awk -F: '{print $1}' /etc/passwd)
        # Determine new users (requires sorted lists)
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
# Process existing users on startup
process_existing_users

# Now start polling for new users
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


### Fix Firefox ###

# Function to print status messages
echo_status() {
    echo -e "\e[1;32m$1\e[0m"
}

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
sudo apt update

# Step 7: Check if correct Firefox package is available
echo_status "Checking available Firefox versions..."
apt policy firefox

# Step 8: Install Firefox from the PPA
echo_status "Installing Firefox from Mozilla PPA..."
sudo apt install -y firefox

# Step 9: Verify installation
echo_status "Verifying Firefox installation..."
which firefox && firefox --version

# Step 10: Prevent Snap from reinstalling Firefox automatically
echo_status "Marking Firefox package to prevent auto-update to Snap version..."
sudo apt-mark hold firefox

echo_status "Firefox installation completed successfully."