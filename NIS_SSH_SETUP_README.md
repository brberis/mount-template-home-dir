# MPI SSH Setup for PBS/Torque Cluster with NIS

## Overview

The `setup_ssh_for_mpi_nis.sh` script configures SSH for **all users** (current and future) in a PBS/Torque cluster that uses NIS (Network Information Service). Unlike per-user configuration, this approach works at the **system level** and automatically handles new NIS users without re-running the script.

## Problem Solved

In NIS environments:
- Users are centrally managed and broadcast to all nodes
- Users may not have local `/etc/passwd` entries on compute nodes  
- New users can be added at any time
- Traditional per-user SSH setup scripts must be re-run for each new user

This script solves these issues by:
1. ✅ Configuring SSH at the **system level** for all cluster nodes
2. ✅ Auto-generating SSH keys for users on first login
3. ✅ Works for NIS users without local password file entries
4. ✅ No need to re-run for new users
5. ✅ Disables strict host key checking between cluster nodes

## Key Differences from Standard Script

| Feature | Standard Script | NIS Script |
|---------|----------------|------------|
| Target Users | Specific sudoers users | ALL users (UID >= 1000) |
| Configuration Level | Per-user ~/.ssh/config | System-wide /etc/ssh/ |
| New User Support | Requires re-run | Automatic |
| NIS Compatibility | Limited | Full |
| SSH Key Generation | At script runtime | On-demand (first login) |

## Usage

### Manual Execution

Run on each node (crew user with sudo):

```bash
# On head node
bash setup_ssh_for_mpi_nis.sh

# On each compute node
bash setup_ssh_for_mpi_nis.sh
```

### Terraform Integration

```hcl
resource "null_resource" "ssh_setup" {
  count = var.node_count
  
  provisioner "remote-exec" {
    inline = [
      "curl -o /tmp/setup_ssh_for_mpi_nis.sh https://your-repo/setup_ssh_for_mpi_nis.sh",
      "chmod +x /tmp/setup_ssh_for_mpi_nis.sh",
      "bash /tmp/setup_ssh_for_mpi_nis.sh"
    ]
    
    connection {
      type = "ssh"
      user = "crew"
      host = element(var.node_ips, count.index)
    }
  }
}
```

## How It Works

### 1. System-Wide SSH Client Configuration

Creates `/etc/ssh/ssh_config.d/90-mpi-cluster.conf`:
```
Host ac-* *.local 10.* 172.16.* 192.168.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    PasswordAuthentication no
    PubkeyAuthentication yes
```

**Effect**: ALL users get these settings when SSHing to cluster nodes

### 2. SSH Daemon Configuration

Creates `/etc/ssh/sshd_config.d/90-mpi-cluster.conf`:
```
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
MaxStartups 100:10:200
MaxSessions 100
```

**Effect**: SSH daemon accepts many simultaneous MPI connections

### 3. Auto SSH Key Generation Script

Creates `/usr/local/bin/generate-mpi-ssh-keys`:
- Runs on user's first login (or manually)
- Generates 4096-bit RSA key if missing
- Adds own public key to `~/.ssh/authorized_keys`
- Works for NIS users even without local home directory cache

### 4. System Known Hosts

Populates `/etc/ssh/ssh_known_hosts` with all cluster node keys:
- System-wide trusted hosts
- No per-user known_hosts management needed

### 5. Existing User Setup

For users with existing `/home/` directories:
- Automatically runs key generation script
- Handles NIS users correctly with proper ownership

## Files Created

### System-Wide Configuration
- `/etc/ssh/ssh_config.d/90-mpi-cluster.conf` - Client settings for all users
- `/etc/ssh/sshd_config.d/90-mpi-cluster.conf` - Daemon settings
- `/etc/ssh/ssh_known_hosts` - System known hosts
- `/usr/local/bin/generate-mpi-ssh-keys` - Key generation script

### Per-User Files (auto-generated)
- `~/.ssh/id_rsa` - Private key (600 permissions)
- `~/.ssh/id_rsa.pub` - Public key (644 permissions)
- `~/.ssh/authorized_keys` - Authorized keys (600 permissions)
- `~/.ssh/config` - User SSH config (600 permissions)

## New NIS User Workflow

When a new NIS user logs in for the first time:

1. User attempts first SSH to a cluster node
2. System SSH config applies (no host key checking)
3. If SSH key doesn't exist, they get prompted (first time only)
4. Admin can pre-generate keys: `sudo -u newuser /usr/local/bin/generate-mpi-ssh-keys`

## Manual SSH Key Generation for NIS Users

For a NIS user who hasn't logged in yet:

```bash
# Create home directory if needed (NIS might not auto-create)
sudo mkdir -p /home/nisuser
sudo chown nisuser:nisuser /home/nisuser

# Generate SSH keys
sudo -u nisuser /usr/local/bin/generate-mpi-ssh-keys /home/nisuser nisuser

# Or if sudo -u doesn't work for NIS users:
HOME=/home/nisuser USER=nisuser sudo /usr/local/bin/generate-mpi-ssh-keys /home/nisuser nisuser
sudo chown -R nisuser:nisuser /home/nisuser/.ssh
```

## Verification

Test SSH connectivity for any user:

```bash
# As a specific user
sudo -u username ssh node-name hostname

# Should return the node's hostname with no password prompt or warnings
```

## NIS-Specific Considerations

### Home Directory Creation

NIS doesn't automatically create home directories. Ensure:
- PAM is configured to create home dirs on first login: `pam_mkhomedir.so`
- Or pre-create homes for known users

### UID/GID Consistency

Ensure NISmaps have consistent UIDs/GIDs across all nodes:
```bash
# Check NIS user info
ypcat passwd | grep username
getent passwd username
```

### NFS Home Directories

If using NFS for `/home`:
- SSH keys created on one node are available on all nodes ✅
- Simpler key management
- No need to distribute keys between nodes

If **NOT** using NFS:
- Keys must be synchronized between nodes
- Consider using the head node to distribute keys to compute nodes

## Troubleshooting

### "sudo -u nisuser" doesn't work

NIS users might not be cached locally. Use:
```bash
HOME=/home/nisuser USER=nisuser sudo /usr/local/bin/generate-mpi-ssh-keys /home/nisuser nisuser
```

### Permission denied (publickey)

Check:
```bash
# Verify SSH key exists
sudo ls -la /home/username/.ssh/

# Verify permissions
sudo stat /home/username/.ssh/id_rsa  # Should be 600
sudo stat /home/username/.ssh/authorized_keys  # Should be 600

# Verify ownership (especially for NIS users)
sudo ls -ln /home/username/.ssh/  # Should show correct UID/GID
```

### NIS user home directory not created

Enable PAM to auto-create home dirs. Edit `/etc/pam.d/common-session`:
```
session required pam_mkhomedir.so skel=/etc/skel umask=0022
```

### SSH still asks for host key verification

Check system SSH config:
```bash
cat /etc/ssh/ssh_config.d/90-mpi-cluster.conf
```

Verify it's being loaded:
```bash
sudo sshd -T | grep stricthostkeychecking
```

## PBS Job Example

After setup, MPI jobs work seamlessly:

```bash
#!/bin/bash
#PBS -N mpi_job
#PBS -l nodes=2:ppn=48
#PBS -l walltime=01:00:00

cd $PBS_O_WORKDIR

# Load MPI
source /spack/share/spack/setup-env.sh
spack load openmpi

# Run MPI application - SSH works automatically!
mpiexec -np 96 --hostfile $PBS_NODEFILE ./my_mpi_app
```

No additional SSH configuration needed in the PBS script!

## Security Notes

⚠️ **Important Security Considerations**:

1. **Disabled Host Key Checking**: Vulnerable to MITM attacks
   - Acceptable in private, isolated HPC networks
   - **NOT** recommended for public networks

2. **Auto-Generated Keys**: No passphrase protection
   - Keys are unencrypted for batch job automation
   - Ensure proper filesystem permissions

3. **Wide Host Matching**: Matches all private IP ranges
   - Adjust patterns in config if too permissive for your environment

**Best Practices**:
- Use on isolated/private networks only
- Implement network-level security (VLANs, firewalls)
- Restrict SSH access to cluster nodes via firewall rules
- Monitor SSH logs: `/var/log/auth.log`

## Comparison with Old Script

If you previously used `setup_ssh_for_mpi.sh` (sudoers-based):
- **Migration**: Run the new NIS script on all nodes
- **Coexistence**: Both can coexist safely
- **Recommendation**: Use NIS script for cleaner, more scalable approach

## Support

Common issues:
- **NIS not responding**: Check `ypwhich`, restart `ypbind`
- **Home dirs on NFS**: Ensure NFS is mounted before running script
- **Permissions errors**: NIS UID/GID must match across all nodes

## License

This script is provided as-is for use in PBS/Torque HPC clusters with NIS.
