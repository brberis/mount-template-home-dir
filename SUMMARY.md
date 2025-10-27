# PBS/Torque + Singularity/E4S Quantum ESPRESSO - Summary

## ✅ WORKING SOLUTION

**File**: `quantum_expresso_SIMPLE_WORKING.pbs`

**Configuration**:
- Single node: 48 cores
- PBS/Torque compatible (works with Moab)
- E4S container with Intel MPI
- Verified successful execution

**Usage**:
```bash
qsub quantum_expresso_SIMPLE_WORKING.pbs
```

## ❌ MULTI-NODE STATUS

Multi-node execution (96+ cores across 2+ nodes) **does not work** due to fundamental incompatibility between:
- PBS/Torque job launcher
- Singularity containers  
- Intel MPI remote process launching

**Problem**: When Intel MPI inside a container tries to SSH to remote nodes, the remote processes start **outside** the container, causing path/library mismatches.

**Attempted Solutions** (all failed):
1. SSH bootstrap with wrapper scripts
2. Custom launcher scripts
3. PBS nodefile binding
4. TCP fabric configuration
5. Pre-launched container daemons
6. Various I_MPI environment variables

**Jobs Tested**: 4700022-4700036 (all multi-node attempts failed)

## RECOMMENDATIONS

1. **For immediate use**: Use single-node solution (`quantum_expresso_SIMPLE_WORKING.pbs`)
2. **For multi-node**: Discuss with HPC team about:
   - Migrating to Slurm (best solution)
   - Installing host MPI compatible with container
   - Upgrading to Apptainer/Singularity CE 4.0+

## VERIFIED WORKING TEST

```
Job: 4700037.svanteibm
Result: ✅ SUCCESS
Output: JOB DONE.
Cores: 48 (single node)
Runtime: 0.81s wall time
```

The single-node solution is production-ready and maintains PBS/Torque/Moab integration.
