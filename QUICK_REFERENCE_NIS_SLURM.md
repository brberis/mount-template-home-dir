# Quick Reference: NIS & Slurm Multi-Node Setup

## Quick Cluster Info
- **Head Node:** rocky9-e4s (10.1.1.162)
- **Compute Nodes:** ac-9726-0-0 (10.1.2.22), ac-9726-0-1 (10.1.2.156)
- **NIS Domain:** nodus.com

---

## 1. Fix Slurm Configuration (Head Node Only)

### Edit slurm.conf
```bash
sudo vi /etc/slurm/slurm.conf
```

**Add NodeAddr to compute node lines:**
```ini
# Before (nodes show as unknown):
NodeName=ac-9726-0-0 CPUs=4 State=UNKNOWN
NodeName=ac-9726-0-1 CPUs=4 State=UNKNOWN

# After (with NodeAddr):
NodeName=ac-9726-0-0 NodeAddr=10.1.2.22 CPUs=4 State=UNKNOWN
NodeName=ac-9726-0-1 NodeAddr=10.1.2.156 CPUs=4 State=UNKNOWN
```

> 💡 **Tip:** See [complete slurm.conf example](NIS_SLURM_SETUP.md#solution-update-slurmconf) in the full setup guide.

### Apply Configuration

```bash
# Copy to compute nodes
sudo scp /etc/slurm/slurm.conf ac-9726-0-0:/etc/slurm/slurm.conf
sudo scp /etc/slurm/slurm.conf ac-9726-0-1:/etc/slurm/slurm.conf

# Restart services
sudo systemctl restart slurmctld
sudo ssh root@ac-9726-0-0 'systemctl restart slurmd'
sudo ssh root@ac-9726-0-1 'systemctl restart slurmd'

# Set nodes to idle
sudo scontrol update nodename=ac-9726-0-0 state=idle
sudo scontrol update nodename=ac-9726-0-1 state=idle
```

---

## 2. Install NIS Components (Run on Each Compute Node)

### Quick Install Script
```bash
#!/bin/bash
# Save as: install_nis_client.sh
# Run as: sudo bash install_nis_client.sh

NIS_DOMAIN="nodus.com"
NIS_SERVER="10.1.1.162"

# Install dependencies
dnf install -y gcc make rpcgen libtirpc-devel libnsl2-devel systemd-devel \
    wget tar xz autoconf automake libtool gettext-devel

# Build ypbind-mt
cd /tmp
wget https://github.com/thkukuk/ypbind-mt/releases/download/v2.7.2/ypbind-mt-2.7.2.tar.xz
tar xf ypbind-mt-2.7.2.tar.xz
cd ypbind-mt-2.7.2
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var
make -j$(nproc) && make install

# Build yp-tools
cd /tmp
wget https://github.com/thkukuk/yp-tools/archive/refs/tags/v4.2.3.tar.gz
tar xzf v4.2.3.tar.gz
cd yp-tools-4.2.3
autoreconf -fi
./configure --prefix=/usr
make -j$(nproc) && make install

# Build libnss_nis
cd /tmp
wget https://github.com/thkukuk/libnss_nis/releases/download/v3.2/libnss_nis-3.2.tar.xz
tar xf libnss_nis-3.2.tar.xz
cd libnss_nis-3.2
./configure --prefix=/usr
make -j$(nproc) && make install && ldconfig

# Configure NIS
echo "$NIS_DOMAIN" > /etc/defaultdomain
domainname $NIS_DOMAIN

cat > /etc/yp.conf << EOF
domain $NIS_DOMAIN server $NIS_SERVER
ypserver $NIS_SERVER
EOF

cp /etc/nsswitch.conf /etc/nsswitch.conf.backup
sed -i 's/^passwd:.*/passwd:     files nis/' /etc/nsswitch.conf
sed -i 's/^shadow:.*/shadow:     files nis/' /etc/nsswitch.conf  
sed -i 's/^group:.*/group:      files nis/' /etc/nsswitch.conf

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

systemctl daemon-reload
systemctl enable rpcbind ypbind
systemctl restart rpcbind
systemctl start ypbind

echo "NIS Installation Complete!"
echo "Testing:"
sleep 3
ypwhich
getent passwd testuser
```

---

## 3. Quick Verification Commands

```bash
# Check Slurm
sinfo                    # All nodes should show 'idle'
scontrol show nodes      # Verify node addresses

# Check NIS
systemctl status ypbind  # Should be active (running)
ypwhich                  # Should show: 10.1.1.162
getent passwd testuser   # Should show user details
ypcat passwd             # List all NIS users

# Test multi-node job
srun --nodes=2 --ntasks=2 bash -c "echo \$(hostname): \$(whoami)"
```

---

## 4. Common Issues & Fixes

### Slurm nodes in unknown state
```bash
sudo scontrol update nodename=NODE_NAME state=idle
```

### ypbind not running
```bash
sudo systemctl restart rpcbind
sudo systemctl restart ypbind
journalctl -u ypbind -n 50
```

### getent not working
```bash
# Check if libnss_nis is installed
ls -la /usr/lib64/libnss_nis*
sudo ldconfig

# Verify nsswitch.conf
grep "passwd:" /etc/nsswitch.conf
# Should show: passwd:     files nis
```

### Can't reach NIS server
```bash
# Test connectivity
rpcinfo -p 10.1.1.162 | grep ypserv

# Check ypbind binding
cat /var/yp/binding/nodus.com.3
```

### MPI "Illegal instruction" error
```bash
# Problem: MPI compiled with AVX-512, but CPU only supports AVX2

# Check CPU capabilities
lscpu | grep Flags | grep avx512
# If empty, CPU doesn't support AVX-512

# Solution: Use Amazon OpenMPI
export PATH=/opt/amazon/openmpi/bin:$PATH
export LD_LIBRARY_PATH=/opt/amazon/openmpi/lib64:$LD_LIBRARY_PATH

# Recompile your MPI program
mpicc -o myprogram myprogram.c
```

---

## 5. Service Management

```bash
# Start services
sudo systemctl start rpcbind ypbind

# Stop services
sudo systemctl stop ypbind rpcbind

# Restart services
sudo systemctl restart ypbind

# Check status
sudo systemctl status ypbind
sudo systemctl status rpcbind

# View logs
journalctl -u ypbind -f
```

---

## 6. Test Suite

### Basic NIS Test
```bash
ypwhich && \
getent passwd testuser && \
ypcat passwd | grep testuser && \
echo "NIS OK"
```

### Multi-Node Slurm Test
```bash
srun --nodes=2 --ntasks=2 bash -c "hostname && getent passwd testuser && whoami && id"
```

### Home Directory Access Test
```bash
srun --nodes=2 --ntasks=2 bash -c "ls -ld \$HOME && touch \$HOME/test_\$(hostname).txt"
```

### MPI Multi-Node Test

**For AWS/Intel Xeon E5 CPUs (AVX2 but not AVX-512):**

```bash
# Use Amazon OpenMPI (not mvapich with AVX-512)
export PATH=/opt/amazon/openmpi/bin:$PATH
export LD_LIBRARY_PATH=/opt/amazon/openmpi/lib64:$LD_LIBRARY_PATH

# Compile
cd ~/examples/mpi-procname
mpicc -o mpiprocname mpiprocname.c

# Create batch script
cat > mpiprocname.sbatch << 'EOF'
#!/bin/bash
#SBATCH --job-name=mpiprocname
#SBATCH --nodes=2
#SBATCH --ntasks=4
#SBATCH --ntasks-per-node=2
#SBATCH -t 0-0:02

export PATH=/opt/amazon/openmpi/bin:$PATH
export LD_LIBRARY_PATH=/opt/amazon/openmpi/lib64:$LD_LIBRARY_PATH
mpirun ./mpiprocname
EOF

# Submit
sbatch mpiprocname.sbatch

# Check output
cat slurm-*.out
```

**Expected Output:**
```
Hello, world.  I am 0 of 4 on ac-9726-0-0
Hello, world.  I am 1 of 4 on ac-9726-0-0
Hello, world.  I am 2 of 4 on ac-9726-0-1
Hello, world.  I am 3 of 4 on ac-9726-0-1
```

---

## Build Times (for reference)
- **ypbind-mt**: ~30 seconds
- **yp-tools**: ~45 seconds
- **libnss_nis**: ~20 seconds
- **Total build time**: ~2 minutes per node

---

**For detailed documentation, see: NIS_SLURM_SETUP.md**
