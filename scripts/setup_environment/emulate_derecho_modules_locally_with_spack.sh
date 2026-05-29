#!/bin/bash
# scripts/setup_environment/emulate_derecho_modules_locally_with_spack.sh
#
# SOURCED. Temporary driver that emulates a module-based machine (Derecho)
# on the laptop. Uses spack ONLY for the parts that come from Lmod on
# Derecho -- compiler, MPI, NetCDF, CMake. FMS, pFUnit, AMReX, and TIM are
# built from source via build_dep; MOM6 source comes from $MOM6_ROOT
# (or submodule if unset).
#
# Once scripts/setup_environment/derecho_cpu_gcc_openmpi.sh is verified against
# real Lmod modules, delete this file and spack/derecho_modules_emulation_with_spack.yaml.
#
# Usage:
#   source scripts/setup_environment/emulate_derecho_modules_locally_with_spack.sh [options]
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
            echo "Error: unknown option '$1' to emulate_derecho_modules_locally_with_spack.sh" >&2
            return 1 2>/dev/null || exit 1
            ;;
    esac
done

if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
    echo "Error: TURBO_STACK_ROOT is not set." >&2
    return 1 2>/dev/null || exit 1
fi
if [[ -z "${SPACK_ROOT:-}" ]]; then
    echo "Error: SPACK_ROOT is not set." >&2
    return 1 2>/dev/null || exit 1
fi
if [[ ! -f "$SPACK_ROOT/share/spack/setup-env.sh" ]]; then
    echo "Error: SPACK_ROOT ($SPACK_ROOT) is not a valid Spack installation." >&2
    return 1 2>/dev/null || exit 1
fi

# shellcheck source=/dev/null
source "$SPACK_ROOT/share/spack/setup-env.sh"

_emu_env="derecho_modules_emulation_with_spack"
_emu_yaml="$TURBO_STACK_ROOT/spack/${_emu_env}.yaml"

if ! spack env list | grep -qw "$_emu_env"; then
    echo "Error: spack env '$_emu_env' does not exist." >&2
    echo "Create it once with:" >&2
    echo "  bash $TURBO_STACK_ROOT/spack/create_spack_environment.sh $_emu_env $_emu_yaml" >&2
    unset _emu_env _emu_yaml
    return 1 2>/dev/null || exit 1
fi

if ! spack env activate "$_emu_env"; then
    echo "Error: failed to activate spack env '$_emu_env'" >&2
    unset _emu_env _emu_yaml
    return 1 2>/dev/null || exit 1
fi

unset _emu_env _emu_yaml

# --- Dependency builds -------------------------------------------------
# Build FMS / pFUnit / AMReX / TIM from source via build_dep.  Source for each
# defaults to the submodule unless $<NAME>_ROOT is exported by the caller.
# Deps build + install location comes from the --deps-build-root sourced arg
# (parsed above); default is inside the turbo-stack source tree at deps/default.
: "${_deps_build_root:=$TURBO_STACK_ROOT/deps/default}"
_install_prefix="$_deps_build_root/install"
_build_root="$_deps_build_root/build"

# Parallelism is governed by $CMAKE_BUILD_PARALLEL_LEVEL (set by the
# orchestrator).  cmake --build reads it natively -- no plumbing needed here.
# shellcheck source=/dev/null
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
    -- -DAMReX_FORTRAN=ON -DAMReX_FORTRAN_INTERFACES=ON -DAMReX_MPI=ON \
       -DAMReX_TINY_PROFILE=ON

build_dep tim \
    --build-dir "$_build_root/tim" \
    --install-prefix "$_install_prefix" \
    -- -D64BIT=ON -D32BIT=OFF

unset _deps_build_root _install_prefix _build_root
