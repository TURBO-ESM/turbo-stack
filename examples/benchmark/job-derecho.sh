#!/bin/bash
#PBS -N mom6_standalone
#PBS -A NCGD0067
#PBS -j oe
#PBS -k eod
#PBS -q main
#PBS -l walltime=00:05:00
#PBS -l select=1:ncpus=32:mpiprocs=32

### Set temp to scratch
export TMPDIR=${SCRATCH}/${USER}/temp && mkdir -p $TMPDIR

COMPILER=intel
INFRA=FMS2

mpiexec ../../bin/${COMPILER}/MOM6_using_${INFRA}/MOM6/MOM6
