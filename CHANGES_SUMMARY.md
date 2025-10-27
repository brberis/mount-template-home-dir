# Cluster Configuration Summary
**Date:** October 27, 2025  
**Cluster:** rocky9-e4s with Slurm 23.11.4

---

## 🎯 Mission Accomplished

✅ **Slurm multi-node jobs** are now working correctly  
✅ **NIS user authentication** is functional on all compute nodes  
✅ **Home directories** are accessible from all nodes  
✅ **Complete documentation** for redeployment is available

---

## 📋 Changes Made

### 1. Slurm Configuration
**File:** `/etc/slurm/slurm.conf`

**Changed Lines:**
```diff
-NodeName=ac-9726-0-0 CPUs=4 State=UNKNOWN
-NodeName=ac-9726-0-1 CPUs=4 State=UNKNOWN
+NodeName=ac-9726-0-0 NodeAddr=10.1.2.22 CPUs=4 State=UNKNOWN
+NodeName=ac-9726-0-1 NodeAddr=10.1.2.156 CPUs=4 State=UNKNOWN
```

**Reason:** Slurm couldn't resolve compute node hostnames, causing multi-node jobs to fail.

**Complete example slurm.conf available in:** [NIS_SLURM_SETUP.md](NIS_SLURM_SETUP.md#solution-update-slurmconf)

---

### 2. NIS Client Installation (Both Compute Nodes)

Since Rocky Linux 9 removed NIS from glibc, we built and installed:

#### a) **ypbind-mt 2.7.2**
- **Source:** https://github.com/thkukuk/ypbind-mt
- **Purpose:** NIS client daemon for binding to NIS server
- **Installed to:** `/usr/sbin/ypbind`

#### b) **yp-tools 4.2.3**
- **Source:** https://github.com/thkukuk/yp-tools
- **Purpose:** NIS query utilities (ypcat, ypwhich, ypmatch, etc.)
- **Installed to:** `/usr/bin/ypcat`, `/usr/bin/ypwhich`, etc.

#### c) **libnss_nis 3.2**
- **Source:** https://github.com/thkukuk/libnss_nis
- **Purpose:** NSS library for NIS name resolution (enables `getent`)
- **Installed to:** `/usr/lib64/libnss_nis.so.2`

---

### 3. NIS Configuration Files (Both Compute Nodes)

#### `/etc/defaultdomain`
```
nodus.com
```

#### `/etc/yp.conf`
```
domain nodus.com server 10.1.1.162
ypserver 10.1.1.162
```

#### `/etc/nsswitch.conf` (Modified)
```diff
-passwd:     files
-shadow:     files
-group:      files
+passwd:     files nis
+shadow:     files nis
+group:      files nis
```

#### `/etc/systemd/system/ypbind.service` (Created)
```systemd
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
```

---

## 🔧 Services Enabled

On both compute nodes:
- `rpcbind.service` - Enabled and running
- `ypbind.service` - Enabled and running

---

## ✅ Verification Results

### Slurm Status
```bash
$ sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
batch*       up   infinite      2   idle ac-9726-0-[0-1]
```

### NIS Test on ac-9726-0-0
```bash
$ ypwhich
10.1.1.162

$ getent passwd testuser
testuser:x:2000:2000::/home/testuser:/usr/bin/bash
```

### NIS Test on ac-9726-0-1
```bash
$ ypwhich
10.1.1.162

$ getent passwd testuser
testuser:x:2000:2000::/home/testuser:/usr/bin/bash
```

### Multi-Node Slurm Job
```bash
$ srun --nodes=2 --ntasks=2 bash -c "echo \$(hostname): \$(whoami) [UID:\$(id -u)]"
ac-9726-0-0: testuser [UID:2000]
ac-9726-0-1: testuser [UID:2000]
```

---

## 📚 Documentation Created

1. **NIS_SLURM_SETUP.md** - Complete setup guide with:
   - Problem analysis
   - Step-by-step installation instructions
   - Automated installation script
   - Troubleshooting guide
   - Configuration file references

2. **QUICK_REFERENCE_NIS_SLURM.md** - Quick reference with:
   - One-page installation script
   - Common commands
   - Troubleshooting quick fixes
   - Test suite

3. **CHANGES_SUMMARY.md** (this file) - Summary of all changes

---

## 🚀 Redeployment Instructions

When the cluster is destroyed and redeployed:

### 1. On Head Node
```bash
# Edit /etc/slurm/slurm.conf - Add NodeAddr parameters
# Distribute to compute nodes
# Restart slurmctld
```

### 2. On Each Compute Node
```bash
# Run the installation script from NIS_SLURM_SETUP.md or QUICK_REFERENCE_NIS_SLURM.md
# The script handles everything automatically
```

### 3. Verify
```bash
# On head node
sinfo  # Check nodes are idle
srun --nodes=2 --ntasks=2 hostname  # Test multi-node
```

**Total redeployment time:** ~10 minutes per compute node (including build time)

---

## 🔍 Why This Was Necessary

1. **Rocky Linux 9 / RHEL 9 removed NIS**
   - NIS is considered legacy and deprecated
   - RHEL/Rocky removed it from glibc to push users to alternatives (SSSD, FreeIPA)
   - We needed NIS for compatibility with existing infrastructure

2. **Building from source was required**
   - No RPM packages available in standard repositories
   - EPEL doesn't provide NIS for RHEL 9+
   - Building from source ensures we have the latest stable versions

3. **Three components needed**
   - `ypbind-mt`: Client daemon to communicate with NIS server
   - `yp-tools`: Commands to query NIS maps
   - `libnss_nis`: Library to integrate NIS with system name resolution (getent, PAM, etc.)

---

## 💡 Alternative Solutions (Not Implemented)

If redeploying from scratch, consider:

1. **FreeIPA** - Modern replacement for NIS, LDAP, Kerberos
2. **SSSD with LDAP** - System Security Services Daemon
3. **Local user sync** - Ansible/scripts to sync /etc/passwd across nodes

We stuck with NIS to maintain compatibility with existing infrastructure.

---

## 📞 Support Information

For issues or questions:
- See troubleshooting section in `NIS_SLURM_SETUP.md`
- Check logs: `journalctl -u ypbind -n 100`
- Verify connectivity: `rpcinfo -p 10.1.1.162 | grep ypserv`

---

**Cluster is now fully operational with NIS and multi-node Slurm support! 🎉**
