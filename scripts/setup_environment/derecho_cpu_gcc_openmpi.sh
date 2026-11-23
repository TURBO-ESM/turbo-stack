#!/bin/bash
# scripts/setup_environment/derecho_cpu_gcc_openmpi.sh
#
# SOURCED.  Stage-1 (environment setup) toolchain step ONLY: loads Derecho's
# CPU / gcc / OpenMPI toolchain via Lmod (compiler, CMake, MPI, NetCDF, ParallelIO).
# NOT build any dependencies and has no side effects beyond preparing the shell --
# the upstream submodule deps (AMReX/pFUnit = Layer 2; FMS/TIM = Layer 3) are built
# explicitly by the caller via the turbo_build_* wrappers in scripts/lib/common.sh.
# See docs/dependency_layers_prompt.md for the layer model.
#
# Usage:  source scripts/setup_environment/derecho_cpu_gcc_openmpi.sh

# --- Toolchain (Stage 1 env setup; Layer 1) -----------------------------
module purge
module load gcc cmake openmpi netcdf parallelio #pfunit

# Temporary fix so the correct C++ standard library is picked up for TIM, which
# is built with gcc 14.3.0 on Derecho while the default compiler is still older.
# ${LIBRARY_PATH:-} keeps this safe under `set -u`.
export LIBRARY_PATH=/glade/u/apps/common/25.10/spack/opt/spack/gcc/14.3.0/nw2m/lib64${LIBRARY_PATH:+:$LIBRARY_PATH}
