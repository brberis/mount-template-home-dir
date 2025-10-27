# NIS and Slurm Multi-Node Setup Guide for Rocky Linux 9

## Overview
This document describes how to set up NIS (Network Information Service) on Rocky Linux 9 / RHEL 9 and configure Slurm for multi-node job execution. Rocky Linux 9 removed NIS support from glibc, requiring us to build NIS components from source.

**Cluster Configuration:**
- Head Node: rocky9-e4s (10.1.1.162)
- Compute Node 1: ac-9726-0-0 (10.1.1.241)
- Compute Node 2: ac-9726-0-1 (10.1.1.101)
- NIS Domain: nodus.com

---

## Problem Summary
1. **Slurm multi-node jobs failing**: NodeAddr not configured in slurm.conf
2. **NIS not working on compute nodes**: Rocky Linux 9 removed NIS from glibc
3. **User lookup failing**: Missing ypbind, yp-tools, and libnss_nis libraries

---

## Part 1: Fix Slurm Multi-Node Configuration

### Issue
Multi-node jobs were failing because Slurm couldn't resolve compute node addresses.

### Solution: Update slurm.conf

Edit `/etc/slurm/slurm.conf` on the head node:

```bash
sudo vi /etc/slurm/slurm.conf
```

**Critical Change:** Add `NodeAddr` parameter to each compute node entry.

**Change from:**
```
NodeName=ac-9726-0-0 CPUs=4 State=UNKNOWN
NodeName=ac-9726-0-1 CPUs=4 State=UNKNOWN
```

**To:**
```
NodeName=ac-9726-0-0 NodeAddr=10.1.2.22 CPUs=4 State=UNKNOWN
NodeName=ac-9726-0-1 NodeAddr=10.1.2.156 CPUs=4 State=UNKNOWN
```

<details>
<summary>📋 Complete slurm.conf Example (Click to expand)</summary>

```ini
# /etc/slurm/slurm.conf - Example working configuration
# Rocky Linux 9 with Slurm 23.11.4

# Process Tracking
ProctrackType=proctrack/cgroup
TaskPlugin=task/affinity,task/cgroup

# Authentication
AuthType=auth/munge
AuthAltTypes=auth/jwt
AuthAltParameters=jwt_key=/var/spool/slurmd/jwt_hs256.key

# Controller Configuration
ReturnToService=1
SlurmctldPidFile=/var/run/slurmctld.pid
SlurmctldPort=6817
SlurmctldTimeout=120
SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurm/slurmctld.log
StateSaveLocation=/var/spool/slurmctld

# Compute Node Configuration
SlurmdPidFile=/var/run/slurmd.pid
SlurmdPort=6818
SlurmdSpoolDir=/var/spool/slurmd
SlurmdTimeout=300
SlurmdDebug=info
SlurmdLogFile=/var/log/slurm/slurmd.log

# User Configuration
SlurmUser=slurm

# Job Limits
InactiveLimit=0
KillWait=30
MinJobAge=300
Waittime=0

# Scheduler
SchedulerType=sched/backfill
SelectType=select/cons_tres

# Accounting
AccountingStorageHost=localhost
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageUser=slurm
AccountingStoreFlags=job_env,job_script

# Cluster Definition
ClusterName=rocky9-e4s
ControlMachine=rocky9-e4s

# *** CRITICAL: NodeAddr is REQUIRED for multi-node jobs ***
# Without NodeAddr, nodes will show as "unknown" and jobs will fail
NodeName=ac-9726-0-0 NodeAddr=10.1.2.22 CPUs=4 State=UNKNOWN
NodeName=ac-9726-0-1 NodeAddr=10.1.2.156 CPUs=4 State=UNKNOWN

# Partition Configuration
PartitionName=batch Nodes=ALL Default=YES MaxTime=INFINITE State=UP
```

**Key Points:**
- `NodeAddr` must match the actual IP address of each compute node
- Find IPs with: `getent hosts ac-9726-0-0` or `ping -c1 ac-9726-0-0`
- After editing, distribute to all nodes and restart services
</details>

### Distribute Configuration

Copy the updated configuration to all compute nodes:

```bash
# Copy to first compute node
sudo scp /etc/slurm/slurm.conf ac-9726-0-0:/etc/slurm/slurm.conf

# Copy to second compute node
sudo scp /etc/slurm/slurm.conf ac-9726-0-1:/etc/slurm/slurm.conf
```

### Restart Slurm Services

```bash
# On head node
sudo systemctl restart slurmctld

# On each compute node
sudo ssh root@ac-9726-0-0 'systemctl restart slurmd'
sudo ssh root@ac-9726-0-1 'systemctl restart slurmd'
```

### Set Nodes to IDLE

```bash
sudo scontrol update nodename=ac-9726-0-0 state=idle
sudo scontrol update nodename=ac-9726-0-1 state=idle
```

---

## Part 2: Build and Install NIS Components

Rocky Linux 9 / RHEL 9 removed NIS support. We need to build three components from source:
1. **ypbind-mt** - NIS client daemon
2. **yp-tools** - NIS query tools (ypcat, ypwhich, etc.)
3. **libnss_nis** - NSS library for NIS name resolution

### Prerequisites

Install build dependencies:

```bash
sudo dnf install -y gcc make rpcgen libtirpc-devel libnsl2-devel systemd-devel \
    wget tar xz autoconf automake libtool gettext-devel
```

### Build ypbind-mt (NIS Client Daemon)

```bash
cd /tmp
wget https://github.com/thkukuk/ypbind-mt/releases/download/v2.7.2/ypbind-mt-2.7.2.tar.xz
tar xf ypbind-mt-2.7.2.tar.xz
cd ypbind-mt-2.7.2

./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var
make -j$(nproc)
sudo make install
```

### Build yp-tools (NIS Query Tools)

```bash
cd /tmp
wget https://github.com/thkukuk/yp-tools/archive/refs/tags/v4.2.3.tar.gz
tar xzf v4.2.3.tar.gz
cd yp-tools-4.2.3

autoreconf -fi
./configure --prefix=/usr
make -j$(nproc)
sudo make install
```

### Build libnss_nis (NSS NIS Library)

```bash
cd /tmp
wget https://github.com/thkukuk/libnss_nis/releases/download/v3.2/libnss_nis-3.2.tar.xz
tar xf libnss_nis-3.2.tar.xz
cd libnss_nis-3.2

./configure --prefix=/usr
make -j$(nproc)
sudo make install
sudo ldconfig
```

---

## Part 3: Configure NIS on Compute Nodes

### Step 1: Set NIS Domain

```bash
echo "nodus.com" | sudo tee /etc/defaultdomain
sudo domainname nodus.com
```

### Step 2: Configure yp.conf

Create `/etc/yp.conf`:

```bash
sudo cat > /etc/yp.conf << 'EOF'
# yp.conf - YP client configuration
# NIS domain and server configuration
domain nodus.com server 10.1.1.162
ypserver 10.1.1.162
EOF
```

### Step 3: Configure nsswitch.conf

Backup and update `/etc/nsswitch.conf`:

```bash
sudo cp /etc/nsswitch.conf /etc/nsswitch.conf.backup
sudo sed -i 's/^passwd:.*/passwd:     files nis/' /etc/nsswitch.conf
sudo sed -i 's/^shadow:.*/shadow:     files nis/' /etc/nsswitch.conf  
sudo sed -i 's/^group:.*/group:      files nis/' /etc/nsswitch.conf
```

### Step 4: Create ypbind systemd Service

Create `/etc/systemd/system/ypbind.service`:

```bash
sudo cat > /etc/systemd/system/ypbind.service << 'EOF'
[Unit]
Description=NIS/YP (Network Information Service) Client
Wants=rpcbind.service
After=rpcbind.service network-online.target
Before=nss-user-lookup.target

[Service]
Type=simple
ExecStartPre=/usr/bin/domainname nodus.com
ExecStart=/usr/sbin/ypbind -foreground
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
```

### Step 5: Enable and Start Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable rpcbind ypbind
sudo systemctl restart rpcbind
sudo systemctl start ypbind
```

### Step 6: Verify NIS is Working

```bash
# Check ypbind is running
sudo systemctl status ypbind

# Test NIS binding
ypwhich
# Should output: 10.1.1.162

# Test user lookup
getent passwd testuser
# Should output: testuser:x:2000:2000::/home/testuser:/usr/bin/bash

# Test with ypcat
ypcat passwd | grep testuser
```

---

## Part 4: Complete Installation Script for Compute Nodes

Here's a complete script to install and configure NIS on a compute node:

```bash
#!/bin/bash
# NIS Client Installation Script for Rocky Linux 9 Compute Nodes

set -e

# Variables
NIS_DOMAIN="nodus.com"
NIS_SERVER="10.1.1.162"
BUILD_DIR="/tmp"

echo "=== Installing NIS Client on $(hostname) ==="

# Install build dependencies
echo "Installing build dependencies..."
dnf install -y gcc make rpcgen libtirpc-devel libnsl2-devel systemd-devel \
    wget tar xz autoconf automake libtool gettext-devel

# Build and install ypbind-mt
echo "Building ypbind-mt..."
cd $BUILD_DIR
wget https://github.com/thkukuk/ypbind-mt/releases/download/v2.7.2/ypbind-mt-2.7.2.tar.xz
tar xf ypbind-mt-2.7.2.tar.xz
cd ypbind-mt-2.7.2
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var
make -j$(nproc)
make install

# Build and install yp-tools
echo "Building yp-tools..."
cd $BUILD_DIR
wget https://github.com/thkukuk/yp-tools/archive/refs/tags/v4.2.3.tar.gz
tar xzf v4.2.3.tar.gz
cd yp-tools-4.2.3
autoreconf -fi
./configure --prefix=/usr
make -j$(nproc)
make install

# Build and install libnss_nis
echo "Building libnss_nis..."
cd $BUILD_DIR
wget https://github.com/thkukuk/libnss_nis/releases/download/v3.2/libnss_nis-3.2.tar.xz
tar xf libnss_nis-3.2.tar.xz
cd libnss_nis-3.2
./configure --prefix=/usr
make -j$(nproc)
make install
ldconfig

# Configure NIS domain
echo "Configuring NIS domain..."
echo "$NIS_DOMAIN" > /etc/defaultdomain
domainname $NIS_DOMAIN

# Configure yp.conf
echo "Creating /etc/yp.conf..."
cat > /etc/yp.conf << EOF
domain $NIS_DOMAIN server $NIS_SERVER
ypserver $NIS_SERVER
EOF

# Update nsswitch.conf
echo "Updating /etc/nsswitch.conf..."
cp /etc/nsswitch.conf /etc/nsswitch.conf.backup
sed -i 's/^passwd:.*/passwd:     files nis/' /etc/nsswitch.conf
sed -i 's/^shadow:.*/shadow:     files nis/' /etc/nsswitch.conf  
sed -i 's/^group:.*/group:      files nis/' /etc/nsswitch.conf

# Create ypbind systemd service
echo "Creating ypbind systemd service..."
cat > /etc/systemd/system/ypbind.service << 'EOF'
[Unit]
Description=NIS/YP (Network Information Service) Client
Wants=rpcbind.service
After=rpcbind.service network-online.target
Before=nss-user-lookup.target

[Service]
Type=simple
ExecStartPre=/usr/bin/domainname nodus.com
ExecStart=/usr/sbin/ypbind -foreground
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
echo "Enabling and starting services..."
systemctl daemon-reload
systemctl enable rpcbind ypbind
systemctl restart rpcbind
systemctl start ypbind

# Wait for ypbind to be ready
sleep 3

# Verify installation
echo ""
echo "=== Verification ==="
echo "ypbind status:"
systemctl status ypbind --no-pager | head -10

echo ""
echo "NIS server binding:"
ypwhich

echo ""
echo "User lookup test (testuser):"
getent passwd testuser

echo ""
echo "=== NIS installation complete on $(hostname) ==="
```

---

## Part 5: Testing Multi-Node Slurm Jobs with NIS

### Simple Test

```bash
srun --nodes=2 --ntasks=2 bash -c "echo Node:\$(hostname) User:\$(whoami) UID:\$(id -u)"
```

**Expected Output:**
```
Node:ac-9726-0-0 User:testuser UID:2000
Node:ac-9726-0-1 User:testuser UID:2000
```

### Comprehensive Test

```bash
srun --nodes=2 --ntasks=2 bash -c "hostname && getent passwd testuser && ls -ld \$HOME"
```

**Expected Output:**
```
ac-9726-0-0
testuser:...:2000:2000::/home/testuser:/usr/bin/bash
drwxr-xr-x 9 testuser testuser 4096 ... /home/testuser

ac-9726-0-1
testuser:...:2000:2000::/home/testuser:/usr/bin/bash
drwxr-xr-x 9 testuser testuser 4096 ... /home/testuser
```

### MPI Multi-Node Test

**IMPORTANT: CPU Architecture Consideration**

If you have MPI programs that fail with "Illegal instruction" errors, it's likely because the MPI library was compiled with CPU instructions (like AVX-512) that your hardware doesn't support.

**Check Your CPU Capabilities:**
```bash
lscpu | grep -E "Model name|Flags"
```

For Intel Xeon E5-2686 v4 (common on AWS), the CPU supports AVX2 but NOT AVX-512.

**Solution: Use Amazon OpenMPI**

Amazon provides OpenMPI builds optimized for AWS hardware at `/opt/amazon/openmpi/`.

#### Update MPI Compilation Script

Create or update `compile.sh`:
```bash
#!/bin/bash
set -x
export PATH=/opt/amazon/openmpi/bin:$PATH
mpicc -o mpiprocname mpiprocname.c
```

#### Update MPI Batch Script

Create `mpiprocname.sbatch`:
```bash
#!/bin/bash
#SBATCH --job-name=mpiprocname
#SBATCH --nodes=2
#SBATCH --ntasks=4
#SBATCH --ntasks-per-node=2
#SBATCH --exclusive
#SBATCH -t 0-0:02

export PATH=/opt/amazon/openmpi/bin:$PATH
export LD_LIBRARY_PATH=/opt/amazon/openmpi/lib64:$LD_LIBRARY_PATH

mpirun ./mpiprocname
```

#### Run the MPI Test

```bash
cd ~/examples/mpi-procname
./compile.sh
sbatch mpiprocname.sbatch
```

#### Check Output

```bash
cat slurm-*.out
```

**Expected Output:**
```
Hello, world.  I am 0 of 4 on ac-9726-0-0
Hello, world.  I am 1 of 4 on ac-9726-0-0
Hello, world.  I am 2 of 4 on ac-9726-0-1
Hello, world.  I am 3 of 4 on ac-9726-0-1
```

This confirms:
- ✅ Multi-node Slurm execution
- ✅ NIS user authentication across nodes
- ✅ MPI communication between nodes
- ✅ Correct task distribution (2 tasks per node)

---

## Troubleshooting

### Check NIS server connectivity

```bash
rpcinfo -p 10.1.1.162 | grep ypserv
```

### Check ypbind status

```bash
systemctl status ypbind
journalctl -u ypbind -n 50
```

### Test NIS binding

```bash
ypwhich          # Should show NIS server IP
ypcat passwd     # Should list NIS users
getent passwd testuser  # Should show user details
```

### Check NSS library

```bash
ls -la /usr/lib64/libnss_nis*
ldconfig -p | grep libnss_nis
```

### Verify Slurm nodes

```bash
sinfo              # All nodes should be 'idle'
scontrol show nodes   # Check node details
```

### MPI "Illegal Instruction" Error

**Symptom:**
```
Illegal instruction (core dumped)
```

**Cause:** MPI library compiled with CPU instructions not supported by your hardware (e.g., AVX-512 on CPUs that only support AVX2).

**Diagnosis:**
```bash
# Check CPU capabilities
lscpu | grep Flags

# Check MPI compilation flags
mpicc --version
mpiexec --version  # Look for -mavx512f or similar flags
```

**Solution:**

Use Amazon OpenMPI which is compiled for AWS hardware:

```bash
# Option 1: Update PATH in your scripts
export PATH=/opt/amazon/openmpi/bin:$PATH
export LD_LIBRARY_PATH=/opt/amazon/openmpi/lib64:$LD_LIBRARY_PATH

# Option 2: Use full paths
/opt/amazon/openmpi/bin/mpicc -o myprogram myprogram.c
```

**Available MPI installations:**
```bash
# Check what's available
ls -la /opt/amazon/openmpi*/bin/mpicc
ls -la /usr/lib64/openmpi/bin/mpicc
ls -la /usr/local/mvapich*/bin/mpicc
```

**For AWS EC2 instances:**
- Use `/opt/amazon/openmpi/` (OpenMPI 4.x optimized for AWS)
- Use `/opt/amazon/openmpi5/` (OpenMPI 5.x optimized for AWS)
- Avoid `/usr/local/mvapich4-plus/` if compiled with AVX-512 and your CPU doesn't support it

---

## Files Modified

### Head Node (rocky9-e4s)
- `/etc/slurm/slurm.conf` - Added NodeAddr parameters

### All Compute Nodes (ac-9726-0-0, ac-9726-0-1)
- `/etc/defaultdomain` - NIS domain configuration
- `/etc/yp.conf` - NIS client configuration
- `/etc/nsswitch.conf` - Name service switch configuration
- `/etc/systemd/system/ypbind.service` - ypbind systemd service
- `/etc/slurm/slurm.conf` - Copied from head node

### Binaries Installed on All Compute Nodes
- `/usr/sbin/ypbind` - NIS client daemon
- `/usr/bin/ypcat`, `/usr/bin/ypmatch`, `/usr/bin/ypwhich` - NIS query tools
- `/usr/lib64/libnss_nis.so.2` - NSS NIS library

---

## Summary

After following this guide, your Rocky Linux 9 cluster will have:

1. **Working multi-node Slurm**: Jobs can run across multiple compute nodes
2. **NIS user authentication**: NIS users can log in and run jobs on all nodes
3. **Shared home directories**: Users can access their home directories from any node
4. **Complete NIS functionality**: All NIS tools (ypcat, ypwhich, getent) working correctly

The setup is persistent across reboots, as all services are enabled with systemd.

---

**Date:** October 27, 2025  
**Tested on:** Rocky Linux 9 with Slurm 23.11.4  
**NIS Domain:** nodus.com
