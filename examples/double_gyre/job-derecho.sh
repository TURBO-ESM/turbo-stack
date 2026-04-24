#!/bin/bash
#PBS -N mom6_standalone
#PBS -A NCGD0067
#PBS -j oe
#PBS -k eod
#PBS -q main
#PBS -l walltime=00:05:00
#PBS -l select=1:ncpus=4:mpiprocs=4

### Set temp to scratch
export TMPDIR=${SCRATCH}/${USER}/temp && mkdir -p $TMPDIR

COMPILER=gnu
INFRA=TIM

#LEVEL 0
# export PPM_LIMIT_POS_MODE="FORTRAN"
# export PPM_LIMIT_POS_MODE="CAPTURE"
# export PPM_LIMIT_POS_MODE="AMREX"

#LEVEL 1
#export PPM_RECONSTRUCTION_Y_MODE="CAPTURE"
export PPM_RECONSTRUCTION_Y_MODE="AMREX"
mpiexec ../../bin/${COMPILER}/MOM6_using_${INFRA}/MOM6/MOM6
