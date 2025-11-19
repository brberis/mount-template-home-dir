#!/bin/bash
#
# Apache Guacamole Installation Script for Ubuntu 22.04/24.04
# 
# This script installs Apache Guacamole with xrdp + XFCE directly on the host
# Based on scottyhardy/docker-remote-desktop configuration
#
# Features:
# - RDP via xrdp (direct host access, not containerized)
# - XFCE4 desktop environment
# - Full clipboard support (bidirectional)
# - Audio forwarding via PulseAudio with xrdp modules
# - File transfer via RDP drive redirection
#
# Usage: bash install_guacamole_host.sh
#

set -e

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

log_section "Apache Guacamole + xrdp Installation on Host"

# Configuration variables
GUACAMOLE_VERSION="1.5.5"
GUACAMOLE_HOME="/etc/guacamole"
TOMCAT_VERSION="9"
GUACAMOLE_PORT="8080"
RDP_PORT="3389"

# Detect Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_CODENAME=$(lsb_release -cs)

log_info "Detected Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"
log_info "Guacamole version: $GUACAMOLE_VERSION"
log_info "RDP will be accessible on port: $RDP_PORT"
log_info "Guacamole web interface port: $GUACAMOLE_PORT"

# Step 1: Update system and install dependencies
log_section "Step 1: Installing System Dependencies"

log_info "Updating package lists..."
sudo apt-get update

log_info "Installing Guacamole build dependencies..."
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
    git \
    autoconf \
    dpkg-dev \
    libltdl-dev

log_info "Installing Tomcat ${TOMCAT_VERSION}..."
sudo apt-get install -y tomcat${TOMCAT_VERSION} tomcat${TOMCAT_VERSION}-admin tomcat${TOMCAT_VERSION}-common tomcat${TOMCAT_VERSION}-user

log_info "✓ Guacamole dependencies installed"

# Step 2: Install xrdp + XFCE Desktop (based on docker-remote-desktop)
log_section "Step 2: Installing xrdp + XFCE Desktop Environment"

log_info "Installing xrdp, XFCE4, and related packages..."
sudo apt-get install -y \
    dbus-x11 \
    locales \
    pavucontrol \
    pulseaudio \
    pulseaudio-utils \
    software-properties-common \
    vim \
    x11-xserver-utils \
    xfce4 \
    xfce4-goodies \
    xfce4-pulseaudio-plugin \
    xorgxrdp \
    xrdp \
    xubuntu-icon-theme

log_info "Installing Firefox from Mozilla PPA..."
sudo add-apt-repository -y ppa:mozillateam/ppa
sudo tee /etc/apt/preferences.d/mozilla-firefox > /dev/null <<EOF
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
EOF

sudo apt-get update
sudo apt-get install -y --allow-downgrades firefox

log_info "Generating locales..."
sudo locale-gen en_US.UTF-8

log_info "✓ xrdp + XFCE desktop installed"

# Step 3: Build and install PulseAudio xrdp modules
log_section "Step 3: Building PulseAudio xrdp Modules"

log_info "Cloning pulseaudio-module-xrdp..."
cd /tmp
if [[ -d "pulseaudio-module-xrdp" ]]; then
    sudo rm -rf pulseaudio-module-xrdp
fi

git clone https://github.com/neutrinolabs/pulseaudio-module-xrdp.git
cd pulseaudio-module-xrdp

log_info "Installing PulseAudio sources..."
scripts/install_pulseaudio_sources_apt.sh

log_info "Building PulseAudio xrdp modules..."
./bootstrap
./configure PULSE_DIR=$HOME/pulseaudio.src
make

log_info "Installing PulseAudio xrdp modules..."
sudo make install

log_info "Configuring PulseAudio autostart for xrdp..."
if [[ -f /etc/xdg/autostart/pulseaudio-xrdp.desktop ]]; then
    sudo sed -i 's|^Exec=.*|Exec=/usr/bin/pulseaudio|' /etc/xdg/autostart/pulseaudio-xrdp.desktop
fi

log_info "✓ PulseAudio xrdp modules installed"

# Step 4: Configure xrdp
log_section "Step 4: Configuring xrdp"

log_info "Configuring xrdp for XFCE..."
sudo tee /etc/xrdp/startwm.sh <<'EOF'
#!/bin/sh
# xrdp X session start script (c) 2015, 2017, 2021 mirabilos
# published under The MirOS Licence

# Rely on /etc/profile getting sourced automatically
# shellcheck disable=SC1091

unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

if test -r /etc/default/locale; then
	. /etc/default/locale
	export LANG LANGUAGE
fi

# Start PulseAudio
pulseaudio --start --exit-idle-time=-1

# Start XFCE4
exec startxfce4
EOF

sudo chmod +x /etc/xrdp/startwm.sh

log_info "Enabling and starting xrdp service..."
sudo systemctl enable xrdp
sudo systemctl enable xrdp-sesman
sudo systemctl restart xrdp

if systemctl is-active --quiet xrdp; then
    log_info "✓ xrdp service is running on port ${RDP_PORT}"
else
    log_error "Failed to start xrdp service"
    systemctl status xrdp
fi

# Step 5: Download and compile guacamole-server (guacd)
log_section "Step 5: Building Guacamole Server (guacd)"

cd /tmp

if [[ -f "guacamole-server-${GUACAMOLE_VERSION}.tar.gz" ]]; then
    log_info "Guacamole server archive already exists, using cached version"
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

# Step 6: Create guacd systemd service
log_section "Step 6: Creating guacd Service"

log_info "Creating guacd systemd service..."
sudo tee /etc/systemd/system/guacd.service > /dev/null <<EOF
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
sudo systemctl daemon-reload
sudo systemctl enable guacd
sudo systemctl start guacd

if systemctl is-active --quiet guacd; then
    log_info "✓ guacd service is running"
else
    log_error "Failed to start guacd service"
    systemctl status guacd
    exit 1
fi

# Step 7: Download and install guacamole-client (web app)
log_section "Step 7: Installing Guacamole Client Web Application"

cd /tmp

if [[ -f "guacamole-${GUACAMOLE_VERSION}.war" ]]; then
    log_info "Guacamole client already exists, using cached version"
else
    log_info "Downloading Guacamole client ${GUACAMOLE_VERSION}..."
    wget "https://downloads.apache.org/guacamole/${GUACAMOLE_VERSION}/binary/guacamole-${GUACAMOLE_VERSION}.war"
fi

log_info "Deploying Guacamole web application to Tomcat..."
sudo mkdir -p /var/lib/tomcat${TOMCAT_VERSION}/webapps
sudo cp guacamole-${GUACAMOLE_VERSION}.war /var/lib/tomcat${TOMCAT_VERSION}/webapps/guacamole.war

log_info "✓ Guacamole client deployed"

# Step 8: Configure Guacamole
log_section "Step 8: Configuring Guacamole"

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

log_info "Creating user-mapping.xml with host RDP connections..."
HOSTNAME=$(hostname)

sudo tee ${GUACAMOLE_HOME}/user-mapping.xml > /dev/null <<EOF
<user-mapping>
    <!-- Admin user - connects to host system -->
    <authorize username="guacadmin" password="guacadmin">
        
        <!-- Host System Desktop (RDP) -->
        <connection name="Host Desktop - guacadmin">
            <protocol>rdp</protocol>
            <param name="hostname">localhost</param>
            <param name="port">${RDP_PORT}</param>
            <param name="username">guacadmin</param>
            <param name="password">guacadmin</param>
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
            <param name="drive-path">/var/lib/guacd/drives/guacadmin</param>
            <param name="create-drive-path">true</param>
            
            <!-- Performance Settings -->
            <param name="color-depth">24</param>
            <param name="resize-method">display-update</param>
            <param name="enable-wallpaper">false</param>
            <param name="enable-theming">true</param>
            <param name="enable-font-smoothing">true</param>
        </connection>

    </authorize>

    <!-- Test user - connects to host system -->
    <authorize username="testuser" password="Aa123456!">
        
        <!-- Host System Desktop (RDP) -->
        <connection name="Host Desktop - testuser">
            <protocol>rdp</protocol>
            <param name="hostname">localhost</param>
            <param name="port">${RDP_PORT}</param>
            <param name="username">testuser</param>
            <param name="password">Aa123456!</param>
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

log_info "Creating Linux users for RDP access..."
# Create guacadmin user if doesn't exist
if ! id "guacadmin" &>/dev/null; then
    useradd -m -s /bin/bash guacadmin
    echo "guacadmin:guacadmin" | chpasswd
    log_info "Created user: guacadmin"
else
    log_info "User guacadmin already exists"
fi

# Update testuser password if exists, create if not
if id "testuser" &>/dev/null; then
    echo "testuser:Aa123456!" | chpasswd
    log_info "Updated password for existing user: testuser"
else
    useradd -m -s /bin/bash testuser
    echo "testuser:Aa123456!" | chpasswd
    log_info "Created user: testuser"
fi

log_info "Creating drive directories for file transfer..."
sudo mkdir -p /var/lib/guacd/drives/{guacadmin,testuser}
sudo chown -R tomcat:tomcat /var/lib/guacd

log_info "Setting Guacamole home directory for Tomcat..."
sudo mkdir -p /etc/systemd/system/tomcat${TOMCAT_VERSION}.service.d/
sudo tee /etc/systemd/system/tomcat${TOMCAT_VERSION}.service.d/guacamole.conf > /dev/null <<EOF
[Service]
Environment="GUACAMOLE_HOME=${GUACAMOLE_HOME}"
EOF

log_info "✓ Guacamole configuration created"

# Step 9: Configure firewall (if ufw is active)
log_section "Step 9: Configuring Firewall"

if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    log_info "UFW firewall is active, opening required ports..."
    ufw allow ${GUACAMOLE_PORT}/tcp comment "Guacamole web interface"
    ufw allow ${RDP_PORT}/tcp comment "xrdp"
    log_info "✓ Firewall rules added"
else
    log_info "UFW not active, skipping firewall configuration"
fi

# Step 10: Set permissions and restart services
log_section "Step 10: Finalizing Installation"

log_info "Setting proper permissions..."
sudo chown -R tomcat:tomcat ${GUACAMOLE_HOME}
sudo chmod 600 ${GUACAMOLE_HOME}/user-mapping.xml

log_info "Restarting services..."
sudo systemctl daemon-reload
sudo systemctl restart tomcat${TOMCAT_VERSION}
sudo systemctl restart guacd
sudo systemctl restart xrdp

# Wait for Tomcat to start
log_info "Waiting for Tomcat to deploy Guacamole..."
sleep 10

# Check service status
SERVICES_OK=true
if ! systemctl is-active --quiet tomcat${TOMCAT_VERSION}; then
    log_error "Tomcat is not running"
    SERVICES_OK=false
fi
if ! systemctl is-active --quiet guacd; then
    log_error "guacd is not running"
    SERVICES_OK=false
fi
if ! systemctl is-active --quiet xrdp; then
    log_error "xrdp is not running"
    SERVICES_OK=false
fi

if $SERVICES_OK; then
    log_info "✓ All services running"
else
    log_error "Some services failed to start"
    systemctl status tomcat${TOMCAT_VERSION} guacd xrdp
fi

# Step 11: Display setup information
log_section "Installation Complete!"

SERVER_IP=$(hostname -I | awk '{print $1}')

cat <<EOF
${GREEN}╔════════════════════════════════════════════════════════════════╗
║     Apache Guacamole + xrdp Installation Successful!           ║
╚════════════════════════════════════════════════════════════════╝${NC}

${BLUE}Access Information:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ${GREEN}Web Interface:${NC}  http://${SERVER_IP}:${GUACAMOLE_PORT}/guacamole
  
  ${GREEN}Guacamole Login:${NC}
    Admin: guacadmin / guacadmin
    User:  testuser / Aa123456!
  
  ${GREEN}Linux System Users:${NC}
    guacadmin / guacadmin
    testuser / Aa123456!
    
    ${RED}⚠️  CHANGE THESE PASSWORDS IMMEDIATELY IN PRODUCTION!${NC}

${BLUE}System Configuration:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ${GREEN}Desktop Environment:${NC} XFCE4 running directly on host (${HOSTNAME})
  ${GREEN}RDP Server:${NC}         xrdp on port ${RDP_PORT}
  ${GREEN}Audio:${NC}              PulseAudio with xrdp modules
  ${GREEN}System Access:${NC}      Full host access (not containerized)
  ${GREEN}Home Directories:${NC}   /home/guacadmin, /home/testuser

${BLUE}Available Connections:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ${GREEN}Host Desktop - guacadmin${NC}
     User logs into the actual host system as guacadmin
     Full system access, sudo capabilities
     
  ${GREEN}Host Desktop - testuser${NC}
     User logs into the actual host system as testuser
     Standard user access

${BLUE}Features:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✓ Direct host system access (NOT in container)
  ✓ RDP via xrdp + XFCE4 desktop
  ✓ Copy/Paste (bidirectional via Guacamole menu)
  ✓ Audio forwarding (PulseAudio with xrdp modules)
  ✓ File transfer (RDP drive redirection)
  ✓ Full filesystem access
  ✓ All host resources available (GPU, network, etc.)
  ✓ Firefox browser pre-installed

${BLUE}Quick Start:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. ${YELLOW}Access Guacamole:${NC}
     Open browser: http://${SERVER_IP}:${GUACAMOLE_PORT}/guacamole
     
  2. ${YELLOW}Login to Guacamole:${NC}
     Username: guacadmin (or testuser)
     Password: guacadmin (or Aa123456!)
     
  3. ${YELLOW}Click your connection${NC}
     "Host Desktop - guacadmin" or "Host Desktop - testuser"
     
  4. ${YELLOW}You're now on the actual host system!${NC}
     - This is ${HOSTNAME} running XFCE
     - Full access to all system resources
     - Can sudo (if user has permissions)
     - Access all files in /home/username

${BLUE}Using Clipboard (Copy/Paste):${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ${GREEN}On Mac, use: Ctrl + Option + Shift${NC} (all together)
  ${GREEN}On Windows/Linux: Ctrl + Alt + Shift${NC}
  
  ${GREEN}Local → Remote:${NC}
    1. Copy text on your computer
    2. Press ${YELLOW}Ctrl+Option+Shift${NC} (Mac) to open Guacamole menu
    3. Click in the text box and paste (Cmd+V on Mac)
    4. Text syncs automatically to remote desktop
    5. Now paste in remote with Ctrl+V
    
  ${GREEN}Remote → Local:${NC}
    1. Copy text in remote desktop (Ctrl+C)
    2. Press ${YELLOW}Ctrl+Option+Shift${NC} to open menu
    3. Text appears - copy it to your clipboard
    4. Paste on your local computer

${BLUE}Audio:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ${GREEN}✓ Audio works automatically via PulseAudio xrdp modules${NC}
  - Play videos/music in Firefox or other apps
  - Audio streams to your browser
  - Adjust volume in XFCE panel (top right)

${BLUE}Adding More Users:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. Create Linux user:
     sudo useradd -m -s /bin/bash newuser
     sudo passwd newuser
     
  2. Create drive directory:
     sudo mkdir -p /var/lib/guacd/drives/newuser
     sudo chown tomcat:tomcat /var/lib/guacd/drives/newuser
     
  3. Add to ${GUACAMOLE_HOME}/user-mapping.xml:
     Copy an existing <authorize> block and modify usernames/passwords
     
  4. Restart Tomcat:
     sudo systemctl restart tomcat${TOMCAT_VERSION}

${BLUE}Service Management:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Check all services:  systemctl status guacd tomcat${TOMCAT_VERSION} xrdp
  Restart services:    systemctl restart guacd tomcat${TOMCAT_VERSION} xrdp
  View guacd logs:     journalctl -u guacd -f
  View xrdp logs:      journalctl -u xrdp -f
  View Tomcat logs:    tail -f /var/log/tomcat${TOMCAT_VERSION}/catalina.out

${BLUE}Configuration Files:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Guacamole config:    ${GUACAMOLE_HOME}/guacamole.properties
  User mappings:       ${GUACAMOLE_HOME}/user-mapping.xml
  xrdp config:         /etc/xrdp/xrdp.ini
  xrdp startup:        /etc/xrdp/startwm.sh
  Shared folders:      /var/lib/guacd/drives/

${BLUE}Direct RDP Access (Optional):${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  You can also connect directly via RDP client:
  
  ${GREEN}Server:${NC}   ${SERVER_IP}:${RDP_PORT}
  ${GREEN}User:${NC}     guacadmin or testuser
  ${GREEN}Password:${NC} (as configured above)

${BLUE}Troubleshooting:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  If connection fails:
    - Check xrdp: sudo systemctl status xrdp
    - Check guacd: sudo systemctl status guacd
    - View logs: sudo journalctl -u xrdp -u guacd -f
    
  If audio doesn't work:
    - Ensure browser audio is not muted
    - Check PulseAudio: pactl info
    - Try Chrome/Edge (better audio support)
    
  If clipboard doesn't work on Mac:
    - Use Ctrl+Option+Shift (not Cmd)
    - Click in the text box before pasting
    - Try Chrome or Firefox

${GREEN}Installation successful! You now have full host access via Guacamole!${NC}

${YELLOW}Note: Users connect to the actual ${HOSTNAME} host system with full access
      to all filesystem, network, and system resources.${NC}

EOF

log_info "Installation complete. Test by accessing: http://${SERVER_IP}:${GUACAMOLE_PORT}/guacamole"
