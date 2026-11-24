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

# The build to run: the --compiler and --infra given to scripts/build_on_derecho.sh.
COMPILER=intel
INFRA=FMS2
MOM6=../../build/${COMPILER}-${INFRA}/mom6_build/config_src/drivers/solo_driver/MOM6
# A legacy ./build.sh build is at ../../bin/${COMPILER}/MOM6_using_${INFRA}/MOM6/MOM6 instead.

if [ ! -x "$MOM6" ]; then
    echo "No MOM6 executable at $MOM6." >&2
    echo "Build it with: scripts/build_on_derecho.sh --compiler ${COMPILER} --infra ${INFRA}" >&2
    exit 1
fi

mpiexec "$MOM6"
