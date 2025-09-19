#!/bin/bash
#PBS -N mom6_standalone
#PBS -A <PROJECT_CODE>
#PBS -j oe
#PBS -k eod
#PBS -q main
#PBS -l walltime=00:15:00
#PBS -l select=4:ncpus=128:mpiprocs=128

### Set temp to scratch
export TMPDIR=${SCRATCH}/${USER}/temp && mkdir -p $TMPDIR

if [ ! -d /glade/work/altuntas/mom6.standalone.runs/cesm/INPUT/t232/ ]; then
    echo "Could not find the MOM6 input directory. This likely means that you don't have access to glade."
    echo "This example is currently set up to run on derecho or casper only."
    exit 1
fi

COMPILER=intel

mpiexec ../../bin/${COMPILER}/MOM6/MOM6
