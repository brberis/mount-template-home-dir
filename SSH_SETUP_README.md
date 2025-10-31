# MPI SSH Setup for PBS/Torque Cluster

## Overview

The `setup_ssh_for_mpi.sh` script automatically configures SSH connectivity between nodes in a PBS/Torque cluster to enable multi-node MPI jobs. This solves the "Host key verification failed" error that prevents OpenMPI from launching processes on remote nodes.

## Problem Solved

When running MPI jobs across multiple nodes, OpenMPI uses SSH to launch processes on remote compute nodes. By default, SSH requires interactive host key verification, which fails in batch job environments. This script:

1. ✅ Generates SSH key pairs for the MPI user (`svanteuser`)
2. ✅ Configures passwordless SSH between all nodes
3. ✅ Disables strict host key checking for cluster nodes
4. ✅ Pre-populates known_hosts with all cluster nodes
5. ✅ Distributes keys from head node to compute nodes

## Usage

### Manual Execution

Run on each node (crew user, not root):

```bash
# On head node
bash setup_ssh_for_mpi.sh

# On each compute node (after head node completes)
bash setup_ssh_for_mpi.sh
```

### Terraform Integration

Add to your Terraform deployment scripts:

#### Head Node (runs first)

```hcl
resource "null_resource" "headnode_ssh_setup" {
  depends_on = [null_resource.headnode_deployment]
  
  provisioner "remote-exec" {
    inline = [
      "curl -o /tmp/setup_ssh_for_mpi.sh https://your-repo/setup_ssh_for_mpi.sh",
      "chmod +x /tmp/setup_ssh_for_mpi.sh",
      "bash /tmp/setup_ssh_for_mpi.sh"
    ]
    
    connection {
      type = "ssh"
      user = "crew"
      host = self.public_ip
    }
  }
}
```

#### Compute Nodes (run after head node)

```hcl
resource "null_resource" "compute_ssh_setup" {
  count      = var.compute_node_count
  depends_on = [null_resource.headnode_ssh_setup]
  
  provisioner "remote-exec" {
    inline = [
      "curl -o /tmp/setup_ssh_for_mpi.sh https://your-repo/setup_ssh_for_mpi.sh",
      "chmod +x /tmp/setup_ssh_for_mpi.sh",
      "bash /tmp/setup_ssh_for_mpi.sh"
    ]
    
    connection {
      type = "ssh"
      user = "crew"
      host = element(aws_instance.compute.*.public_ip, count.index)
    }
  }
}
```

### Cloud-Init / User Data

For automatic execution during VM initialization:

```yaml
#cloud-config
runcmd:
  - curl -o /tmp/setup_ssh_for_mpi.sh https://your-repo/setup_ssh_for_mpi.sh
  - chmod +x /tmp/setup_ssh_for_mpi.sh
  - sudo -u crew bash /tmp/setup_ssh_for_mpi.sh
```

## How It Works

### Detection Logic

The script automatically detects node type:
- **Head Node**: Detected by presence of `/NODUS/.is_headnode` file
- **Compute Node**: All other nodes

### Key Steps

1. **User Check**: Ensures `svanteuser` exists
2. **SSH Directory**: Creates `~/.ssh` with proper permissions (700)
3. **Key Generation**: Generates 4096-bit RSA key pair
4. **Self-Authorization**: Adds own public key to `authorized_keys`
5. **SSH Config**: Creates config with `StrictHostKeyChecking no`
6. **Known Hosts**: Scans all cluster nodes and adds to `known_hosts`
7. **Key Distribution** (head node only): Distributes keys to compute nodes
8. **Connectivity Test**: Tests SSH to all nodes

### Files Created

All files are created in `/home/svanteuser/.ssh/`:

- `id_rsa` - Private key (600 permissions)
- `id_rsa.pub` - Public key (644 permissions)
- `authorized_keys` - Authorized public keys (600 permissions)
- `known_hosts` - Trusted host keys (600 permissions)
- `config` - SSH client configuration (600 permissions)

## Configuration

Edit the script to customize:

```bash
# Change MPI user (default: svanteuser)
MPI_USER="your_mpi_user"
```

## Verification

After running the script, verify SSH connectivity:

```bash
# Test from head node to compute node
sudo -u svanteuser ssh ac-2ee4-2-0 hostname

# Test from compute node to another compute node
sudo -u svanteuser ssh ac-2ee4-2-1 hostname
```

Expected output: the hostname of the remote node (no password prompt, no warnings)

## Troubleshooting

### Script fails with "sudo command not found"

Install sudo on the base image:
```bash
apt-get update && apt-get install -y sudo
```

### SSH tests show "FAILED"

This is normal if:
- Compute nodes are still deploying
- PBS is not fully configured
- Network is initializing

**Solution**: Re-run the script after all nodes are online

### "User svanteuser does not exist"

The script will automatically create the user. If this fails:
```bash
sudo useradd -m -s /bin/bash svanteuser
```

### PBS not returning node list

If `pbsnodes -a` fails, the script falls back to only configuring the current node. Ensure PBS is running:
```bash
sudo systemctl status pbs_server  # Head node
sudo systemctl status pbs_mom     # Compute nodes
```

## Integration with PBS Jobs

After running this script, MPI jobs should work across nodes:

```bash
#PBS -l nodes=2:ppn=48
...
mpiexec -np 96 --hostfile $PBS_NODEFILE ./your_mpi_program
```

No additional SSH configuration needed in the PBS script!

## Security Considerations

⚠️ **Important**: This script configures passwordless SSH and disables strict host key checking for ease of use in HPC clusters. Consider these security implications:

- **Passwordless SSH**: Any process running as `svanteuser` can SSH to other nodes
- **No Host Key Verification**: Vulnerable to MITM attacks (acceptable in trusted private networks)
- **Shared Keys**: All nodes use the same key pair (distributed from head node)

**Recommendations**:
- Use only on private, isolated networks
- Restrict `svanteuser` to MPI job execution only
- Consider implementing host-based authentication for production
- Use firewall rules to limit SSH access to cluster nodes only

## Support

For issues or questions:
- Check PBS logs: `/var/spool/torque/server_logs/`, `/var/spool/torque/mom_logs/`
- Check SSH logs: `/var/log/auth.log` or `/var/log/secure`
- Re-run script with more nodes deployed
- Verify NFS mounts if using shared home directories

## License

This script is provided as-is for use in PBS/Torque HPC clusters.
