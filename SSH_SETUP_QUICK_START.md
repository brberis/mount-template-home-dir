# MPI SSH Setup Scripts - Quick Reference

## Which Script to Use?

### Use `setup_ssh_for_mpi_nis.sh` if:
✅ Your cluster uses NIS (Network Information Service)  
✅ Users can be added at any time  
✅ You want a "set it and forget it" solution  
✅ New users should automatically work without re-running scripts  

### Use `setup_ssh_for_mpi.sh` if:
⚠️ Fixed set of local users (no NIS)  
⚠️ All users known at deployment time  
⚠️ You manually manage users on each node  

## Quick Start (NIS Cluster - RECOMMENDED)

```bash
# Run on ALL nodes (head + compute)
bash setup_ssh_for_mpi_nis.sh

# Test with any user
sudo -u username ssh node-name hostname
```

## What Gets Configured?

| Component | NIS Script | Old Script |
|-----------|-----------|------------|
| System SSH config | ✅ /etc/ssh/ssh_config.d/ | ❌ |
| System SSHD config | ✅ /etc/ssh/sshd_config.d/ | ❌ |
| Per-user ~/.ssh/ | Auto-generated | ✅ Manual |
| Works for new users | ✅ Yes | ❌ No |
| Requires sudo | ✅ Yes | ✅ Yes |

## Files Created

### NIS Script (`setup_ssh_for_mpi_nis.sh`)
```
/etc/ssh/ssh_config.d/90-mpi-cluster.conf
/etc/ssh/sshd_config.d/90-mpi-cluster.conf
/etc/ssh/ssh_known_hosts
/usr/local/bin/generate-mpi-ssh-keys
~/.ssh/id_rsa (per user, auto-generated)
~/.ssh/authorized_keys (per user, auto-generated)
```

## Adding a New NIS User After Setup

**Option 1: Automatic (on first login)**
```bash
# User logs in - keys auto-generated
# Nothing to do!
```

**Option 2: Manual (before first login)**
```bash
# Pre-generate SSH keys
sudo -u newuser /usr/local/bin/generate-mpi-ssh-keys
```

## Testing

```bash
# Run the test script
bash test_mpi_ssh.sh

# Or test manually
sudo -u testuser ssh compute-node hostname
# Should return: compute-node (no password, no warnings)
```

## Troubleshooting

### User's SSH still prompts for password
```bash
# Generate keys manually
sudo -u username /usr/local/bin/generate-mpi-ssh-keys /home/username username

# Check key permissions
sudo ls -la /home/username/.ssh/
# id_rsa should be 600, authorized_keys should be 600
```

### NIS user "doesn't exist"
```bash
# Check NIS is working
ypwhich
ypcat passwd | grep username
getent passwd username

# If NIS is down
sudo systemctl restart ypbind
```

### SSH asks for host key verification
```bash
# Check system config loaded
cat /etc/ssh/ssh_config.d/90-mpi-cluster.conf

# Restart SSH daemon
sudo systemctl restart sshd
```

## PBS Job Example

```bash
#!/bin/bash
#PBS -l nodes=2:ppn=48

mpiexec -np 96 --hostfile $PBS_NODEFILE ./myapp
# SSH works automatically - no extra config needed!
```

## Documentation

- **NIS Setup**: See `NIS_SSH_SETUP_README.md`
- **Standard Setup**: See `SSH_SETUP_README.md`
- **Test Script**: `test_mpi_ssh.sh`

## One-Liner Deployment

```bash
# Download and run on each node
curl -sL https://your-repo/setup_ssh_for_mpi_nis.sh | sudo bash
```

## Summary

For NIS clusters, use **`setup_ssh_for_mpi_nis.sh`**:
- ✅ Run once per node
- ✅ Works for all current users
- ✅ Works for all future users  
- ✅ No need to re-run when adding users
- ✅ System-level configuration

This is the **recommended** approach for production HPC clusters with NIS!
