# Multi-Node QE Script Improvements

## Changes Made to qe.pbs

### 1. Fixed Rank Calculation
**Before**: Used `$PBS_NP` (which might not be set)
**After**: Calculate from `$PBS_NODEFILE`: `NRANKS=$(wc -l < $PBS_NODEFILE)`

### 2. Updated OpenMPI Settings
**Before**:
```bash
export OMPI_MCA_btl="tcp,self"
export OMPI_MCA_pml="cm"
```

**After**:
```bash
export OMPI_MCA_btl="^openib"  # Disable IB, use TCP
export OMPI_MCA_btl_tcp_if_include="eth0"  # Specify network interface
unset OMPI_MCA_pml  # Remove potentially conflicting setting
```

**Note**: You may need to adjust `eth0` to match your actual network interface. Check with:
```bash
ip addr show
```

### 3. Improved mpiexec Command
**Before**: `-n $PBS_NP`
**After**: `-np $NRANKS --hostfile $PBS_NODEFILE --map-by node:PE=1`

- `--hostfile`: Explicitly use PBS nodefile
- `--map-by node:PE=1`: Map processes to nodes, 1 processing element per rank

### 4. Added MPI Connectivity Test
Before running QE, test if MPI can reach all nodes:
```bash
mpiexec -np $NRANKS --hostfile $PBS_NODEFILE hostname
```

### 5. Enhanced Error Reporting
- Check if output files exist before displaying
- Show both STDOUT and STDERR
- More detailed success/failure messages

## Next Steps

1. **Copy script to cluster**:
   ```bash
   scp qe.pbs oddcadmin2@52.170.77.13:/home/svanteuser/
   ```

2. **Submit job**:
   ```bash
   ssh oddcadmin2@52.170.77.13
   cd /home/svanteuser
   qsub qe.pbs
   ```

3. **Monitor**:
   ```bash
   qstat -a
   tail -f qe_96cores_WORKING.out
   ```

## Common Issues to Check

### If MPI test fails:
- Check SSH connectivity between nodes: `ssh ac-2ee4-2-1 hostname`
- Verify network interface name matches `OMPI_MCA_btl_tcp_if_include`
- Check firewall rules

### If QE fails but MPI works:
- Verify Spack environment on all nodes: `ssh ac-2ee4-2-1 "source /spack/share/spack/setup-env.sh && which pw.x"`
- Check shared filesystem access: `ssh ac-2ee4-2-1 "ls -la /mnt/nfs/svanteuser/qe_run"`

### Network Interface Detection
Run on head node:
```bash
ip addr show | grep "inet " | grep -v "127.0.0.1"
```

Common interface names:
- `eth0`, `ens3`, `enp0s3` - Ethernet
- `ib0` - InfiniBand
- `bond0` - Bonded interfaces

Update the script if needed:
```bash
export OMPI_MCA_btl_tcp_if_include="YOUR_INTERFACE_NAME"
```
