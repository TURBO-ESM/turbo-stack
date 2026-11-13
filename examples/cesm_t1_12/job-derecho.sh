#!/bin/bash
#PBS -N mom6_cesm_t1_12
#PBS -A NCGD0067
#PBS -j oe
#PBS -k eod
#PBS -q main
#PBS -l walltime=01:00:00
#PBS -l select=60:ncpus=128:mpiprocs=128

COMPILER=intel
INFRA=FMS2
EXAMPLE_DIR=$PBS_O_WORKDIR
EXE=$EXAMPLE_DIR/../../bin/${COMPILER}/MOM6_using_${INFRA}/MOM6/MOM6
RUNDIR=${RUNDIR:-/glade/derecho/scratch/$USER/turbo_perf/cesm_t1_12_${INFRA}}

module reset
module load ncarenv/25.10 intel/2025.2.1 ncarcompilers/1.1.0 hdf5/1.14.6 netcdf/4.9.3 parallelio/2.6.8
export TMPDIR=/glade/derecho/scratch/$USER/temp && mkdir -p "$TMPDIR"

mkdir -p "$RUNDIR/RESTART" && cd "$RUNDIR" || exit 1
cp "$EXAMPLE_DIR"/{MOM_input,MOM_override,diag_table,input.nml,MOM_mask_table} .
ln -sfn "$(readlink -f "$EXAMPLE_DIR/INPUT")" INPUT
mpiexec "$EXE"
