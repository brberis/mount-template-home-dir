# MVAPICH2 Multinode Testing Guide

## Overview

This guide provides complete instructions for deploying and testing MVAPICH2 on a Torque/PBS cluster. All required files are included:

- **setup_mvapich2_cluster.sh** - Installation and configuration script
- **mpi_ring_test.c** - MPI test program
- **mvapich2_multinode_test.pbs** - PBS job script

## Prerequisites

- Torque/PBS scheduler installed and configured
- Root/sudo access on all nodes
- Network connectivity between all nodes
- At least 2 compute nodes for multinode testing

## Quick Start

### Step 1: Deploy on All Nodes

Run the setup script on **ALL nodes** (head node and compute nodes):

```bash
# Copy the script to the cluster
scp setup_mvapich2_cluster.sh paratoolsadmin@150.239.225.118:~/

# SSH to the head node
ssh paratoolsadmin@150.239.225.118

# Run the setup script with sudo
sudo bash setup_mvapich2_cluster.sh
```

**Repeat on each compute node:**
```bash
# SSH to each compute node
ssh compute-node-01
sudo bash setup_mvapich2_cluster.sh
```

The script will:
- ✓ Install all required packages (gcc, development tools, RDMA libraries)
- ✓ Download and compile MVAPICH2 2.3.7
- ✓ Configure environment variables
- ✓ Set up SSH for MPI communication
- ✓ Optimize kernel parameters for MPI
- ✓ Test the installation

### Step 2: Load MVAPICH2 Environment

After installation, load the environment:

```bash
source /etc/profile.d/mvapich2.sh
```

Verify installation:
```bash
which mpirun mpicc
mpirun --version
```

### Step 3: Deploy Test Files

Copy the test program and PBS script to your working directory:

```bash
# Create a test directory
mkdir -p ~/mpi_tests
cd ~/mpi_tests

# Copy files from your local machine
scp mpi_ring_test.c paratoolsadmin@150.239.225.118:~/mpi_tests/
scp mvapich2_multinode_test.pbs paratoolsadmin@150.239.225.118:~/mpi_tests/
```

### Step 4: Submit the Test Job

```bash
cd ~/mpi_tests

# Submit the job
qsub mvapich2_multinode_test.pbs

# Check job status
qstat

# View output when complete
cat mvapich2_test.log
```

## Detailed Installation Guide

### What the Setup Script Does

#### 1. Package Installation

**Ubuntu/Debian:**
- build-essential, gcc, g++, gfortran
- RDMA libraries (libibverbs, librdmacm)
- InfiniBand diagnostics tools
- Development headers and tools

**Rocky/RHEL/CentOS:**
- Development Tools group
- RDMA core development packages
- Compiler toolchain
- Network optimization tools

#### 2. MVAPICH2 Compilation

The script compiles MVAPICH2 from source with optimizations:

```bash
# Configuration options:
--prefix=/opt/mvapich2              # Installation location
--enable-fast=O3                    # Optimization level
--with-device=ch3:mrail             # InfiniBand support (if available)
--with-device=ch3:sock              # TCP/IP fallback
--enable-fortran=yes                # Fortran support
--enable-cxx                        # C++ support
--enable-threads=multiple           # Thread safety
```

#### 3. Environment Configuration

Creates `/etc/profile.d/mvapich2.sh` with:
```bash
export PATH=/opt/mvapich2/bin:$PATH
export LD_LIBRARY_PATH=/opt/mvapich2/lib:$LD_LIBRARY_PATH
export MPI_HOME=/opt/mvapich2
```

This ensures MVAPICH2 is available to all users automatically.

#### 4. SSH Configuration

Configures SSH for password-less MPI communication:
- Enables host-based authentication
- Disables strict host key checking for MPI
- Configures known hosts handling

**Note:** For production, also run `setup_ssh_for_mpi.sh` to distribute SSH keys.

#### 5. System Tuning

Optimizes kernel parameters for MPI performance:

**Memory limits:**
```bash
* soft memlock unlimited    # Allow large shared memory
* hard memlock unlimited
* soft nofile 65536         # Increase file descriptors
* hard nofile 65536
```

**Kernel parameters:**
```bash
kernel.shmmax = 68719476736     # Max shared memory segment
kernel.shmall = 4294967296      # Total shared memory pages
net.core.rmem_max = 134217728   # Network buffer sizes
net.core.wmem_max = 134217728
```

## Test Program Details

### mpi_ring_test.c

The test program performs comprehensive MPI validation:

**1. Ring Communication Test**
- Rank 0 sends a token to Rank 1
- Each rank increments and forwards the token
- Last rank sends back to Rank 0
- Verifies token passed through all processes

**2. Collective Operations**
- **Broadcast:** Rank 0 broadcasts data to all ranks
- **Reduce:** All ranks contribute to sum reduction
- **Gather:** Collects hostnames from all ranks

**3. Node Distribution**
- Shows how processes are distributed across nodes
- Helps verify multinode execution

**Expected Output:**
```
=== Starting MPI Ring Test with 8 processes ===

[Rank 0] Sending token 42 to rank 1
[Rank 1] Received token 42 from rank 0
[Rank 1] Sending token 43 to rank 2
...
[Rank 0] Received token 49 from rank 7 - RING COMPLETE!

✓ SUCCESS: Token passed through all 8 processes correctly!

=== Testing MPI Collective Operations ===
...
✓ Reduction test PASSED

=== Node Distribution ===
Processes distributed across 2 node(s):
  compute-node-01: 4 processes
  compute-node-02: 4 processes
```

## PBS Job Script Details

### mvapich2_multinode_test.pbs

**Key PBS Directives:**
```bash
#PBS -N mvapich2_multinode_test    # Job name
#PBS -l nodes=2:ppn=4              # 2 nodes, 4 processes per node
#PBS -l walltime=00:10:00          # 10 minute time limit
#PBS -j oe                         # Combine stdout/stderr
#PBS -o mvapich2_test.log          # Output file
```

**Customize for your cluster:**
- Adjust `nodes=X:ppn=Y` for your desired configuration
- Increase `walltime` for longer tests
- Add `-q queue_name` if using specific queues

**What the script does:**

1. **Environment Setup**
   - Loads MVAPICH2 environment
   - Verifies MPI commands are available
   - Displays version information

2. **Job Information**
   - Shows allocated nodes
   - Displays total processes
   - Lists node distribution

3. **Compilation**
   - Compiles mpi_ring_test.c on the head node
   - Verifies compilation success

4. **SSH Testing**
   - Tests SSH connectivity to all allocated nodes
   - Warns if connectivity issues exist

5. **MVAPICH2 Configuration**
   - Sets environment variables for optimal performance
   - Disables CPU affinity (if causing issues)
   - Enables debugging (optional)

6. **Test Execution**
   - Runs the ring communication test
   - Performs additional verification tests
   - Reports success/failure

7. **Results Summary**
   - Displays test results
   - Provides troubleshooting guidance if failed

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: "mpirun: command not found"

**Solution:**
```bash
# Reload environment
source /etc/profile.d/mvapich2.sh

# Or manually set paths
export PATH=/opt/mvapich2/bin:$PATH
export LD_LIBRARY_PATH=/opt/mvapich2/lib:$LD_LIBRARY_PATH
```

#### Issue 2: SSH connection failures

**Error:** `ssh: connect to host X.X.X.X port 22: Connection refused`

**Solution:**
```bash
# Run SSH setup script on all nodes
bash setup_ssh_for_mpi.sh

# Manually test SSH
ssh compute-node-01 hostname
```

#### Issue 3: Compilation errors

**Error:** `mpi.h: No such file or directory`

**Solution:**
```bash
# Verify mpicc is in PATH
which mpicc

# Check MPI installation
ls -la /opt/mvapich2/include/mpi.h
```

#### Issue 4: "Illegal instruction" errors

**Error:** `Illegal instruction (core dumped)`

**Solution:**
This typically means MVAPICH2 was compiled with CPU instructions not supported by your hardware.

```bash
# Check CPU capabilities
lscpu | grep -i flags

# Recompile with safer flags
cd /tmp/mvapich2-build/mvapich2-*/
./configure --prefix=/opt/mvapich2 \
    --enable-fast=O2 \  # Use O2 instead of O3
    --with-device=ch3:sock \
    CFLAGS="-march=native -mtune=generic"
make clean
make -j$(nproc)
sudo make install
```

#### Issue 5: Processes not distributed across nodes

**Symptoms:** All processes run on one node

**Solution:**
```bash
# Verify PBS_NODEFILE
cat $PBS_NODEFILE

# Check node availability
pbsnodes -a

# Try explicit hostfile
mpirun -np 8 -f hostfile ./mpi_ring_test
```

#### Issue 6: Shared memory errors

**Error:** `Failed to allocate shared memory`

**Solution:**
```bash
# Increase shared memory limits (already done by setup script)
# Verify settings
sysctl kernel.shmmax kernel.shmall

# Or disable shared memory
export MV2_SMP_USE_CMA=0
```

## Performance Tuning

### MVAPICH2 Environment Variables

For optimal performance, adjust these variables in your PBS script:

```bash
# CPU Binding
export MV2_ENABLE_AFFINITY=1           # Enable CPU affinity
export MV2_CPU_BINDING_POLICY=scatter  # Scatter processes across cores

# Shared Memory
export MV2_SMP_USE_CMA=1              # Use Cross Memory Attach
export MV2_USE_SHARED_MEM=1           # Enable shared memory

# InfiniBand (if available)
export MV2_USE_RDMA_CM=1              # Use RDMA Connection Manager
export MV2_DEFAULT_PORT=1             # IB port to use
export MV2_RAIL_SHARING_POLICY=FIXED_MAPPING

# Network Tuning
export MV2_VBUF_TOTAL_SIZE=32768      # Total buffer size
export MV2_RDMA_EAGER_THRESHOLD=16384 # RDMA eager threshold
```

### For Large Scale Jobs (100+ processes)

```bash
export MV2_HOMOGENEOUS_CLUSTER=1      # Assume homogeneous cluster
export MV2_USE_LAZY_MEM_UNREGISTER=1  # Lazy memory deregistration
export MV2_USE_HUGEPAGES=1            # Use huge pages (if available)
```

## Verification Tests

### Test 1: Single Node

```bash
# Test on one node with 4 processes
mpirun -np 4 ./mpi_ring_test
```

### Test 2: Two Nodes

```bash
# Create hostfile
echo "compute-node-01" > hostfile
echo "compute-node-01" >> hostfile
echo "compute-node-02" >> hostfile
echo "compute-node-02" >> hostfile

# Run test
mpirun -np 4 -f hostfile ./mpi_ring_test
```

### Test 3: All Available Nodes

```bash
# In a PBS job
mpirun -np $NPROCS -hostfile $PBS_NODEFILE ./mpi_ring_test
```

### Test 4: Bandwidth Test (Optional)

```bash
# Compile OSU Micro-Benchmarks
wget http://mvapich.cse.ohio-state.edu/download/mvapich/osu-micro-benchmarks-5.9.tar.gz
tar -xzf osu-micro-benchmarks-5.9.tar.gz
cd osu-micro-benchmarks-5.9
./configure CC=/opt/mvapich2/bin/mpicc
make
./mpi/pt2pt/osu_bw
```

## Next Steps

After successful testing:

1. **Deploy to Production**
   - Run setup_mvapich2_cluster.sh on all remaining nodes
   - Verify network connectivity and performance

2. **Install Applications**
   - Compile MPI applications with `/opt/mvapich2/bin/mpicc`
   - Use MVAPICH2 in your job scripts

3. **Monitor Performance**
   - Profile MPI jobs with built-in profiling tools
   - Optimize based on communication patterns

4. **User Documentation**
   - Provide users with MVAPICH2 module information
   - Share example job scripts

## Support and Resources

- **MVAPICH2 Documentation:** http://mvapich.cse.ohio-state.edu/
- **User Guide:** http://mvapich.cse.ohio-state.edu/userguide/
- **FAQ:** http://mvapich.cse.ohio-state.edu/faq/

## File Summary

All files created for this deployment:

1. **setup_mvapich2_cluster.sh** (466 lines)
   - Complete installation and configuration
   - Run on ALL nodes with sudo

2. **mpi_ring_test.c** (197 lines)
   - Comprehensive MPI test program
   - Tests communication and collective operations

3. **mvapich2_multinode_test.pbs** (264 lines)
   - PBS job script for multinode testing
   - Includes diagnostics and verification

4. **MVAPICH2_DEPLOYMENT_GUIDE.md** (this file)
   - Complete documentation
   - Troubleshooting and tuning guide

---

**Quick Reference Commands:**

```bash
# On head node (as root)
sudo bash setup_mvapich2_cluster.sh

# On each compute node (as root)
sudo bash setup_mvapich2_cluster.sh

# As regular user
source /etc/profile.d/mvapich2.sh
cd ~/mpi_tests
qsub mvapich2_multinode_test.pbs
qstat
cat mvapich2_test.log
```
