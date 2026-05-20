#!/bin/bash
#PBS -A NCGD0067
#PBS -N mom6_standalone_gpu
#PBS -q main
#PBS -l walltime=00:03:00
#PBS -l select=1:ncpus=4:mpiprocs=4:ngpus=4

# Load modules to match compile-time environment
module load ncarenv/25.10 cuda/12.9.0 hdf5/1.14.6 nvhpc/25.9 ncarcompilers/1.1.0 netcdf/4.9.3

### Set temp to scratch
export TMPDIR=${SCRATCH}/${USER}/temp && mkdir -p $TMPDIR

COMPILER=nvhpc
INFRA=TIM

mpiexec -n 4 -ppn 4 set_gpu_rank ../../bin/${COMPILER}/MOM6_using_${INFRA}/MOM6/MOM6