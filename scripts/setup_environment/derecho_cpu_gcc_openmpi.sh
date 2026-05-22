#!/bin/bash
# scripts/setup_environment/derecho_cpu_gcc_openmpi.sh
#
# SOURCED.  Loads Derecho's CPU/gcc/OpenMPI toolchain via Lmod, then builds
# FMS/pFUnit/AMReX/TIM from source via build_dep.  Buildable-dep source
# defaults: $<NAME>_ROOT if exported (e.g. by fetch_source.sh or the user),
# else the corresponding turbo-stack submodule.
#
# Options (passed as sourced args, typically by an orchestrator):
#   --deps-build-root DIR    Where the from-source dep cmake builds + installs
#                            land ($DIR/build/<name>/ and $DIR/install/).
#                            Default: $TURBO_STACK_ROOT/deps/default.

# --- Parse sourced args -----------------------------------------------
_deps_build_root=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --deps-build-root) _deps_build_root="$2"; shift 2 ;;
        *)
            echo "Error: unknown option '$1' to derecho_cpu_gcc_openmpi.sh" >&2
            return 1 2>/dev/null || exit 1
            ;;
    esac
done

# --- Toolchain ---------------------------------------------------------
module purge
module load gcc cmake openmpi netcdf #pfunit

# Temporary fix to get the right c++ standard library picked up for TIM, which
# is built with gcc 14.3.0 on Derecho but the default compiler is still older
# gcc.
export LIBRARY_PATH=/glade/u/apps/common/25.10/spack/opt/spack/gcc/14.3.0/nw2m/lib64:$LIBRARY_PATH

# --- Dependency builds -------------------------------------------------
# Deps build + install location comes from the --deps-build-root sourced arg
# (parsed above); default is inside the turbo-stack source tree at deps/default.
: "${_deps_build_root:=$TURBO_STACK_ROOT/deps/default}"
_install_prefix="$_deps_build_root/install"
_build_root="$_deps_build_root/build"

# Parallelism is governed by $CMAKE_BUILD_PARALLEL_LEVEL (set by the
# orchestrator).  cmake --build reads it natively -- no plumbing needed here.
source "$TURBO_STACK_ROOT/scripts/build_dep.sh"

build_dep fms \
    --build-dir "$_build_root/fms" \
    --install-prefix "$_install_prefix" \
    -- -D64BIT=ON -D32BIT=OFF -DFPIC=ON -DOPENMP=OFF

build_dep pfunit \
    --build-dir "$_build_root/pfunit" \
    --install-prefix "$_install_prefix" \
    -- -DSKIP_MPI=NO -DSKIP_ESMF=YES -DENABLE_TESTS=OFF

build_dep amrex \
    --build-dir "$_build_root/amrex" \
    --install-prefix "$_install_prefix" \
    -- -DAMReX_FORTRAN=ON -DAMReX_FORTRAN_INTERFACES=ON -DAMReX_MPI=ON

build_dep tim \
    --build-dir "$_build_root/tim" \
    --install-prefix "$_install_prefix" \
    -- -D64BIT=ON -D32BIT=OFF

unset _deps_build_root _install_prefix _build_root
