#!/usr/bin/env bash
set -euo pipefail

# make sure apt never prompts
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Pre-seed needrestart config to never prompt (if installed)
CONFIG_FILE="/etc/needrestart/needrestart.conf"
TEMP_FILE="$(mktemp)"

if command -v needrestart >/dev/null 2>&1; then
  if [[ -f "$CONFIG_FILE" ]]; then
    sudo sed -i "s|^#*\$nrconf{restart} = .*;|\$nrconf{restart} = 'a';|" "$CONFIG_FILE"
    echo "Updated $CONFIG_FILE to set \$nrconf{restart} = 'a';"
  else
    echo "\$nrconf{restart} = 'a';" | sudo tee "$CONFIG_FILE"
    echo "Created $CONFIG_FILE to set \$nrconf{restart} = 'a';"
  fi
fi

echo "==> Disabling nginx service if present..."
if systemctl list-unit-files | grep -q '^nginx.service'; then
  sudo systemctl disable --now nginx.service || true
  echo "==> nginx.service disabled"
else
  echo "==> nginx.service not found, skipping"
fi

echo "==> Checking CPU hardware virtualization support..."
if ! egrep '(vmx|svm)' /proc/cpuinfo >/dev/null; then
  cat <<'EOF'

🚨  ERROR: No CPU virtualization support detected (no vmx/svm flags)  
    Your machine cannot run Docker’s virtualization-based components.  

    Consider provisioning a cloud VM that supports hardware virtualization:
      • Azure: Standard_D2s_v3, Standard_D4s_v3  
      • AWS  : t3.medium, m5.large  

EOF
  exit 1
fi

echo "==> Removing any older Docker packages (if installed)..."
sudo apt-get remove -y docker docker-engine docker.io containerd runc curl || true

echo "==> Updating apt package index..."
sudo apt-get update -y

echo "==> Installing prerequisites..."
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    --option=Dpkg::Options::="--force-confdef" \
    --option=Dpkg::Options::="--force-confold"

echo "==> Creating keyrings directory..."
sudo mkdir -m 0755 -p /etc/apt/keyrings

echo "==> Cleaning old Docker GPG key (if any)..."
sudo rm -f /etc/apt/keyrings/docker.gpg

echo "==> Downloading Docker’s official GPG key and adding it to keyrings..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg

echo "==> Setting up the Docker apt repository..."
sudo tee /etc/apt/sources.list.d/docker.list >/dev/null <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable
EOF

echo "==> Updating apt package index (again)..."
sudo apt-get update -y

echo "==> Installing Docker Engine, CLI, containerd, Buildx & Compose plugin..."
sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    --option=Dpkg::Options::="--force-confdef" \
    --option=Dpkg::Options::="--force-confold"

echo "==> Verifying Docker installation..."
sudo docker --version
sudo docker compose version

echo "==> Checking Docker service status..."
sudo systemctl status docker --no-pager

echo "Docker should now be installed and running."

##############################################################################
# Post-install: clone & build ISARD VDI
##############################################################################

echo
echo "⚠️  Reminder: Docker commands below require 'sudo' if your user isn't in the docker group."
echo

echo "==> Cloning isardvdi repository..."
git clone https://gitlab.com/isard/isardvdi

echo "==> Entering repository..."
cd isardvdi

echo "==> Copying example config..."
cp isardvdi.cfg.example isardvdi.cfg

echo "==> Configuring isardvdi.cfg..."
PUBLIC_IP=$(curl -fsSL http://checkip.amazonaws.com) 
sed -i "s|^DOMAIN=.*|DOMAIN=${PUBLIC_IP}|" isardvdi.cfg
sed -i "s|^WEBAPP_ADMIN_PWD=.*|WEBAPP_ADMIN_PWD=HeidiVDIApp|" isardvdi.cfg

echo "==> Running build script..."
./build.sh

# ──────────────────────────────────────────────────────────────────────────────
echo "==> Patching isard-grafana-agent entrypoint (scoped)…"

sed -i '/^  isard-grafana-agent:/,/^  [^ ]/ { /^[[:space:]]*entrypoint:/,+1d }' docker-compose.yml

sed -i '/^  isard-grafana-agent:/,/^  [^ ]/ { /^[[:space:]]*container_name: isard-grafana-agent/a\
    entrypoint:\
      - sh\
      - -c\
      - |\
        chmod +x /run.sh && exec /run.sh
}' docker-compose.yml

echo "==> Patching Loki bind mount…"
sed -i '/- type: bind/{ 
  N
  /source: \/docker\/loki\/config.yaml/{
    # pull in the next 3 lines (target, bind:, create_host_path)
    N
    N
    N
    # now replace the entire 5-line chunk
    c\
      - type: bind\
        source: /docker/loki\
        target: /etc/loki\
        bind:\
          create_host_path: true
  }
}' docker-compose.yml

echo "==> Patching Prometheus bind mount (cleanup stray lines)…"
sed -i '/- type: bind/{
  N
  /prometheus.yml/{
    N
    N
    N
    c\
      - type: bind\
        source: /docker/prometheus\
        target: /etc/prometheus\
        bind:\
          create_host_path: true
  }
}' docker-compose.yml

# ──────────────────────────────────────────────────────────────────────────────

echo "==> Pulling & starting containers..."
sudo docker compose pull
sudo docker compose up -d

echo
echo "ISARD VDI up and running."

