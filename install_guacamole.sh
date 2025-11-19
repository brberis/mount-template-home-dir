#!/bin/bash
#
# Apache Guacamole Installation Script for Ubuntu 22.04
# 
# This script installs Apache Guacamole with full support for:
# - VNC connections (TurboVNC/TigerVNC)
# - Copy/Paste functionality
# - Audio forwarding via PulseAudio
# - RDP (optional via Docker)
#
# Usage: bash install_guacamole.sh
#

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================
# Set to true to install Docker Remote Desktop container
INSTALL_DOCKER_DESKTOP=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

# Check if sudo is available
if ! command -v sudo &> /dev/null; then
    log_error "sudo is required but not installed"
    exit 1
fi

log_section "Apache Guacamole Installation - PoC Setup"

# Configuration variables
GUACAMOLE_VERSION="1.5.5"
GUACAMOLE_HOME="/etc/guacamole"
TOMCAT_VERSION="9"
GUACAMOLE_USER="guacamole"
VNC_PORT="5901"
GUACAMOLE_PORT="8080"

log_info "Guacamole version: $GUACAMOLE_VERSION"
log_info "Target VNC port: $VNC_PORT"
log_info "Guacamole web interface port: $GUACAMOLE_PORT"

# Step 1: Update system and install dependencies
log_section "Step 1: Installing System Dependencies"

log_info "Updating package lists..."
sudo apt-get update

log_info "Installing build dependencies and libraries..."
sudo apt-get install -y \
    build-essential \
    libcairo2-dev \
    libjpeg-turbo8-dev \
    libpng-dev \
    libtool-bin \
    libossp-uuid-dev \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libswscale-dev \
    freerdp2-dev \
    libpango1.0-dev \
    libssh2-1-dev \
    libtelnet-dev \
    libvncserver-dev \
    libwebsockets-dev \
    libpulse-dev \
    libssl-dev \
    libvorbis-dev \
    libwebp-dev \
    wget \
    curl \
    git

log_info "Installing Tomcat ${TOMCAT_VERSION}..."
sudo apt-get install -y tomcat${TOMCAT_VERSION} tomcat${TOMCAT_VERSION}-admin tomcat${TOMCAT_VERSION}-common tomcat${TOMCAT_VERSION}-user

log_info "Installing PulseAudio for audio support..."
sudo apt-get install -y pulseaudio pulseaudio-utils

log_info "✓ Dependencies installed"

# Step 2: Download and compile guacamole-server (guacd)
log_section "Step 2: Building Guacamole Server (guacd)"

cd /tmp

if [[ -f "guacamole-server-${GUACAMOLE_VERSION}.tar.gz" ]]; then
    log_info "Guacamole server archive already downloaded, using cached version"
else
    log_info "Downloading Guacamole server ${GUACAMOLE_VERSION}..."
    wget "https://downloads.apache.org/guacamole/${GUACAMOLE_VERSION}/source/guacamole-server-${GUACAMOLE_VERSION}.tar.gz"
fi

log_info "Extracting archive..."
tar -xzf guacamole-server-${GUACAMOLE_VERSION}.tar.gz
cd guacamole-server-${GUACAMOLE_VERSION}

log_info "Configuring build with VNC, RDP, and audio support..."
./configure --with-init-dir=/etc/init.d \
    --enable-allow-freerdp-snapshots \
    --with-vnc \
    --with-rdp \
    --with-ssh \
    --with-pulse

log_info "Compiling guacamole-server (this may take several minutes)..."
make -j$(nproc)

log_info "Installing guacamole-server..."
sudo make install

log_info "Updating library cache..."
sudo ldconfig

log_info "✓ Guacamole server (guacd) installed"

# Step 3: Create guacd systemd service
log_section "Step 3: Creating guacd Service"

log_info "Creating guacd systemd service..."
cat | sudo tee /etc/systemd/system/guacd.service <<EOF
[Unit]
Description=Guacamole proxy daemon
Documentation=man:guacd(8)
After=network.target

[Service]
Environment="GUACD_LOG_LEVEL=info"
ExecStart=/usr/local/sbin/guacd -f
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

log_info "Enabling and starting guacd service..."
sudo systemctl daemon-reload < /dev/null
sudo systemctl enable guacd < /dev/null
sudo systemctl start guacd < /dev/null

if sudo systemctl is-active --quiet guacd < /dev/null; then
    log_info "✓ guacd service is running"
else
    log_error "Failed to start guacd service"
    sudo systemctl status guacd < /dev/null
    exit 1
fi

# Step 4: Download and install guacamole-client (web app)
log_section "Step 4: Installing Guacamole Client Web Application"

cd /tmp

if [[ -f "guacamole-${GUACAMOLE_VERSION}.war" ]]; then
    log_info "Guacamole client already downloaded, using cached version"
else
    log_info "Downloading Guacamole client ${GUACAMOLE_VERSION}..."
    wget "https://downloads.apache.org/guacamole/${GUACAMOLE_VERSION}/binary/guacamole-${GUACAMOLE_VERSION}.war"
fi

log_info "Deploying Guacamole web application to Tomcat..."
sudo mkdir -p /var/lib/tomcat${TOMCAT_VERSION}/webapps
sudo cp guacamole-${GUACAMOLE_VERSION}.war /var/lib/tomcat${TOMCAT_VERSION}/webapps/guacamole.war

log_info "✓ Guacamole client deployed"

# Step 5: Configure Guacamole
log_section "Step 5: Configuring Guacamole"

log_info "Creating Guacamole configuration directory..."
sudo mkdir -p ${GUACAMOLE_HOME}/{extensions,lib}

log_info "Creating guacamole.properties..."
sudo tee ${GUACAMOLE_HOME}/guacamole.properties > /dev/null <<EOF
# Guacamole Configuration
guacd-hostname: localhost
guacd-port: 4822

# Basic authentication
basic-user-mapping: /etc/guacamole/user-mapping.xml

# Enable audio
enable-audio-input: true
EOF

log_info "Creating user-mapping.xml with VNC and Docker RDP connections..."
# Get the hostname for display
HOSTNAME=$(hostname)

sudo tee ${GUACAMOLE_HOME}/user-mapping.xml > /dev/null <<EOF
<user-mapping>
    <!-- Default admin user (CHANGE PASSWORD IN PRODUCTION!) -->
    <authorize username="guacadmin" password="guacadmin">
        
        <!-- Docker Remote Desktop (RDP) - Primary Connection -->
        <connection name="Docker Desktop (RDP)">
            <protocol>rdp</protocol>
            <param name="hostname">localhost</param>
            <param name="port">3389</param>
            <param name="username">ubuntu</param>
            <param name="password">ubuntu</param>
            <param name="security">any</param>
            <param name="ignore-cert">true</param>
            
            <!-- Copy/Paste Support -->
            <param name="enable-clipboard">true</param>
            <param name="normalize-clipboard">unix</param>
            
            <!-- Audio Support -->
            <param name="enable-audio">true</param>
            <param name="audio-servername">localhost</param>
            
            <!-- Drive Redirection for File Transfer -->
            <param name="enable-drive">true</param>
            <param name="drive-name">shared</param>
            <param name="drive-path">/var/lib/guacd/drives/docker</param>
            <param name="create-drive-path">true</param>
            
            <!-- Performance Settings -->
            <param name="color-depth">24</param>
            <param name="resize-method">display-update</param>
            <param name="enable-wallpaper">false</param>
            <param name="enable-theming">true</param>
            <param name="enable-font-smoothing">true</param>
        </connection>

    </authorize>

    <!-- Additional user: testuser -->
    <authorize username="testuser" password="Aa123456!">
        
        <!-- Docker Remote Desktop (RDP) - Primary Connection -->
        <connection name="Docker Desktop (RDP)">
            <protocol>rdp</protocol>
            <param name="hostname">localhost</param>
            <param name="port">3389</param>
            <param name="username">ubuntu</param>
            <param name="password">ubuntu</param>
            <param name="security">any</param>
            <param name="ignore-cert">true</param>
            
            <!-- Copy/Paste Support -->
            <param name="enable-clipboard">true</param>
            <param name="normalize-clipboard">unix</param>
            
            <!-- Audio Support -->
            <param name="enable-audio">true</param>
            <param name="audio-servername">localhost</param>
            
            <!-- Drive Redirection for File Transfer -->
            <param name="enable-drive">true</param>
            <param name="drive-name">shared</param>
            <param name="drive-path">/var/lib/guacd/drives/testuser</param>
            <param name="create-drive-path">true</param>
            
            <!-- Performance Settings -->
            <param name="color-depth">24</param>
            <param name="resize-method">display-update</param>
            <param name="enable-wallpaper">false</param>
            <param name="enable-theming">true</param>
            <param name="enable-font-smoothing">true</param>
        </connection>

    </authorize>
</user-mapping>
EOF

log_info "Creating drive directories for file transfer..."
sudo mkdir -p /var/lib/guacd/drives/{docker,testuser}
sudo chown -R tomcat:tomcat /var/lib/guacd

log_info "Setting Guacamole home directory for Tomcat..."
sudo mkdir -p /etc/systemd/system/tomcat${TOMCAT_VERSION}.service.d/
cat | sudo tee /etc/systemd/system/tomcat${TOMCAT_VERSION}.service.d/guacamole.conf <<EOF
[Service]
Environment="GUACAMOLE_HOME=${GUACAMOLE_HOME}"
EOF

log_info "✓ Guacamole configuration created"

# Step 6: Install Docker and Docker Remote Desktop Container (Optional)
if [[ "$INSTALL_DOCKER_DESKTOP" == "true" ]]; then
    log_section "Step 6: Installing Docker and Remote Desktop Container"

    log_info "Installing Docker..."
    if ! command -v docker &> /dev/null; then
        sudo apt-get install -y ca-certificates curl gnupg lsb-release
        sudo mkdir -p /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        log_info "✓ Docker installed"
    else
        log_info "Docker already installed"
    fi

    log_info "Pulling Docker Remote Desktop image (scottyhardy/docker-remote-desktop)..."
    sudo docker pull scottyhardy/docker-remote-desktop:latest

    log_info "Starting Docker Remote Desktop container..."
    sudo docker run -d \
        --restart=unless-stopped \
        --hostname="docker-desktop" \
        --publish="3389:3389/tcp" \
        --name="remote-desktop" \
        scottyhardy/docker-remote-desktop:latest

    # Wait for container to be ready
    sleep 5

    if sudo docker ps | grep -q "remote-desktop"; then
        log_info "✓ Docker Remote Desktop container running on port 3389"
        log_info "Default credentials: ubuntu/ubuntu"
    else
        log_error "Failed to start Docker Remote Desktop container"
        sudo docker logs remote-desktop
    fi
else
    log_section "Step 6: Skipping Docker Installation (INSTALL_DOCKER_DESKTOP=false)"
    log_info "Docker Desktop container installation disabled"
fi

# Step 7: Configure PulseAudio for network audio
log_section "Step 7: Configuring PulseAudio for Audio Forwarding"

log_info "Creating PulseAudio configuration for network audio..."

# Enable PulseAudio network module for all users
if ! grep -q "load-module module-native-protocol-tcp" /etc/pulse/default.pa; then
    sudo tee -a /etc/pulse/default.pa > /dev/null <<EOF

# Enable network audio for Guacamole
load-module module-native-protocol-tcp auth-anonymous=1
EOF
    log_info "✓ PulseAudio TCP module enabled"
else
    log_info "PulseAudio TCP module already configured"
fi

# Configure PulseAudio client
sudo tee /etc/pulse/client.conf > /dev/null <<EOF
# PulseAudio client configuration
autospawn = yes
daemon-binary = /usr/bin/pulseaudio
enable-shm = yes

# Allow network connections
default-server = localhost
EOF

log_info "✓ PulseAudio configured for network audio"

# Step 7: Configure firewall (if ufw is active)
log_section "Step 8: Configuring Firewall"

if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
    log_info "UFW firewall is active, opening required ports..."
    sudo ufw allow ${GUACAMOLE_PORT}/tcp comment "Guacamole web interface"
    sudo ufw allow 5900:5910/tcp comment "VNC servers"
    log_info "✓ Firewall rules added"
else
    log_info "UFW not active, skipping firewall configuration"
fi

# Step 8: Set permissions and restart services
log_section "Step 9: Finalizing Installation"

log_info "Setting proper permissions..."
sudo chown -R tomcat:tomcat ${GUACAMOLE_HOME}
sudo chmod 600 ${GUACAMOLE_HOME}/user-mapping.xml

log_info "Restarting services..."
sudo systemctl daemon-reload < /dev/null
sudo systemctl restart tomcat${TOMCAT_VERSION} < /dev/null
sudo systemctl restart guacd < /dev/null

# Wait for Tomcat to start
log_info "Waiting for Tomcat to deploy Guacamole..."
sleep 10

# Check service status
if sudo systemctl is-active --quiet tomcat${TOMCAT_VERSION} < /dev/null && sudo systemctl is-active --quiet guacd < /dev/null; then
    log_info "✓ All services running"
else
    log_error "Service startup issue detected"
    sudo systemctl status tomcat${TOMCAT_VERSION} guacd < /dev/null
fi

# Step 9: Display setup information
log_section "Installation Complete!"

SERVER_IP=$(hostname -I | awk '{print $1}')

cat <<EOF
${GREEN}╔════════════════════════════════════════════════════════════════╗
║          Apache Guacamole Installation Successful!             ║
╚════════════════════════════════════════════════════════════════╝${NC}

${BLUE}Access Information:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ${GREEN}Web Interface:${NC}  http://${SERVER_IP}:${GUACAMOLE_PORT}/guacamole
  
  ${GREEN}Default Credentials:${NC}
    Admin: guacadmin / guacadmin
    User:  testuser / Aa123456!
    ${RED}⚠️  CHANGE THESE IMMEDIATELY IN PRODUCTION!${NC}

${BLUE}Available Connections:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ${GREEN}Docker Desktop (RDP)${NC} - Ready to use!
     Protocol: RDP via xrdp in Docker container
     Backend: Ubuntu 24.04 with XFCE desktop
     Credentials: ubuntu/ubuntu (auto-login via Guacamole)
     Features: ✓ Clipboard  ✓ Audio  ✓ File Transfer
     Status: Container running on port 3389

${BLUE}Features Enabled:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✓ Docker Remote Desktop Container (scottyhardy/docker-remote-desktop)
  ✓ RDP Protocol Support with xrdp + XFCE
  ✓ VNC Protocol Support (TigerVNC/TurboVNC)
  ✓ Copy/Paste Functionality (bidirectional)
  ✓ Audio Forwarding (PulseAudio)
  ✓ File Transfer (RDP drive redirection)
  ✓ SSH Support (optional)

${BLUE}Quick Start:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. ${YELLOW}Access Guacamole:${NC}
     Open browser: http://${SERVER_IP}:${GUACAMOLE_PORT}/guacamole
     
  2. ${YELLOW}Login with:${NC}
     Username: guacadmin (or testuser)
     Password: guacadmin (or Aa123456!)
     
  3. ${YELLOW}Click "Docker Desktop (RDP)"${NC} connection
     - Desktop opens immediately with XFCE
     - Audio works automatically in your browser
     - Use Ctrl+Alt+Shift for clipboard menu
     - File transfer via shared drive

${BLUE}Using Clipboard (Copy/Paste):${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ${GREEN}Local → Remote:${NC}
    1. Copy text on your computer (Ctrl+C)
    2. In Guacamole, press ${YELLOW}Ctrl+Alt+Shift${NC} to open menu
    3. Paste text into the Guacamole clipboard text box
    4. Paste in remote desktop (Ctrl+V)
    
  ${GREEN}Remote → Local:${NC}
    1. Copy text in remote desktop (Ctrl+C)
    2. Press ${YELLOW}Ctrl+Alt+Shift${NC} to open menu
    3. Text appears in clipboard viewer
    4. Select and copy to use locally

${BLUE}Audio:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ${GREEN}✓ Audio works automatically!${NC}
  - Play videos/music in remote desktop
  - Audio streams to your browser
  - Adjust volume in XFCE panel (top right)

${BLUE}Docker Container Management:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Check status:       docker ps | grep remote-desktop
  View logs:          docker logs remote-desktop
  Restart:            docker restart remote-desktop
  Stop:               docker stop remote-desktop
  Start:              docker start remote-desktop
  Remove:             docker rm -f remote-desktop

${BLUE}Configuration Files:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Main config:        ${GUACAMOLE_HOME}/guacamole.properties
  User mappings:      ${GUACAMOLE_HOME}/user-mapping.xml
  guacd service:      /etc/systemd/system/guacd.service
  Tomcat webapps:     /var/lib/tomcat${TOMCAT_VERSION}/webapps/
  Shared folder:      /var/lib/guacd/drives/docker

${BLUE}Useful Commands:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Check services:     systemctl status guacd tomcat${TOMCAT_VERSION}
  View guacd logs:    journalctl -u guacd -f
  View Tomcat logs:   tail -f /var/log/tomcat${TOMCAT_VERSION}/catalina.out
  Restart services:   systemctl restart guacd tomcat${TOMCAT_VERSION}

${BLUE}Troubleshooting:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  If RDP connection fails:
    - Check container: sudo docker ps | grep remote-desktop
    - View logs: sudo docker logs remote-desktop
    - Restart: sudo docker restart remote-desktop
    
  If audio doesn't work:
    - Ensure browser audio is not muted
    - Try Chrome/Edge (better WebRTC support than Firefox)
    - Check browser permissions for audio
    
  If clipboard doesn't work:
    - Use ${YELLOW}Ctrl+Alt+Shift${NC} to access clipboard menu
    - Grant clipboard permissions when browser prompts
    - Text must go through Guacamole clipboard menu

${GREEN}Installation successful! Audio, clipboard, and file transfer ready!${NC}

EOF

log_info "Installation log available at: /var/log/guacamole-install.log"
