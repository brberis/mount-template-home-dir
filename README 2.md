# mount-template-home-dir

## HPC Cluster Configuration Scripts and Documentation

This repository contains scripts and comprehensive documentation for setting up and managing an HPC cluster with Slurm and NIS on Rocky Linux 9.

---

## 🆕 Latest: NIS and Slurm Multi-Node Setup (Oct 27, 2025)

### Problem Solved
Successfully configured NIS (Network Information Service) on Rocky Linux 9 and fixed Slurm multi-node job execution.

### Documentation

📘 **[Complete Setup Guide](NIS_SLURM_SETUP.md)** - Detailed step-by-step instructions  
⚡ **[Quick Reference](QUICK_REFERENCE_NIS_SLURM.md)** - One-page quick start  
📋 **[Changes Summary](CHANGES_SUMMARY.md)** - What was changed and why  
✅ **[Verification Results](VERIFICATION_RESULTS.md)** - Test results and proof of functionality

### Quick Links

- **Install NIS on compute nodes:** See [QUICK_REFERENCE_NIS_SLURM.md](QUICK_REFERENCE_NIS_SLURM.md)
- **Fix Slurm multi-node issues:** See [NIS_SLURM_SETUP.md](NIS_SLURM_SETUP.md#part-1-fix-slurm-multi-node-configuration)
- **Troubleshooting:** See [NIS_SLURM_SETUP.md - Troubleshooting Section](NIS_SLURM_SETUP.md#troubleshooting)

---

## What's Included

### NIS Setup for Rocky Linux 9
- Complete build and installation instructions for:
  - **ypbind-mt 2.7.2** - NIS client daemon
  - **yp-tools 4.2.3** - NIS query utilities
  - **libnss_nis 3.2** - NSS library for name resolution
- Automated installation script
- systemd service configuration
- Configuration files for all components

### Slurm Multi-Node Configuration
- Slurm configuration fixes for multi-node job execution
- Node address configuration
- Service management procedures
- Testing and verification procedures

### Additional Scripts
Various HPC cluster management scripts for:
- Home directory mounting
- Container configurations
- E4S (Extreme-scale Scientific Software Stack) setups
- PBS/Slurm job scripts

---

## System Requirements

- **OS:** Rocky Linux 9 / RHEL 9
- **Slurm:** 23.11.4 or compatible
- **Network:** TCP/IP connectivity between head and compute nodes
- **NIS Server:** Must be running on head node

---

## Quick Start

### For New Deployments

1. **Fix Slurm Configuration (Head Node):**
   ```bash
   # Edit /etc/slurm/slurm.conf - Add NodeAddr for each compute node
   # See NIS_SLURM_SETUP.md Part 1 for details
   ```

2. **Install NIS on Compute Nodes:**
   ```bash
   # Use the automated script from QUICK_REFERENCE_NIS_SLURM.md
   # Installation takes ~10 minutes per node
   ```

3. **Verify:**
   ```bash
   sinfo                    # Check node status
   srun --nodes=2 hostname  # Test multi-node jobs
   getent passwd <username> # Test NIS lookup
   ```

---

## Documentation Structure

```
.
├── README.md                          # This file
├── NIS_SLURM_SETUP.md                # Complete setup guide (main documentation)
├── QUICK_REFERENCE_NIS_SLURM.md      # Quick reference and automated script
├── CHANGES_SUMMARY.md                 # Summary of changes made
├── VERIFICATION_RESULTS.md            # Test results and verification
└── [various scripts...]               # Additional cluster management scripts
```

---

## Why This Was Necessary

**Rocky Linux 9 / RHEL 9 removed NIS support:**
- NIS (YP) is considered legacy technology
- Red Hat removed it from glibc to push modern alternatives (FreeIPA, SSSD)
- Many HPC clusters still rely on NIS for user management
- This documentation provides a complete workaround by building NIS from source

**Slurm Multi-Node Issues:**
- Missing NodeAddr configuration prevented multi-node job execution
- Documentation includes proper configuration and troubleshooting

---

## Support

For issues, questions, or contributions:
1. Check the [Troubleshooting section](NIS_SLURM_SETUP.md#troubleshooting) in the main guide
2. Review [VERIFICATION_RESULTS.md](VERIFICATION_RESULTS.md) for expected test outputs
3. Consult [QUICK_REFERENCE_NIS_SLURM.md](QUICK_REFERENCE_NIS_SLURM.md) for common fixes

---

## License

These scripts and documentation are provided as-is for HPC cluster administration purposes.

---

## Cluster Information

- **Domain:** nodus.com
- **Head Node:** rocky9-e4s (10.1.1.162)
- **Compute Nodes:** ac-9726-0-0 (10.1.1.241), ac-9726-0-1 (10.1.1.101)
- **Status:** ✅ Operational
- **Last Verified:** October 27, 2025# rocky-9-slurm-nis
