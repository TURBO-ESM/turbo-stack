#!/bin/bash
#PBS -A NCGD0067
#PBS -N mom6_standalone_gpu
#PBS -q main
#PBS -l walltime=00:03:00
#PBS -l select=1:ncpus=16:mpiprocs=2:ngpus=2

# Load modules to match compile-time environment
module load cuda/12.9.0 nvhpc/25.9 cray-mpich/8.1.32

### Set temp to scratch
export TMPDIR=${SCRATCH}/${USER}/temp && mkdir -p $TMPDIR

COMPILER=nvhpc
INFRA=FMS2

# Serial version works:
../../bin/${COMPILER}/MOM6_using_${INFRA}/MOM6/MOM6

# # Multiple ranks with GPU offloading fails at day 2.
# mpiexec -n 2 -ppn 2 set_gpu_rank ../../bin/${COMPILER}/MOM6_using_${INFRA}/MOM6/MOM6