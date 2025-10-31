# PBS/Torque MPI Optimization Guide

## Overview

The `setup_pbs_for_mpi.sh` script optimizes PBS/Torque for large-scale MPI jobs by configuring cgroups and system limits appropriately.

## What It Does

### ✅ Cgroups Configuration (Smart Approach)

**NOT disabling cgroups entirely** - instead:

- ✅ **Keeps cgroups ENABLED** for resource tracking and monitoring
- ✅ **Relaxes enforcement** to prevent job failures
- ✅ **Maintains visibility** into resource usage
- ✅ **Prevents cgroup creation errors** that block MPI jobs

### Specific Changes:

1. **Cgroups Settings**:
   ```bash
   $cgroups enabled                      # Keep tracking ON
   $enforce_cpuset_compliance false      # Don't block jobs if cpuset fails
   $enforce_memory_compliance false      # Don't block jobs if memory cgroup fails
   $memory_pressure_enabled false        # Allow jobs to use swap if needed
   ```

2. **Process Limits**:
   - Max load: 500 (from default ~100)
   - Ideal load: 100
   - Allows many MPI ranks on a single node

3. **System Limits** (`/etc/security/limits.d/90-mpi-jobs.conf`):
   ```
   Max processes: 65,536 (from default ~1024)
   Open files: 65,536 (from default ~1024)
   Stack size: unlimited
   Locked memory: unlimited (for RDMA/InfiniBand)
   ```

## Key Difference: Enabled vs Enforced

| Aspect | Before | After |
|--------|--------|-------|
| **Cgroups tracking** | Enabled | ✅ Still enabled |
| **Resource monitoring** | Active | ✅ Still active |
| **Strict enforcement** | Yes → causes failures | ❌ Disabled |
| **Job blocking** | Blocks on cgroup errors | ✅ Allows jobs to proceed |
| **PBS visibility** | Full | ✅ Full (no change) |

## Why This Approach?

### ❌ Bad: Disable cgroups entirely
```bash
$cgroups false  # Loses ALL resource tracking
```
**Problems**:
- PBS can't track memory usage
- No CPU usage monitoring
- No resource accounting
- Jobs can oversubscribe resources

### ✅ Good: Relax enforcement (our approach)
```bash
$cgroups enabled
$enforce_cpuset_compliance false
$enforce_memory_compliance false
```
**Benefits**:
- PBS still tracks resources ✅
- Jobs don't fail on cgroup errors ✅
- Monitoring and accounting continue ✅
- Best of both worlds ✅

## Deployment

### Requirements
- PBS/Torque installed
- Root or sudo access
- Run on ALL nodes (head + compute)

### Installation

1. **Deploy on head node**:
   ```bash
   scp setup_pbs_for_mpi.sh user@headnode:/tmp/
   ssh user@headnode 'sudo bash /tmp/setup_pbs_for_mpi.sh'
   ```

2. **Deploy on compute nodes**:
   ```bash
   for node in node1 node2 node3; do
     ssh headnode "scp /tmp/setup_pbs_for_mpi.sh $node:/tmp/"
     ssh headnode "ssh $node 'sudo bash /tmp/setup_pbs_for_mpi.sh'"
   done
   ```

3. **Verify**:
   ```bash
   # Check PBS MOM is running
   sudo systemctl status pbs_mom
   
   # Check config was applied
   grep "MPI Job Tuning" /var/spool/torque/mom_priv/config
   
   # Check system limits
   cat /etc/security/limits.d/90-mpi-jobs.conf
   ```

## What Gets Fixed

### Before (Common Failures):

```
❌ nodes=2:ppn=48  → "Could not create all cgroups for this job"
❌ nodes=4:ppn=24  → "cgroup creation failed"
❌ nodes=1:ppn=96  → Sometimes fails with cgroup errors
```

### After (Should Work):

```
✅ nodes=2:ppn=48  → Works (multi-node, high ppn)
✅ nodes=4:ppn=24  → Works (multi-node, medium ppn)
✅ nodes=1:ppn=96  → Works reliably (single-node, high ppn)
✅ nodes=8:ppn=12  → Works (multi-node, any ppn)
```

## Safety Features

1. **Automatic Backup**:
   - Original config backed up to: `/var/spool/torque/mom_priv/config.backup.YYYYMMDD_HHMMSS`

2. **Idempotent**:
   - Can be run multiple times safely
   - Removes old MPI tuning section before adding new one

3. **Verification**:
   - Checks PBS MOM restarts successfully
   - Verifies service is active after changes

## Rollback

If you need to restore original settings:

```bash
# Find backup
ls -lt /var/spool/torque/mom_priv/config.backup.*

# Restore
sudo cp /var/spool/torque/mom_priv/config.backup.YYYYMMDD_HHMMSS \
        /var/spool/torque/mom_priv/config

# Restart
sudo systemctl restart pbs_mom
```

## Monitoring After Deployment

Check that cgroups are still working for monitoring:

```bash
# View cgroups for a running job
ls -la /torque/

# Check PBS MOM logs
sudo tail -f /var/spool/torque/mom_logs/$(date +%Y%m%d)

# Monitor resource usage (still works!)
qstat -f <jobid> | grep resources_used
```

## Integration with Terraform

Add to your deployment pipeline:

```bash
#!/bin/bash
# deploy.sh - Run on each node after provisioning

# 1. Setup SSH for MPI
bash /tmp/setup_ssh_for_mpi_nis.sh

# 2. Optimize PBS for MPI
bash /tmp/setup_pbs_for_mpi.sh

# 3. Ready for MPI jobs!
```

## Troubleshooting

### PBS MOM won't start after changes

```bash
# Check logs
sudo journalctl -u pbs_mom -n 100

# Verify config syntax
sudo pbs_mom -c /var/spool/torque/mom_priv/config -s

# Restore backup if needed
sudo cp /var/spool/torque/mom_priv/config.backup.* \
        /var/spool/torque/mom_priv/config
sudo systemctl restart pbs_mom
```

### Jobs still fail with cgroup errors

1. Check that script ran on ALL nodes (including the one where job fails)
2. Verify PBS MOM was restarted: `sudo systemctl status pbs_mom`
3. Check config was applied: `grep enforce_cpuset_compliance /var/spool/torque/mom_priv/config`
4. Check system limits: `ulimit -a` (as the user running the job)

### Want to re-enable strict enforcement

Edit `/var/spool/torque/mom_priv/config`:

```bash
$enforce_cpuset_compliance true
$enforce_memory_compliance true
```

Then restart: `sudo systemctl restart pbs_mom`

## Summary

This script provides the **best of both worlds**:

- ✅ Cgroups **enabled** for monitoring and accounting
- ✅ Enforcement **relaxed** to prevent job failures
- ✅ System limits **increased** for large MPI jobs
- ✅ PBS functionality **fully maintained**
- ✅ Safe, reversible, well-documented

Perfect companion to `setup_ssh_for_mpi_nis.sh` for complete MPI cluster setup!
