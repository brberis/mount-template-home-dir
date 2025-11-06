#!/bin/bash
#
# E4S Container Shortcut Installation Script
# 
# This script creates a system-wide shortcut command 'e4s' that allows all users
# to easily run commands inside the E4S container without typing long Singularity commands.
#
# Usage: bash install_e4s_shortcut.sh
# (sudo is called internally for commands that require root privileges)
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
    log_error "sudo command not found. Please install sudo first."
    exit 1
fi

log_section "E4S Container Shortcut Installation"

# Configuration
E4S_CONTAINER="/e4sonpremvm/E4S/24.02/e4s-cuda80-x86_64-24.11.sif"
INSTALL_DIR="/usr/local/bin"
SHORTCUT_NAME="e4s"

# Verify container exists
if [[ ! -f "$E4S_CONTAINER" ]]; then
    log_error "E4S container not found at: $E4S_CONTAINER"
    log_info "Please update the E4S_CONTAINER path in this script"
    exit 1
fi

log_info "E4S Container found: $E4S_CONTAINER"

# Create the shortcut script
log_info "Creating E4S shortcut script..."

sudo bash -c "cat > '$INSTALL_DIR/$SHORTCUT_NAME'" <<'EOFSCRIPT'
#!/bin/bash
#
# E4S Container Shortcut
# Provides easy access to E4S software stack via Singularity container
#

# E4S Container location
E4S_CONTAINER="/e4sonpremvm/E4S/24.02/e4s-cuda80-x86_64-24.11.sif"

# E4S environment setup - source spack setup (correct path for this container)
E4S_ENV_SETUP='
if [ -f /etc/profile ]; then source /etc/profile 2>/dev/null; fi
if [ -f /spack/share/spack/setup-env.sh ]; then 
    source /spack/share/spack/setup-env.sh 2>/dev/null
elif [ -f /usr/share/spack/setup-env.sh ]; then 
    source /usr/share/spack/setup-env.sh 2>/dev/null
elif [ -f /opt/spack/share/spack/setup-env.sh ]; then 
    source /opt/spack/share/spack/setup-env.sh 2>/dev/null
fi
'

# Check if container exists
if [[ ! -f "$E4S_CONTAINER" ]]; then
    echo "ERROR: E4S container not found at $E4S_CONTAINER" >&2
    exit 1
fi

# Check if singularity is available
if ! command -v singularity &> /dev/null; then
    echo "ERROR: Singularity not found. Please install Singularity first." >&2
    exit 1
fi

# Function to show help
show_help() {
    cat << EOF
E4S Container Shortcut - Easy access to E4S software stack

USAGE:
    e4s [COMMAND] [ARGS...]
    e4s [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -s, --shell         Start an interactive shell in the container
    -j, --jupyter       Start Jupyter Lab in the container
    -l, --list          List available E4S packages (uses spack)
    --find-spack        Locate spack installation inside container
    --version           Show E4S container version

EXAMPLES:
    # Run ANY command/application in E4S container
    e4s python3 my_script.py
    e4s gcc --version
    e4s make
    e4s cmake ..
    e4s nvidia-smi
    
    # MPI applications
    e4s mpirun -np 4 ./my_mpi_program
    e4s mpicc -o program program.c
    
    # Scientific computing tools
    e4s python3 -c "import numpy; print(numpy.__version__)"
    e4s R --version
    e4s julia --version
    
    # Spack package management
    e4s spack find
    e4s spack load python
    e4s spack list | grep hdf5
    
    # Interactive shell (access to all container tools)
    e4s --shell
    e4s -s
    
    # Start Jupyter Lab
    e4s --jupyter
    e4s -j
    
    # Check what tools are available
    e4s which python3
    e4s ls /usr/bin

NOTES:
    - Works with ANY application installed in the E4S container
    - GPU support (--nv) is automatically enabled
    - Your home directory is automatically mounted
    - Current working directory is preserved
    - All environment variables are passed through
    - E4S includes: compilers (gcc, clang), MPI, Python, R, Julia,
      scientific libraries (HDF5, NetCDF, PETSc, etc.), and more

For more information about E4S: https://e4s-project.github.io/
EOF
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -s|--shell)
        # Interactive shell
        echo "Starting E4S interactive shell..."
        exec singularity shell --nv "$E4S_CONTAINER"
        ;;
    -j|--jupyter)
        # Start Jupyter Lab
        echo "Starting Jupyter Lab in E4S container..."
        echo "Access at: http://$(hostname):8888"
        exec singularity exec --nv "$E4S_CONTAINER" bash -c "cd ~ && jupyter-lab"
        ;;
    -l|--list)
        # List available packages
        echo "Available E4S packages:"
        exec singularity exec --nv "$E4S_CONTAINER" bash -c "$E4S_ENV_SETUP && spack find"
        ;;
    --find-spack)
        # Find spack installation
        echo "Searching for Spack installation in container..."
        singularity exec --nv "$E4S_CONTAINER" bash -c "
            echo 'Checking common Spack locations:'
            for path in /usr/share/spack /opt/spack /spack /root/spack /home/*/spack; do
                if [ -d \"\$path\" ]; then
                    echo \"  Found: \$path\"
                    if [ -f \"\$path/share/spack/setup-env.sh\" ]; then
                        echo \"    ✓ setup-env.sh exists\"
                    fi
                fi
            done
            echo ''
            echo 'Searching for spack executable:'
            find / -name 'spack' -type f -executable 2>/dev/null | head -5 || echo '  Not found in PATH search'
            echo ''
            echo 'Checking if spack is in PATH:'
            which spack 2>/dev/null || echo '  spack not in default PATH'
        "
        exit 0
        ;;
    --version)
        # Show version info
        singularity exec --nv "$E4S_CONTAINER" bash -c "echo 'E4S Container Information:'; cat /etc/os-release 2>/dev/null || echo 'OS info not available'; echo ''; echo 'Spack version:'; $E4S_ENV_SETUP && spack --version 2>/dev/null || echo 'Spack not available'"
        exit 0
        ;;
    "")
        # No arguments - show help
        show_help
        exit 0
        ;;
    *)
        # Execute command in container with E4S environment loaded
        # Pass all arguments as separate parameters
        singularity exec --nv "$E4S_CONTAINER" /bin/bash -c "
$E4S_ENV_SETUP
\"\$@\"
" -- "$@"
        ;;
esac
EOFSCRIPT

# Make the script executable
sudo chmod +x "$INSTALL_DIR/$SHORTCUT_NAME"

log_info "✓ E4S shortcut installed at: $INSTALL_DIR/$SHORTCUT_NAME"

# Verify installation
if command -v e4s &> /dev/null; then
    log_info "✓ E4S shortcut is available in PATH"
else
    log_warn "$INSTALL_DIR is not in PATH. Add it to /etc/environment or user profiles"
fi

log_section "Installation Complete"

log_info "The 'e4s' command is now available system-wide for all users!"
log_info ""
log_info "USAGE EXAMPLES:"
log_info "  e4s --help                    # Show help message"
log_info "  e4s --shell                   # Start interactive shell"
log_info "  e4s --jupyter                 # Start Jupyter Lab"
log_info ""
log_info "RUN ANY APPLICATION:"
log_info "  e4s python3 script.py         # Run Python scripts"
log_info "  e4s gcc program.c -o program  # Compile with GCC"
log_info "  e4s mpirun -np 4 ./app        # Run MPI applications"
log_info "  e4s cmake ..                  # Build with CMake"
log_info "  e4s nvidia-smi                # Check GPU status"
log_info "  e4s spack find                # List installed packages"
log_info ""
log_info "✓ The shortcut works with ANY command/tool in the E4S container!"
log_info "✓ All users can now use the 'e4s' command!"
