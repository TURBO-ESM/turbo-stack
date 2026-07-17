#!/bin/bash
# scripts/setup_environment/local_toolchain_on_path.sh
#
# SOURCED.  Stage-1 (environment setup) toolchain step for a generic local
# machine (laptop / workstation) where you bring your OWN toolchain: compilers,
# MPI, NetCDF, and CMake are already on PATH -- installed however you like
# (system packages / Homebrew / an OS module system / an already-activated Spack
# or Conda env).  This recipe does NOT install or build anything; it only
# VERIFIES that the toolchain is present and reports what it found, so a missing
# compiler surfaces as one clear error here instead of a confusing failure deep
# in a dependency build.  The upstream submodule deps (AMReX/pFUnit = Tier 1.5;
# FMS/TIM = Tier 2) are built explicitly by the caller via the turbo_build_*
# wrappers in scripts/lib/common.sh.  See docs/dependency_tiers_prompt.md.
#
# This is the toolchain counterpart to the other Stage-1 recipes:
#   - spack_local_environment.sh   -- toolchain from a Spack env
#   - derecho_cpu_gcc_openmpi.sh   -- toolchain from Lmod modules
#   - local_toolchain_on_path.sh   -- toolchain already on PATH (this file)
#
# Prepare your toolchain BEFORE sourcing this (any one of):
#   module load <compiler> <mpi> <netcdf> cmake     # an OS module system
#   spack env activate <env>                        # an existing Spack env
#   brew install gcc open-mpi netcdf netcdf-fortran cmake   # macOS Homebrew
#   sudo apt install gfortran libopenmpi-dev libnetcdf-dev libnetcdff-dev cmake  # Debian/Ubuntu
#
# Usage:  source scripts/setup_environment/local_toolchain_on_path.sh

# --- Toolchain (Stage 1 env setup; Tier 1) -- verify only, build nothing ------
# turbo-stack + every from-source dep (FMS, TIM, AMReX, pFUnit) build MPI-parallel
# Fortran / C / C++, so the MPI compiler wrappers and cmake are the hard
# requirements; NetCDF is checked but only warned about (CMake's FindNetCDF can
# locate it by other means, e.g. via CMAKE_PREFIX_PATH).
_turbo_missing=()

# A Fortran MPI wrapper: OpenMPI ships mpifort (mpif90 is the older alias);
# MPICH ships both. Accept either.
_turbo_fc=""
for _c in mpifort mpif90; do
    if command -v "$_c" >/dev/null 2>&1; then _turbo_fc="$_c"; break; fi
done
[[ -z "$_turbo_fc" ]] && _turbo_missing+=("a Fortran MPI compiler (mpifort or mpif90)")

# A C++ MPI wrapper: OpenMPI/MPICH ship both mpicxx and mpic++.
_turbo_cxx=""
for _c in mpicxx mpic++; do
    if command -v "$_c" >/dev/null 2>&1; then _turbo_cxx="$_c"; break; fi
done
[[ -z "$_turbo_cxx" ]] && _turbo_missing+=("a C++ MPI compiler (mpicxx or mpic++)")

command -v mpicc >/dev/null 2>&1 || _turbo_missing+=("mpicc")
command -v cmake >/dev/null 2>&1 || _turbo_missing+=("cmake")

if [[ ${#_turbo_missing[@]} -gt 0 ]]; then
    echo "Error: your local toolchain is incomplete -- these are not on PATH:" >&2
    for _m in "${_turbo_missing[@]}"; do echo "         - $_m" >&2; done
    echo "       Install or activate your toolchain first, then re-run.  Examples:" >&2
    echo "         module load <compiler> <mpi> <netcdf> cmake      # an OS module system" >&2
    echo "         spack env activate <env>                         # an existing Spack env" >&2
    echo "         brew install gcc open-mpi netcdf netcdf-fortran cmake              # macOS" >&2
    echo "         sudo apt install gfortran libopenmpi-dev libnetcdf-dev libnetcdff-dev cmake  # Debian/Ubuntu" >&2
    echo "       (Prefer Spack for the whole toolchain? Use build_local_with_spack_env.sh instead.)" >&2
    unset _turbo_missing _turbo_fc _turbo_cxx _c _m
    return 1 2>/dev/null || exit 1
fi

echo "[local-toolchain] using the toolchain already on PATH (built nothing):"
printf '    %-9s %s\n' "cmake:"   "$(command -v cmake) ($(cmake --version 2>/dev/null | head -1))"
printf '    %-9s %s\n' "Fortran:" "$(command -v "$_turbo_fc")"
printf '    %-9s %s\n' "C:"       "$(command -v mpicc)"
printf '    %-9s %s\n' "C++:"     "$(command -v "$_turbo_cxx")"
if command -v nf-config >/dev/null 2>&1; then
    printf '    %-9s %s\n' "NetCDF-F:" "$(command -v nf-config) ($(nf-config --version 2>/dev/null))"
elif command -v nc-config >/dev/null 2>&1; then
    printf '    %-9s %s\n' "NetCDF:"  "$(command -v nc-config)"
else
    echo "[local-toolchain] warning: no nf-config / nc-config on PATH." >&2
    echo "                  If find_package(NetCDF) fails during configure, put your" >&2
    echo "                  NetCDF install prefix on CMAKE_PREFIX_PATH and re-run." >&2
fi

unset _turbo_missing _turbo_fc _turbo_cxx _c _m
