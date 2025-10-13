#!/bin/bash

# Ckecking if it's head node
if compgen -G "/opt/noVNC*" > /dev/null; then
  echo "...Head node detected..."
else
  echo "...Worker node detected..."
  exit 0
fi

echo "Installing ClassifyX components..."

sudo apt update
sudo apt install curl -y
sudo apt install docker.io -y

sudo curl -L "https://github.com/docker/compose/releases/download/v2.18.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

sudo chmod +x /usr/local/bin/docker-compose

sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

### NVIDIA DRIVER INSTALLATION IF DETECTED ###

set -e  # Exit immediately if a command exits with a non-zero status
export DEBIAN_FRONTEND=noninteractive

echo "Checking for NVIDIA GPU..."
if lspci | grep -i nvidia &>/dev/null; then
    echo "NVIDIA GPU detected."
    echo "Checking if NVIDIA driver is already installed..."
    if nvidia-smi &>/dev/null; then
        echo "NVIDIA driver is already installed and active."
    else
        echo "NVIDIA driver not detected or not active. Proceeding with installation..."
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
        # Remove any existing NVIDIA drivers and conflicting packages
        echo "Removing existing NVIDIA drivers and conflicting packages..."
        sudo apt purge -y 'nvidia-*' 'libnvidia-*' || true
        sudo apt autoremove -y
        sudo apt autoclean -y
        # Clear any held packages
        sudo apt-mark unhold nvidia-* libnvidia-* || true
        # Update package cache
        sudo apt update -y
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
        # Remove and load necessary kernel modules
        sudo modprobe -r nouveau || true
        sudo modprobe nvidia || true
        # Restart GPU manager
        sudo systemctl restart gpu-manager || echo "GPU manager restart failed, continuing."
        echo "NVIDIA driver installation complete!"
    fi
    # Verify NVIDIA driver
    echo "Verifying NVIDIA driver installation..."
    if nvidia-smi &>/dev/null; then
        echo "NVIDIA driver is active."
        # Enable NVIDIA persistence mode (optional)
        sudo nvidia-smi -pm 1
        # Disable MIG
        sudo nvidia-smi -mig 0
    else
        echo "Failed to activate NVIDIA driver. Ensure installation was successful."
    fi
else
    echo "No NVIDIA GPU detected. Skipping NVIDIA driver installation and configurations."
fi

# Function to print status messages
echo_status() {
    echo -e "\e[1;32m$1\e[0m"
}

###### INSTALL NVIDIA DOCKER TOOLKIT ######

echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
sleep 5
sudo apt-get update
sudo systemctl restart docker
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker



###### FIX FIREFOX ######

echo_status "Removing Snap version of Firefox..."
sudo snap remove firefox

echo_status "Clearing Snap cache..."
sudo rm -rf /var/cache/snapd

echo_status "Creating APT preferences to prioritize PPA version..."
echo -e 'Package: firefox*\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 501' | sudo tee /etc/apt/preferences.d/mozilla-firefox

echo_status "Purging any existing Firefox package..."

if dpkg -l | grep -q '^ii\s\+firefox'; then
    sudo apt purge -y --allow-change-held-packages firefox
    sudo apt purge -y firefox
else
    echo "Firefox is not installed; skipping purge."
fi

echo_status "Adding Mozilla PPA..."
sudo add-apt-repository -y ppa:mozillateam/ppa

echo_status "Updating package lists..."
sudo apt update

echo_status "Checking available Firefox versions..."
apt policy firefox

echo_status "Installing Firefox from Mozilla PPA..."
sudo apt install -y firefox

echo_status "Verifying Firefox installation..."
which firefox && firefox --version

echo_status "Marking Firefox package to prevent auto-update to Snap version..."
sudo apt-mark hold firefox

echo_status "Firefox installation completed successfully."



###### INSTALL CLASSIFYX ######

sudo mkdir -p /opt/classifyx/
SECRET_KEY=$(openssl rand -base64 48)
# Detect the private IP of the machine
PRIVATE_IP=$(hostname -I | awk '{print $1}')

# Create the .env.prod file with the secret key and private IP 
sudo tee /opt/classifyx/.env.prod > /dev/null << EOF
DEBUG=0
SECRET_KEY=$SECRET_KEY
DJANGO_ALLOWED_HOSTS=localhost 127.0.0.1 [::1] backend $PRIVATE_IP
NEXT_PUBLIC_API_BASE_URL=http://$PRIVATE_IP:3000
NEXT_PUBLIC_DJANGO_API_BASE_URL=http://$PRIVATE_IP:8700
DJANGO_API_BASE_URL=http://$PRIVATE_IP:8700
SQL_ENGINE=django.db.backends.postgresql
SQL_DATABASE=backend_prod
SQL_USER=backend
SQL_PASSWORD=backend
SQL_HOST=db
SQL_PORT=5432
DATABASE=postgres
ORIGIN=http://$PRIVATE_IP:3001
EOF

detect_nvidia_gpu() {
    if lspci | grep -i nvidia &>/dev/null; then
        if nvidia-smi &>/dev/null; then
            return 0  # True: GPU detected and driver active
        fi
    fi
    return 1  # False: No GPU or driver not active
}

# Check for NVIDIA GPU and set variables accordingly
echo "Checking for NVIDIA GPU..."
if detect_nvidia_gpu; then
    echo "NVIDIA GPU detected and driver is active."
    # GPU-specific deploy section
    GPU_DEPLOY="deploy:
      resources:
        limits:
          memory: 8g
        reservations:
          memory: 4g
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]"
    # GPU-specific environment variables
    GPU_ENV="
      - LD_LIBRARY_PATH=/usr/local/cuda/lib64:\$LD_LIBRARY_PATH
      - NVIDIA_VISIBLE_DEVICES=all
      - TF_FORCE_GPU_ALLOW_GROWTH=true
      - PATH=/usr/local/cuda/bin:\$PATH"
else
    echo "No NVIDIA GPU detected or driver not active."
    # Empty variables for no GPU
    GPU_DEPLOY=""
    GPU_ENV="
      - TF_FORCE_GPU_ALLOW_GROWTH=true"
fi

# Create the docker-compose.yml 
sudo tee /opt/classifyx/docker-compose.yml > /dev/null << EOF
services:
  backend:
    image: brberis/classifyx:backend
    command: /bin/sh -c "sleep 5 && 
                    python manage.py makemigrations --noinput &&
                    python manage.py migrate --noinput &&
                    python manage.py shell -c \"from django.contrib.auth.models import User; User.objects.filter(username='testuser').exists() or User.objects.create_superuser('testuser', 'testuser@example.com', 'testpassword')\" &&
                    python manage.py runserver 0.0.0.0:8700" 
    volumes:
      - logs_volume:/usr/src/app/logs
      - static_volume:/usr/src/app/staticfiles
      - media_volume:/usr/src/app/mediafiles
    ports:
      - "8700:8700"
    env_file:
      - ./.env.prod
    environment:
      - CELERY_BROKER_URL=redis://redis:6379/0
    depends_on:
      - db
      - redis
    networks:
      - backend

  db:
    image: brberis/classifyx:postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data/
    environment:
      - POSTGRES_USER=backend
      - POSTGRES_PASSWORD=backend
      - POSTGRES_DB=backend_prod
    networks:
      - backend
      
  redis:
    image: redis
    ports:
      - 6379:6379
    networks:
      - backend

  celery_worker:
    image: brberis/classifyx:celery_worker 
    command: >
      /bin/sh -c "celery -A celery_app worker --loglevel=info --max-tasks-per-child=1 2>&1 |
      stdbuf -oL sed -E 's#WARNING/ForkPoolWorker-[0-9]+ *##g' |
      tee /usr/src/app/logs/celery.log"
    env_file:
      - ./.env.prod
    depends_on:
      - db    
      - redis
    environment:
      - PYTHONUNBUFFERED=1
      - CELERYD_MAX_TASKS_PER_CHILD=1
      - CELERYD_TASK_TIME_LIMIT=3600 
      - CELERYD_TASK_SOFT_TIME_LIMIT=3500
      $GPU_ENV
    volumes:
      - logs_volume:/usr/src/app/logs
      - static_volume:/usr/src/app/staticfiles  
      - media_volume:/usr/src/app/mediafiles 
    $GPU_DEPLOY
    ipc: host
    ulimits:
      memlock:
        soft: -1
        hard: -1
      stack:
        soft: 67108864
        hard: 67108864
    networks:
      - backend
    restart: always

  frontend:
    image: brberis/classifyx:frontend
    command: npm run dev 
    ports:
      - "3001:3000"
    env_file:
      - ./.env.prod
    environment:
      - CHOKIDAR_USEPOLLING=true
    networks:
      - backend

volumes:
  logs_volume:
  postgres_data:
  static_volume:
  media_volume:

networks:
  backend:
    driver: bridge
EOF


# Install jq for JSON parsing
sudo apt-get update
sudo apt-get install -y jq

# Update daemon.json with DNS settings
sudo jq '. + { "dns": ["8.8.8.8", "8.8.4.4"] }' /etc/docker/daemon.json > daemon.json.tmp
sudo mv daemon.json.tmp /etc/docker/daemon.json

# Restart Docker to apply changes
sudo systemctl restart docker

sleep 5

for i in {1..3}; do
  sudo docker-compose -f /opt/classifyx/docker-compose.yml pull && break
  echo "Pull failed, retrying in 5 seconds..."
  sleep 5
done

# Start the containers
sudo docker-compose -f /opt/classifyx/docker-compose.yml up -d

###### INSTALL CLASSIFYX DESKTOP SHORTCUT ######

APP_NAME="calssifyx"
C_FILE="/tmp/$APP_NAME.c"
BIN_PATH="/usr/local/bin/$APP_NAME"
DESKTOP_FILE="/usr/share/applications/classifyx.desktop"
ICON_DIR="/usr/share/pixmaps/"
ICON_PATH="$ICON_DIR/classifyx_icon.png"
ICON_URL="https://raw.githubusercontent.com/brberis/djtensor/refs/heads/main/frontend/app/public/classifyx_logo.png"

if ! command -v gcc &> /dev/null; then
    echo "Error: GCC is not installed. Installing..."
    sudo apt update && sudo apt install -y gcc
fi

PRIVATE_IP=$(hostname -I | awk '{print $1}')
cat <<EOF > "$C_FILE"
#include <stdlib.h>
#include <unistd.h>

int main() {
    system("zenity --progress --pulsate --text='Loading ClassifyX... Please wait.' --no-cancel --timeout=10 --width=500 &");
    system("firefox http://${PRIVATE_IP}:3001 &");
    return 0;
}
EOF

sudo gcc -o "$BIN_PATH" "$C_FILE"

sudo chmod +x "$BIN_PATH"
sudo chown root:root "$BIN_PATH" 

sudo mkdir -p "$ICON_DIR"

if [ ! -f "$ICON_PATH" ]; then
    sudo wget -q --show-progress -O "$ICON_PATH" "$ICON_URL"
fi

sudo chmod 644 "$ICON_PATH"

sudo tee "$DESKTOP_FILE" > /dev/null <<EOF
[Desktop Entry]
Version=1.4
Type=Application
Name=ClassifyX
Comment=Open ClassifyX in Firefox
Exec=$BIN_PATH
Icon=$ICON_PATH
Terminal=false
Categories=Development;Science;
EOF

sudo chmod 644 "$DESKTOP_FILE"
sudo update-desktop-database "/usr/share/applications"
echo "ClassifyX has been installed successfully."

