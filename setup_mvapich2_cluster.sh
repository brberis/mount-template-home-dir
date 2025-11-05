#!/bin/bash
#
# MVAPICH2 Cluster Setup Script
# 
# This script installs and configures MVAPICH2 for multinode MPI jobs with Torque/PBS
# Run this on ALL nodes (head node and compute nodes)
#
# Usage: sudo bash setup_mvapich2_cluster.sh
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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

# Detect OS
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    log_error "Cannot detect OS"
    exit 1
fi

log_section "System Information"
log_info "OS: $OS $VER"
log_info "Hostname: $(hostname)"
log_info "Kernel: $(uname -r)"

# Detect node type
IS_HEADNODE=false
if [[ -f /NODUS/.is_headnode ]] || pgrep -x pbs_server >/dev/null 2>&1; then
    IS_HEADNODE=true
    log_info "Node Type: HEAD NODE"
else
    log_info "Node Type: COMPUTE NODE"
fi

###########################################
# STEP 1: Install Required Packages
###########################################

log_section "Installing Required Packages"

if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    
    log_info "Updating package lists..."
    apt-get update -y
    
    log_info "Installing development tools..."
    apt-get install -y \
        build-essential \
        gfortran \
        gcc \
        g++ \
        make \
        cmake \
        autoconf \
        automake \
        libtool \
        pkg-config \
        wget \
        curl \
        git \
        python3 \
        python3-dev \
        libibverbs-dev \
        librdmacm-dev \
        libibumad-dev \
        librdmacm1 \
        libibverbs1 \
        rdma-core \
        ibverbs-utils \
        infiniband-diags \
        openssh-server \
        openssh-client \
        libssl-dev \
        zlib1g-dev \
        libnuma-dev \
        numactl
    
    log_info "Checking for Mellanox OFED..."
    if ! command -v ibstat &> /dev/null; then
        log_warn "Mellanox OFED not detected. Installing basic RDMA tools."
    fi

elif [[ "$OS" == "rocky" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]]; then
    log_info "Installing development tools..."
    dnf groupinstall -y "Development Tools"
    dnf install -y \
        gcc \
        gcc-c++ \
        gcc-gfortran \
        make \
        cmake \
        autoconf \
        automake \
        libtool \
        wget \
        curl \
        git \
        python3 \
        python3-devel \
        rdma-core-devel \
        libibverbs \
        libibverbs-devel \
        librdmacm \
        librdmacm-devel \
        openssh-server \
        openssh-clients \
        openssl-devel \
        zlib-devel \
        numactl \
        numactl-devel
else
    log_error "Unsupported OS: $OS"
    exit 1
fi

log_info "Package installation complete"

###########################################
# STEP 2: Install MVAPICH2
###########################################

log_section "Installing MVAPICH2"

# Using 2.3.6 which has better PBS/Torque compatibility
MVAPICH2_VERSION="2.3.6"
MVAPICH2_DIR="/opt/mvapich2"
MVAPICH2_BUILD_DIR="/tmp/mvapich2-build"

# Check if MVAPICH2 is already installed
if [[ -f "$MVAPICH2_DIR/bin/mpirun" ]]; then
    log_warn "MVAPICH2 already installed at $MVAPICH2_DIR"
    EXISTING_VERSION=$($MVAPICH2_DIR/bin/mpirun --version 2>&1 | head -1 || echo "unknown")
    log_info "Existing version: $EXISTING_VERSION"
    read -p "Do you want to reinstall? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping MVAPICH2 installation"
        SKIP_MVAPICH2=true
    else
        log_info "Removing existing installation..."
        rm -rf "$MVAPICH2_DIR"
        SKIP_MVAPICH2=false
    fi
else
    SKIP_MVAPICH2=false
fi

if [[ "$SKIP_MVAPICH2" == "false" ]]; then
    log_info "Downloading MVAPICH2 $MVAPICH2_VERSION..."
    mkdir -p "$MVAPICH2_BUILD_DIR"
    cd "$MVAPICH2_BUILD_DIR"
    
    MVAPICH2_TARBALL="mvapich2-${MVAPICH2_VERSION}.tar.gz"
    MVAPICH2_URL="https://mvapich.cse.ohio-state.edu/download/mvapich/mv2/${MVAPICH2_TARBALL}"
    
    if [[ ! -f "$MVAPICH2_TARBALL" ]]; then
        wget "$MVAPICH2_URL" || {
            log_error "Failed to download MVAPICH2 ${MVAPICH2_VERSION}"
            log_info "Trying alternate download location..."
            wget "http://mvapich.cse.ohio-state.edu/download/mvapich/mv2/${MVAPICH2_TARBALL}"
        }
    fi
    
    log_info "Extracting MVAPICH2..."
    tar -xzf "$MVAPICH2_TARBALL"
    cd mvapich2-${MVAPICH2_VERSION}*/
    
    log_info "Configuring MVAPICH2..."
    log_info "This may take several minutes..."
    
    # Detect if InfiniBand is available
    if lspci | grep -i mellanox >/dev/null 2>&1 || [[ -d /sys/class/infiniband ]]; then
        log_info "InfiniBand detected - enabling IB support"
        CONFIGURE_FLAGS="--enable-fast=O3 --with-device=ch3:mrail --with-rdma=gen2"
    else
        log_info "No InfiniBand detected - using TCP/IP"
        CONFIGURE_FLAGS="--enable-fast=O3 --with-device=ch3:sock"
    fi
    
    # Configure with flags to allow Fortran type mismatches (common in MPI libraries)
    # Keep PBS/Torque support enabled for job scheduler integration
    ./configure \
        --prefix="$MVAPICH2_DIR" \
        $CONFIGURE_FLAGS \
        --enable-fortran=yes \
        --enable-cxx \
        --enable-shared \
        --enable-threads=multiple \
        --with-pm=hydra \
        FFLAGS="-O2 -fallow-argument-mismatch" \
        FCFLAGS="-O2 -fallow-argument-mismatch" \
        2>&1 | tee configure.log
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log_error "Configuration failed! Check configure.log"
        tail -100 configure.log
        exit 1
    fi
    
    log_info "Patching PBS launcher bug (post-configure)..."
    # After configure, bsci_init.c is generated from bsci_init.c.in
    # We need to remove the broken PBS launcher reference
    BSCI_FILE=$(find . -name "bsci_init.c" -path "*/tools/bootstrap/src/*" | head -1)
    if [[ -f "$BSCI_FILE" ]]; then
        log_info "Found generated file: $BSCI_FILE"
        # Remove the PBS launcher reference that causes compilation error
        sed -i.bak 's/HYDT_bsci_launcher_pbs_init, //' "$BSCI_FILE"
        sed -i.bak 's/HYDT_bsci_launcher_pbs_init,//' "$BSCI_FILE"
        
        # Verify patch applied
        if grep -q "HYDT_bsci_launcher_pbs_init" "$BSCI_FILE"; then
            log_error "PBS launcher patch failed!"
            log_info "File content around launcher_init_array:"
            grep -n "launcher_init_array" "$BSCI_FILE"
            exit 1
        else
            log_info "✓ PBS launcher bug patched successfully"
        fi
    else
        log_warn "Could not find generated bsci_init.c file, attempting compilation anyway..."
    fi
    
    log_info "Compiling MVAPICH2..."
    log_info "This will take 10-20 minutes..."
    make -j$(nproc) 2>&1 | tee make.log
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log_error "Compilation failed! Showing last 50 lines of make.log:"
        tail -50 make.log
        exit 1
    fi
    
    log_info "Installing MVAPICH2..."
    make install 2>&1 | tee install.log
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log_error "Installation failed! Showing last 50 lines of install.log:"
        tail -50 install.log
        exit 1
    fi
    
    log_info "Cleaning up build directory..."
    cd /
    rm -rf "$MVAPICH2_BUILD_DIR"
    
    log_info "MVAPICH2 installed successfully at $MVAPICH2_DIR"
fi

###########################################
# STEP 3: Configure Environment
###########################################

log_section "Configuring Environment"

# Create environment module file (if module system exists)
if command -v modulecmd &> /dev/null; then
    log_info "Creating environment module..."
    MODULEFILE_DIR="/usr/share/modules/modulefiles/mpi"
    mkdir -p "$MODULEFILE_DIR"
    
    cat > "$MODULEFILE_DIR/mvapich2" <<EOF
#%Module1.0
##
## MVAPICH2 module
##
proc ModulesHelp { } {
    puts stderr "Adds MVAPICH2 to your environment"
}

module-whatis "MVAPICH2 MPI implementation"

prepend-path PATH $MVAPICH2_DIR/bin
prepend-path LD_LIBRARY_PATH $MVAPICH2_DIR/lib
prepend-path MANPATH $MVAPICH2_DIR/share/man
prepend-path PKG_CONFIG_PATH $MVAPICH2_DIR/lib/pkgconfig

setenv MPI_HOME $MVAPICH2_DIR
setenv MPI_DIR $MVAPICH2_DIR
EOF
    log_info "Module file created at $MODULEFILE_DIR/mvapich2"
fi

# Create profile.d script for automatic loading
log_info "Creating system-wide environment configuration..."
cat > /etc/profile.d/mvapich2.sh <<EOF
# MVAPICH2 Environment
export PATH=$MVAPICH2_DIR/bin:\$PATH
export LD_LIBRARY_PATH=$MVAPICH2_DIR/lib:\$LD_LIBRARY_PATH
export MANPATH=$MVAPICH2_DIR/share/man:\$MANPATH
export MPI_HOME=$MVAPICH2_DIR
export MPI_DIR=$MVAPICH2_DIR
EOF

chmod +x /etc/profile.d/mvapich2.sh

log_info "Environment configured"

###########################################
# STEP 4: Configure SSH for MPI
###########################################

log_section "Configuring SSH for MPI"

# Configure SSH client for MPI (not daemon - we don't want to break SSH!)
log_info "Configuring SSH client for MPI communication..."

# Create system-wide SSH client config for MPI
mkdir -p /etc/ssh/ssh_config.d
cat > /etc/ssh/ssh_config.d/99-mpi.conf <<'EOF'
# MPI SSH Client Configuration
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF

log_info "SSH client configured for MPI (SSH daemon not modified)"

###########################################
# STEP 5: Configure Torque/PBS
###########################################

log_section "Configuring Torque/PBS"

if $IS_HEADNODE; then
    log_info "Configuring PBS for MPI jobs..."
    
    # Check if PBS is installed
    if command -v qsub &> /dev/null; then
        # Create PBS epilogue to clean up MPI processes
        cat > /var/spool/torque/mom_priv/epilogue <<'EOF'
#!/bin/bash
# Clean up any remaining MPI processes
pkill -9 -u $1 mpirun mpiexec || true
EOF
        chmod +x /var/spool/torque/mom_priv/epilogue
        
        # Restart PBS mom
        if systemctl is-active --quiet pbs_mom; then
            systemctl restart pbs_mom
        fi
    fi
fi

###########################################
# STEP 6: Test Installation
###########################################

log_section "Testing Installation"

# Source the environment
source /etc/profile.d/mvapich2.sh

# Test MPI installation
log_info "Testing MVAPICH2 installation..."
if command -v mpirun &> /dev/null; then
    log_info "mpirun found: $(which mpirun)"
    log_info "MVAPICH2 version:"
    mpirun --version 2>&1 | head -5
else
    log_error "mpirun not found in PATH"
    exit 1
fi

# Test compilation
log_info "Testing MPI compiler..."
cat > /tmp/mpi_test.c <<'EOF'
#include <mpi.h>
#include <stdio.h>

int main(int argc, char** argv) {
    MPI_Init(&argc, &argv);
    int world_size, world_rank;
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);
    MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);
    printf("Hello from rank %d of %d\n", world_rank, world_size);
    MPI_Finalize();
    return 0;
}
EOF

if mpicc -o /tmp/mpi_test /tmp/mpi_test.c 2>&1; then
    log_info "✓ MPI compilation successful"
    
    # Test single-node execution
    log_info "Testing single-node MPI execution..."
    if mpirun -np 2 /tmp/mpi_test 2>&1; then
        log_info "✓ Single-node MPI test successful"
    else
        log_warn "Single-node MPI test failed"
    fi
else
    log_error "MPI compilation failed"
    exit 1
fi

# Cleanup test files
rm -f /tmp/mpi_test.c /tmp/mpi_test

###########################################
# STEP 7: System Tuning for MPI
###########################################

log_section "System Tuning for MPI Performance"

# Increase shared memory limits
log_info "Configuring shared memory limits..."
cat >> /etc/security/limits.conf <<'EOF'

# MPI Shared Memory Limits
* soft memlock unlimited
* hard memlock unlimited
* soft nofile 65536
* hard nofile 65536
EOF

# Configure kernel parameters for MPI
log_info "Configuring kernel parameters..."
cat > /etc/sysctl.d/99-mpi.conf <<'EOF'
# MPI Performance Tuning
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
kernel.shmmni = 4096
vm.max_map_count = 262144

# Network tuning
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_sack = 1
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 67108864
net.core.wmem_default = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.netdev_max_backlog = 250000
EOF

sysctl -p /etc/sysctl.d/99-mpi.conf >/dev/null 2>&1 || log_warn "Some sysctl settings may require reboot"

###########################################
# Summary
###########################################

log_section "Installation Complete"

log_info "MVAPICH2 Location: $MVAPICH2_DIR"
log_info "Environment: /etc/profile.d/mvapich2.sh"
log_info ""
log_info "To use MVAPICH2 in your current session:"
log_info "  source /etc/profile.d/mvapich2.sh"
log_info ""
log_info "To verify installation:"
log_info "  mpirun --version"
log_info "  which mpicc mpirun mpiexec"
log_info ""

if $IS_HEADNODE; then
    log_info "Next steps for HEAD NODE:"
    log_info "  1. Run this script on all compute nodes"
    log_info "  2. Ensure SSH keys are distributed (run setup_ssh_for_mpi.sh if needed)"
    log_info "  3. Submit test job with: qsub mvapich2_multinode_test.pbs"
else
    log_info "Next steps for COMPUTE NODE:"
    log_info "  1. Verify connectivity with head node"
    log_info "  2. Jobs will be submitted from head node"
fi

log_info ""
log_info "✓ MVAPICH2 cluster setup complete!"
