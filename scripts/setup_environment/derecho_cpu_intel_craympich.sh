#!/bin/bash
# scripts/setup_environment/derecho_cpu_intel_craympich.sh
#
# SOURCED.  Stage-1 (environment setup) toolchain step ONLY: loads Derecho's
# CPU / Intel oneAPI / Cray MPICH toolchain via Lmod (compiler, CMake, MPI,
# NetCDF, ParallelIO).  Builds nothing; same contract as
# derecho_cpu_gcc_openmpi.sh.  build_on_derecho.sh --compiler intel sources it.
#
# Usage:  source scripts/setup_environment/derecho_cpu_intel_craympich.sh

# --- Toolchain (Stage 1 env setup; Tier 1) -----------------------------
# The same modules as build.sh's intel case.
module --force purge
module load ncarenv/25.10
module load intel/2025.2.1 ncarcompilers/1.1.0 cray-mpich/8.1.32 hdf5/1.14.6 netcdf/4.9.3 parallelio/2.6.8 cmake

# Name the compilers, so CMake cannot pick up a different one from PATH.
export CC=icx CXX=icpx FC=ifx
