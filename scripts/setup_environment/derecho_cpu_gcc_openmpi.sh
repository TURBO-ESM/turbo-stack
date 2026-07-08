#!/bin/bash
# scripts/setup_environment/derecho_cpu_gcc_openmpi.sh
#
# SOURCED.  Stage-1 (environment setup) toolchain step ONLY: loads Derecho's
# CPU / gcc / OpenMPI toolchain via Lmod (compiler, CMake, MPI, NetCDF).  It does
# NOT build any dependencies and has no side effects beyond preparing the shell --
# the upstream submodule deps (AMReX/pFUnit = Tier 1.5; FMS/TIM = Tier 2) are built
# explicitly by the caller via the turbo_build_* wrappers in scripts/lib/common.sh.
# See docs/dependency_tiers_prompt.md for the tier model.
#
# Usage:  source scripts/setup_environment/derecho_cpu_gcc_openmpi.sh

# --- Toolchain (Stage 1 env setup; Tier 1) -----------------------------
module purge
module load gcc cmake openmpi netcdf #pfunit

# Temporary fix so the correct C++ standard library is picked up for TIM, which
# is built with gcc 14.3.0 on Derecho while the default compiler is still older.
# ${LIBRARY_PATH:-} keeps this safe under `set -u`.
export LIBRARY_PATH=/glade/u/apps/common/25.10/spack/opt/spack/gcc/14.3.0/nw2m/lib64${LIBRARY_PATH:+:$LIBRARY_PATH}
