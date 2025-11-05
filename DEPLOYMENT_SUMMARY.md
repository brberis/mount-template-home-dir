# MVAPICH2 Deployment Summary

## Current Status

✅ **Files uploaded to cluster:** 150.239.225.140
✅ **Installation in progress:** MVAPICH2 2.3.6 with full PBS/Torque support
⏳ **Estimated completion:** 15-20 minutes

## Files Created

### 1. setup_mvapich2_cluster.sh (Final Version)
**Purpose:** Complete MVAPICH2 installation script  
**Features:**
- ✅ Installs all required packages (gcc, gfortran, build tools, RDMA libraries)
- ✅ Downloads and compiles MVAPICH2 2.3.6 from source
- ✅ **Full PBS/Torque support** (not disabled!)
- ✅ Fixes Fortran type mismatch errors with `-fallow-argument-mismatch`
- ✅ Configures environment variables system-wide
- ✅ Sets up SSH client for MPI (doesn't break SSH daemon)
- ✅ Optimizes kernel parameters for MPI performance
- ✅ Tests installation automatically

**Run on:** ALL nodes (head node + all compute nodes)

### 2. mpi_ring_test.c
**Purpose:** Comprehensive MPI test program  
**Tests:**
- Ring communication (token passing)
- Collective operations (broadcast, reduce, gather)
- Node distribution verification
- Process communication validation

**Compile:** `mpicc -o mpi_ring_test mpi_ring_test.c`

### 3. mvapich2_multinode_test.pbs
**Purpose:** PBS/Torque job script for multinode testing  
**Features:**
- Automatically compiles MPI test program
- Tests SSH connectivity
- Runs MPI across multiple nodes
- Provides detailed diagnostics
- Shows node distribution

**Customize:**
```bash
#PBS -l nodes=2:ppn=4    # 2 nodes, 4 processes per node
#PBS -l walltime=00:10:00 # Time limit
```

**Submit:** `qsub mvapich2_multinode_test.pbs`

### 4. MVAPICH2_DEPLOYMENT_GUIDE.md
Complete documentation with:
- Step-by-step deployment guide
- Troubleshooting section
- Performance tuning tips
- Quick reference commands

### 5. fix_ssh_restore.sh
**Purpose:** Emergency SSH recovery (if needed)  
**Use only if:** SSH service gets broken

## Monitoring Installation Progress

Check installation status:
```bash
ssh paratoolsadmin@150.239.225.140 'tail -f ~/mvapich2_install_full.log'
```

Look for key messages:
- `[INFO] Compiling MVAPICH2...` → Compilation started
- `[INFO] Installing MVAPICH2...` → Installation started
- `✓ MPI compilation successful` → Test passed
- `✓ Single-node MPI test successful` → Installation complete

## After Installation Completes

### Step 1: Verify Installation on Head Node
```bash
ssh paratoolsadmin@150.239.225.140

# Load environment
source /etc/profile.d/mvapich2.sh

# Verify
mpirun --version
which mpicc mpirun
```

### Step 2: Deploy to Compute Nodes

Get list of compute nodes:
```bash
pbsnodes -a | grep -E "^[a-zA-Z]" | awk '{print $1}'
```

Run setup on each compute node:
```bash
# For each compute node:
ssh <compute-node> 'sudo bash ~/setup_mvapich2_cluster.sh'
```

Or automated:
```bash
for node in $(pbsnodes -a | grep -E "^[a-zA-Z]" | awk '{print $1}'); do
    echo "Setting up $node..."
    ssh $node 'sudo bash ~/setup_mvapich2_cluster.sh' &
done
wait
```

### Step 3: Prepare Test Directory
```bash
mkdir -p ~/mpi_tests
cd ~/mpi_tests
cp ~/mpi_ring_test.c .
cp ~/mvapich2_multinode_test.pbs .
```

### Step 4: Submit Test Job
```bash
cd ~/mpi_tests
qsub mvapich2_multinode_test.pbs
```

### Step 5: Check Results
```bash
# Check job status
qstat

# When complete, view results
cat mvapich2_test.log
```

## Expected Test Output

```
=== Starting MPI Ring Test with 8 processes ===

[Rank 0] Sending token 42 to rank 1
[Rank 1] Received token 42 from rank 0
...
✓ SUCCESS: Token passed through all 8 processes correctly!

=== Testing MPI Collective Operations ===
✓ Reduction test PASSED

=== Node Distribution ===
Processes distributed across 2 node(s):
  compute-node-01: 4 processes
  compute-node-02: 4 processes

=== All MPI Tests Completed Successfully ===
```

## Troubleshooting

### Installation Failed
```bash
# Check logs
ssh paratoolsadmin@150.239.225.140 'tail -200 ~/mvapich2_install_full.log'

# Check for specific errors
ssh paratoolsadmin@150.239.225.140 'grep -i error ~/mvapich2_install_full.log'
```

### MPI Not Found After Installation
```bash
# Reload environment
source /etc/profile.d/mvapich2.sh

# Or manually set
export PATH=/opt/mvapich2/bin:$PATH
export LD_LIBRARY_PATH=/opt/mvapich2/lib:$LD_LIBRARY_PATH
```

### SSH Connectivity Issues
```bash
# Run SSH setup script (already exists on cluster)
bash ~/setup_ssh_for_mpi.sh
```

### Job Fails to Start
```bash
# Check PBS node status
pbsnodes -a

# Check PBS logs
sudo tail /var/spool/torque/server_logs/$(date +%Y%m%d)
```

## Key Configuration Details

### MVAPICH2 Version
- **Version:** 2.3.6 (stable, good PBS/Torque support)
- **Communication:** TCP/IP (or InfiniBand if detected)
- **Installation:** /opt/mvapich2
- **PM:** Hydra process manager
- **Fortran:** Enabled with `-fallow-argument-mismatch`

### Environment Variables
Automatically set in `/etc/profile.d/mvapich2.sh`:
```bash
export PATH=/opt/mvapich2/bin:$PATH
export LD_LIBRARY_PATH=/opt/mvapich2/lib:$LD_LIBRARY_PATH
export MPI_HOME=/opt/mvapich2
export MPI_DIR=/opt/mvapich2
```

### PBS Job Script Variables
```bash
$PBS_NODEFILE     # List of allocated nodes
$PBS_NUM_NODES    # Number of nodes
$PBS_NUM_PPN      # Processes per node
$PBS_O_WORKDIR    # Job submission directory
```

## Quick Reference Commands

```bash
# Check installation progress
ssh paratoolsadmin@150.239.225.140 'tail -f ~/mvapich2_install_full.log'

# Verify installation
ssh paratoolsadmin@150.239.225.140 'source /etc/profile.d/mvapich2.sh && mpirun --version'

# List PBS nodes
ssh paratoolsadmin@150.239.225.140 'pbsnodes -a'

# Submit test job
ssh paratoolsadmin@150.239.225.140 'cd ~/mpi_tests && qsub mvapich2_multinode_test.pbs'

# Check job status
ssh paratoolsadmin@150.239.225.140 'qstat'

# View test results
ssh paratoolsadmin@150.239.225.140 'cat ~/mpi_tests/mvapich2_test.log'
```

## Files on Cluster (~/home/paratoolsadmin/)

- ✅ setup_mvapich2_cluster.sh
- ✅ mpi_ring_test.c
- ✅ mvapich2_multinode_test.pbs
- ✅ MVAPICH2_DEPLOYMENT_GUIDE.md
- ✅ fix_ssh_restore.sh
- ⏳ mvapich2_install_full.log (being created now)

## What Makes This Script Special

1. **Builds from Source:** Compiles MVAPICH2 specifically for your hardware
2. **PBS/Torque Integration:** Full support for job scheduler (not disabled)
3. **Fortran Fixed:** Uses `-fallow-argument-mismatch` to fix type errors
4. **No SSH Breaking:** Only modifies SSH client, not daemon
5. **Automatic Testing:** Verifies installation works before completing
6. **System-Wide:** Works for all users automatically
7. **Production Ready:** Includes error handling and logging

## Next Steps After This Document

1. Wait for installation to complete (~15-20 min)
2. Verify on head node
3. Deploy to compute nodes
4. Run multinode test
5. Celebrate working MVAPICH2 + Torque cluster! 🎉

---

**Installation Started:** $(date)  
**Cluster:** 150.239.225.140  
**MVAPICH2 Version:** 2.3.6  
**PBS/Torque:** ✅ ENABLED
