#!/bin/bash
#PBS -N mom6_standalone
#PBS -A NCGD0067
#PBS -j oe
#PBS -k eod
#PBS -q main
#PBS -l walltime=00:15:00
#PBS -l select=6:ncpus=128:mpiprocs=128
#PBS -l job_priority=premium

### Set temp to scratch
export TMPDIR=${SCRATCH}/${USER}/temp && mkdir -p $TMPDIR

COMPILER=intel

mpiexec ../../bin/${COMPILER}/MOM6/MOM6
