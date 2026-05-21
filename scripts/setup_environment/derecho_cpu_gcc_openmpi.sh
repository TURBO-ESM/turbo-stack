#!/bin/bash
# scripts/setup_environment/derecho_cpu_gcc_openmpi.sh
#
# SOURCED.  Loads Derecho's CPU/gcc/OpenMPI toolchain via Lmod, then builds
# FMS/pFUnit/AMReX/TIM from source via build_dep.  Buildable-dep source
# defaults: $<NAME>_ROOT if exported (e.g. by fetch_source.sh or the user),
# else the corresponding turbo-stack submodule.

# --- Toolchain ---------------------------------------------------------
module purge
module load gcc cmake openmpi netcdf #pfunit

# Temporary fix to get the right c++ standard library picked up for TIM, which
# is built with gcc 14.3.0 on Derecho but the default compiler is still older
# gcc.
export LIBRARY_PATH=/glade/u/apps/common/25.10/spack/opt/spack/gcc/14.3.0/nw2m/lib64:$LIBRARY_PATH

# --- Dependency builds -------------------------------------------------
# Where the from-source deps build and install.  Default lands inside the
# turbo-stack source tree at deps/default; callers (e.g. the PR-test driver)
# can override TURBO_DEPS_ROOT to redirect builds into an ephemeral scratch dir.
: "${TURBO_DEPS_ROOT:=$TURBO_STACK_ROOT/deps/default}"
_install_prefix="$TURBO_DEPS_ROOT/install"
_build_root="$TURBO_DEPS_ROOT/build"

# Forward --parallel from the orchestrator if it set TURBO_DEP_PARALLEL.
_parallel_args=()
[[ -n "${TURBO_DEP_PARALLEL:-}" ]] && _parallel_args=(--parallel "$TURBO_DEP_PARALLEL")

source "$TURBO_STACK_ROOT/scripts/build_dep.sh"

build_dep fms \
    --build-dir "$_build_root/fms" \
    --install-prefix "$_install_prefix" \
    "${_parallel_args[@]}" \
    -- -D64BIT=ON -D32BIT=OFF -DFPIC=ON -DOPENMP=OFF

build_dep pfunit \
    --build-dir "$_build_root/pfunit" \
    --install-prefix "$_install_prefix" \
    "${_parallel_args[@]}" \
    -- -DSKIP_MPI=NO -DSKIP_ESMF=YES -DENABLE_TESTS=OFF

build_dep amrex \
    --build-dir "$_build_root/amrex" \
    --install-prefix "$_install_prefix" \
    "${_parallel_args[@]}" \
    -- -DAMReX_FORTRAN=ON -DAMReX_FORTRAN_INTERFACES=ON -DAMReX_MPI=ON

build_dep tim \
    --build-dir "$_build_root/tim" \
    --install-prefix "$_install_prefix" \
    "${_parallel_args[@]}" \
    -- -D64BIT=ON -D32BIT=OFF

unset _install_prefix _build_root _parallel_args
