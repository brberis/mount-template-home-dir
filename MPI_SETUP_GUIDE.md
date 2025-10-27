# MPI Setup Guide for AWS/Rocky Linux 9 Cluster

## Overview

This guide addresses MPI (Message Passing Interface) setup on AWS EC2 instances running Rocky Linux 9, specifically dealing with CPU instruction set compatibility issues.

---

## The Problem: AVX-512 vs AVX2

### Symptom
```bash
$ mpiexec ./myprogram
Illegal instruction (core dumped)
```

### Root Cause

Some MPI libraries are compiled with **AVX-512** instructions (`-mavx512f` compiler flag), but many AWS EC2 instances use older CPUs that only support **AVX2**.

**Example:**
- **CPU:** Intel Xeon E5-2686 v4 (common on AWS)
- **Supports:** SSE2, AVX, AVX2
- **Does NOT support:** AVX-512

When you run MPI code compiled with AVX-512 on an AVX2-only CPU, you get an "Illegal instruction" error.

---

## Diagnosis

### Check Your CPU Capabilities

```bash
lscpu | grep -E "Model name|Flags"
```

**Look for:**
- `avx` - AVX support (good)
- `avx2` - AVX2 support (good)
- `avx512f` - AVX-512 support (needed for some MPI builds)

**Example output (AVX2 but no AVX-512):**
```
Model name:                              Intel(R) Xeon(R) CPU E5-2686 v4 @ 2.30GHz
Flags:                                   ... avx f16c ... avx2 ... (no avx512f)
```

### Check MPI Compilation Flags

```bash
mpicc --version
mpiexec --version
```

Look for compilation flags like `-mavx512f` in the output.

**Example problematic output:**
```
CFLAGS= -DNDEBUG -msse2 -mavx -mavx512f -O3
```

This MPI was compiled with AVX-512 and won't work on AVX2-only CPUs.

---

## Solution: Use Compatible MPI

### Option 1: Amazon OpenMPI (Recommended for AWS)

Amazon provides OpenMPI builds optimized for AWS hardware.

**Location:** `/opt/amazon/openmpi/` or `/opt/amazon/openmpi5/`

**Setup:**
```bash
export PATH=/opt/amazon/openmpi/bin:$PATH
export LD_LIBRARY_PATH=/opt/amazon/openmpi/lib64:$LD_LIBRARY_PATH
```

**Add to your `.bashrc` or job scripts:**
```bash
# Add to ~/.bashrc
echo 'export PATH=/opt/amazon/openmpi/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/opt/amazon/openmpi/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc
```

### Option 2: System OpenMPI

Rocky Linux 9 includes OpenMPI packages, though they may have PMIx compatibility issues with Slurm.

**Location:** `/usr/lib64/openmpi/`

**Setup:**
```bash
export PATH=/usr/lib64/openmpi/bin:$PATH
export LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:$LD_LIBRARY_PATH
```

### Check Available MPI Installations

```bash
# List all MPI installations
ls -la /opt/amazon/openmpi*/bin/mpicc 2>/dev/null
ls -la /usr/lib64/openmpi/bin/mpicc 2>/dev/null
ls -la /usr/local/mvapich*/bin/mpicc 2>/dev/null

# Test each one
/opt/amazon/openmpi/bin/mpicc --version
```

---

## MPI Configuration for Slurm Jobs

### Update Compilation Script

**Before (problematic):**
```bash
#!/bin/bash
# Uses whatever mpicc is in PATH (might be AVX-512)
mpicc -o myprogram myprogram.c
```

**After (correct):**
```bash
#!/bin/bash
# Explicitly use Amazon OpenMPI
export PATH=/opt/amazon/openmpi/bin:$PATH
mpicc -o myprogram myprogram.c
```

### Update Slurm Batch Script

**Before (problematic):**
```bash
#!/bin/bash
#SBATCH --nodes=2
#SBATCH --ntasks=4

mpiexec ./myprogram  # Might use wrong MPI
```

**After (correct):**
```bash
#!/bin/bash
#SBATCH --nodes=2
#SBATCH --ntasks=4

# Set MPI paths
export PATH=/opt/amazon/openmpi/bin:$PATH
export LD_LIBRARY_PATH=/opt/amazon/openmpi/lib64:$LD_LIBRARY_PATH

# Use mpirun (OpenMPI) instead of mpiexec
mpirun ./myprogram
```

---

## Complete Example: MPI Hello World

### 1. Create MPI Program

```c
// mpiprocname.c
#include "mpi.h"
#include <stdio.h>

int main(int argc, char *argv[])
{
    int rank, nprocs, len;
    char name[MPI_MAX_PROCESSOR_NAME];

    MPI_Init(&argc, &argv);
    MPI_Comm_size(MPI_COMM_WORLD, &nprocs);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Get_processor_name(name, &len);
    
    printf("Hello, world. I am %d of %d on %s\n", rank, nprocs, name);
    fflush(stdout);
    
    MPI_Finalize();
    return 0;
}
```

### 2. Create Compilation Script

```bash
#!/bin/bash
# compile.sh
set -x
export PATH=/opt/amazon/openmpi/bin:$PATH
mpicc -o mpiprocname mpiprocname.c
```

### 3. Create Slurm Batch Script

```bash
#!/bin/bash
# mpiprocname.sbatch
#SBATCH --job-name=mpiprocname
#SBATCH --nodes=2
#SBATCH --ntasks=4
#SBATCH --ntasks-per-node=2
#SBATCH --time=0-0:02

export PATH=/opt/amazon/openmpi/bin:$PATH
export LD_LIBRARY_PATH=/opt/amazon/openmpi/lib64:$LD_LIBRARY_PATH

mpirun ./mpiprocname
```

### 4. Compile and Run

```bash
chmod +x compile.sh
./compile.sh
sbatch mpiprocname.sbatch
```

### 5. Check Output

```bash
cat slurm-*.out
```

**Expected Output:**
```
Hello, world. I am 0 of 4 on ac-9726-0-0
Hello, world. I am 1 of 4 on ac-9726-0-0
Hello, world. I am 2 of 4 on ac-9726-0-1
Hello, world. I am 3 of 4 on ac-9726-0-1
```

---

## Troubleshooting

### Issue: "Illegal instruction"
**Cause:** MPI compiled with unsupported CPU instructions (AVX-512)  
**Fix:** Use Amazon OpenMPI or rebuild with compatible flags

### Issue: "cannot open shared object file"
**Cause:** MPI libraries not in LD_LIBRARY_PATH  
**Fix:** 
```bash
export LD_LIBRARY_PATH=/opt/amazon/openmpi/lib64:$LD_LIBRARY_PATH
```

### Issue: PMIx errors with OpenMPI
```
mca_base_component_repository_open: unable to open mca_pmix_ext3x
```
**Cause:** Version mismatch between OpenMPI and Slurm's PMIx  
**Fix:** Use Amazon OpenMPI which is compatible with AWS's Slurm setup

### Issue: MPI processes don't start on all nodes
**Cause:** Slurm configuration issue (see NIS_SLURM_SETUP.md)  
**Fix:** Ensure NodeAddr is set in slurm.conf

---

## Testing MPI Setup

### Quick Test
```bash
# Single node test
srun --nodes=1 --ntasks=2 hostname

# Multi-node test
srun --nodes=2 --ntasks=4 hostname
```

### MPI Communication Test
```bash
# Compile test program
export PATH=/opt/amazon/openmpi/bin:$PATH
mpicc -o mpi_test mpiprocname.c

# Run directly with srun
srun --nodes=2 --ntasks=4 ./mpi_test
```

---

## Summary

| MPI Installation | Path | Recommended | Notes |
|-----------------|------|-------------|-------|
| Amazon OpenMPI 4.x | `/opt/amazon/openmpi/` | ✅ Yes | Best for AWS, AVX2 compatible |
| Amazon OpenMPI 5.x | `/opt/amazon/openmpi5/` | ✅ Yes | Newer version |
| System OpenMPI | `/usr/lib64/openmpi/` | ⚠️ Maybe | May have PMIx issues |
| mvapich4-plus | `/usr/local/mvapich4-plus/` | ❌ No | Compiled with AVX-512 |

**Recommendation:** Always use Amazon OpenMPI (`/opt/amazon/openmpi/`) on AWS EC2 instances.

---

## Related Documentation

- [NIS_SLURM_SETUP.md](NIS_SLURM_SETUP.md) - Complete cluster setup
- [QUICK_REFERENCE_NIS_SLURM.md](QUICK_REFERENCE_NIS_SLURM.md) - Quick reference
- [VERIFICATION_RESULTS.md](VERIFICATION_RESULTS.md) - Test results

---

**Last Updated:** October 27, 2025  
**Cluster:** rocky9-e4s (Intel Xeon E5-2686 v4)  
**Tested with:** Amazon OpenMPI 4.1.7, Slurm 23.11.4
