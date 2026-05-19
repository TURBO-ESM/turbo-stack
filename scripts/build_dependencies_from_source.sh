#!/bin/bash
# scripts/build_dependencies_from_source.sh
#
# SOURCED, not executed.  Builds turbo-stack's buildable dependencies from
# source into a per-tag prefix and exports the environment that
# build_turbo_stack.sh consumes.  Designed to be invoked by per-machine env
# scripts that have already loaded the toolchain (compiler, MPI, NetCDF,
# CMake).
#
# Source-tree discovery for each dependency:
#   1. If $<NAME>_ROOT is set in the environment, use that path.
#   2. Otherwise, fall back to the submodule at the standard location.
#
#   Dep             | <NAME>_ROOT  | Default submodule path
#   ----------------|--------------|---------------------------------------
#   MOM6 (consumed) | MOM6_ROOT    | submodules/MOM6
#   FMS  (built)    | FMS_ROOT     | submodules/infra/FMS2
#   TIM  (built)    | TIM_ROOT     | submodules/infra/TIM
#   pFUnit (built)  | PFUNIT_ROOT  | submodules/pFUnit
#   AMReX  (built)  | AMREX_ROOT   | submodules/amrex
#
# Each buildable dep can be toggled off independently -- useful when the
# active env already provides some of them.  For example, the spack flavor
# (scripts/build_with_spack.sh) gets FMS / pFUnit / AMReX from spack and only calls
# this script with `--only tim` to fill the TIM gap.
#
# Usage:
#   source scripts/build_dependencies_from_source.sh [options]
#
# Options:
#   --tag NAME      Per-toolchain prefix tag (default: default)
#                   Built artifacts go to $TURBO_STACK_ROOT/deps/<tag>/install
#   --prefix DIR    Override install prefix
#   --parallel N    Parallel build jobs (default: 1; -j N also accepted).  Pass
#   -j N            an explicit N to parallelize.  The default stays serial
#                   because `nproc` over-reports on shared login nodes and on
#                   PBS/SLURM allocations that don't pin cpusets -- the caller
#                   knows the right value, this script doesn't.
#   --rebuild       Force rebuild even if sentinel says "installed"
#   --no-fms        Skip building FMS
#   --no-pfunit     Skip building pFUnit
#   --no-amrex      Skip building AMReX
#   --no-tim        Skip building TIM
#   --only LIST     Comma-separated list of deps to build; others skipped.
#                     --only tim        -> build only TIM
#                     --only fms,tim    -> build FMS and TIM, skip the rest
#                   Valid names: fms, pfunit, amrex, tim.
#
# Required environment:
#   TURBO_STACK_ROOT   Path to your turbo-stack repository clone
#   A loaded toolchain (cmake + mpicc/mpif90 on PATH) -- typically set up
#   by a per-machine env script that sources this one (e.g. scripts/setup_environment/derecho.sh
#   or scripts/setup_environment/derecho_modules_emulation_with_spack.sh).

_tag="default"
_prefix=""
_parallel="1"
_rebuild=false
_build_fms=true
_build_pfunit=true
_build_amrex=true
_build_tim=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)          _tag="$2"; shift 2 ;;
        --prefix)       _prefix="$2"; shift 2 ;;
        --parallel|-j)  _parallel="$2"; shift 2 ;;
        --rebuild)      _rebuild=true; shift ;;
        --no-fms)    _build_fms=false; shift ;;
        --no-pfunit) _build_pfunit=false; shift ;;
        --no-amrex)  _build_amrex=false; shift ;;
        --no-tim)    _build_tim=false; shift ;;
        --only)
            _build_fms=false; _build_pfunit=false; _build_amrex=false; _build_tim=false
            IFS=',' read -ra _only_list <<< "$2"
            for _dep in "${_only_list[@]}"; do
                case "$_dep" in
                    fms)    _build_fms=true ;;
                    pfunit) _build_pfunit=true ;;
                    amrex)  _build_amrex=true ;;
                    tim)    _build_tim=true ;;
                    *)
                        echo "Error: unknown dep '$_dep' in --only (valid: fms, pfunit, amrex, tim)" >&2
                        unset _only_list _dep
                        return 1 2>/dev/null || exit 1
                        ;;
                esac
            done
            unset _only_list _dep
            shift 2 ;;
        *)
            echo "Error: unknown option '$1' to build_dependencies_from_source.sh" >&2
            return 1 2>/dev/null || exit 1
            ;;
    esac
done

# --- Validate toolchain & roots -----------------------------------------
if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
    echo "Error: TURBO_STACK_ROOT is not set." >&2
    return 1 2>/dev/null || exit 1
fi
if ! command -v cmake >/dev/null 2>&1; then
    echo "Error: cmake not found on PATH. Load the toolchain first (module load / spack activate)." >&2
    return 1 2>/dev/null || exit 1
fi
if ! command -v mpicc >/dev/null 2>&1 || ! command -v mpif90 >/dev/null 2>&1; then
    echo "Error: MPI wrappers (mpicc, mpif90) not on PATH. Load the MPI module first." >&2
    return 1 2>/dev/null || exit 1
fi

[[ -z "$_prefix" ]] && _prefix="$TURBO_STACK_ROOT/deps/$_tag/install"
_build_root="$TURBO_STACK_ROOT/deps/$_tag/build"
mkdir -p "$_build_root" "$_prefix"

# --- Helpers --------------------------------------------------------------
_ensure_submodule_initialized() {
    local sub_path="$1"
    if [[ ! -d "$sub_path" || -z "$(ls -A "$sub_path" 2>/dev/null)" ]]; then
        echo "[build_dependencies_from_source] Initializing submodule $sub_path ..."
        ( cd "$TURBO_STACK_ROOT" && git submodule update --init --recursive "$sub_path" ) || return 1
    fi
}

# _resolve_root <pretty-name> <env-var-name> <submodule-path>
# Sets the global $_resolved to the path to use.
_resolve_root() {
    local name="$1" envvar="$2" sub_path="$3"
    local current="${!envvar:-}"
    if [[ -n "$current" ]]; then
        if [[ ! -d "$current" ]]; then
            echo "Error: $envvar=$current but the directory does not exist." >&2
            return 1
        fi
        _resolved="$current"
        echo "[build_dependencies_from_source] $name: using $envvar=$current"
    else
        _ensure_submodule_initialized "$sub_path" || return 1
        _resolved="$sub_path"
        echo "[build_dependencies_from_source] $name: using submodule $sub_path"
    fi
}

# _build_and_install_dep <name> <source-dir> <extra-cmake-args...>
# Auto-rebuilds when the source HEAD SHA changes since the last install.
_build_and_install_dep() {
    local name="$1" src="$2"
    shift 2
    local build_dir="$_build_root/$name"
    local sentinel="$build_dir/.installed"

    local current_sha=""
    if [[ -d "$src/.git" || -f "$src/.git" ]]; then
        current_sha=$(git -C "$src" rev-parse HEAD 2>/dev/null || echo "")
    fi

    if [[ "$_rebuild" != true && -f "$sentinel" ]]; then
        local installed_sha
        installed_sha=$(cat "$sentinel" 2>/dev/null)
        if [[ "$installed_sha" == "$current_sha" ]]; then
            echo "[build_dependencies_from_source] $name @ ${current_sha:0:8} already installed -- skipping"
            return 0
        fi
        echo "[build_dependencies_from_source] $name source changed (${installed_sha:0:8} -> ${current_sha:0:8}) -- rebuilding"
        rm -rf "$build_dir"
    fi
    [[ "$_rebuild" == true ]] && rm -rf "$build_dir"

    echo "[build_dependencies_from_source] Configuring $name from $src ..."
    cmake -S "$src" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$_prefix" \
        "$@" \
        || return 1

    echo "[build_dependencies_from_source] Building & installing $name ($_parallel parallel jobs) ..."
    cmake --build "$build_dir" --parallel "$_parallel" --target install || return 1

    echo "$current_sha" > "$sentinel"
}

# --- Resolve source paths ------------------------------------------------
# MOM6 is always resolved -- consumed by turbo-stack's CMakeLists.txt:9.
_resolve_root MOM6 MOM6_ROOT "$TURBO_STACK_ROOT/submodules/MOM6"        \
    || { return 1 2>/dev/null || exit 1; }
mom6_src="$_resolved"
export MOM6_ROOT="$mom6_src"

# Buildable deps only need source resolution when we're about to build them.
if [[ "$_build_fms" == true ]]; then
    _resolve_root FMS FMS_ROOT "$TURBO_STACK_ROOT/submodules/infra/FMS2" \
        || { return 1 2>/dev/null || exit 1; }
    fms_src="$_resolved"
fi
if [[ "$_build_pfunit" == true ]]; then
    _resolve_root PFUNIT PFUNIT_ROOT "$TURBO_STACK_ROOT/submodules/pFUnit" \
        || { return 1 2>/dev/null || exit 1; }
    pfunit_src="$_resolved"
fi
if [[ "$_build_amrex" == true ]]; then
    _resolve_root AMREX AMREX_ROOT "$TURBO_STACK_ROOT/submodules/amrex" \
        || { return 1 2>/dev/null || exit 1; }
    amrex_src="$_resolved"
fi
if [[ "$_build_tim" == true ]]; then
    _resolve_root TIM TIM_ROOT "$TURBO_STACK_ROOT/submodules/infra/TIM" \
        || { return 1 2>/dev/null || exit 1; }
    tim_src="$_resolved"
    export TIM_ROOT="$tim_src"
fi

# --- Build & install (each toggleable) -----------------------------------
# FMS (R8 component to match find_package(FMS COMPONENTS R8))
if [[ "$_build_fms" == true ]]; then
    if ! _build_and_install_dep fms "$fms_src" \
            -D64BIT=ON -D32BIT=OFF -DFPIC=ON -DOPENMP=OFF; then
        return 1 2>/dev/null || exit 1
    fi
fi

# pFUnit (with MPI, no ESMF, no internal tests)
if [[ "$_build_pfunit" == true ]]; then
    if ! _build_and_install_dep pfunit "$pfunit_src" \
            -DSKIP_MPI=NO -DSKIP_ESMF=YES -DENABLE_TESTS=OFF; then
        return 1 2>/dev/null || exit 1
    fi
fi

# AMReX (Fortran + MPI on, plus the high-level F90 interfaces that provide
# amrex_base_module — required by MOM6's TIM wrapper code).  Matches what
# spack's `amrex +fortran` variant produces.
if [[ "$_build_amrex" == true ]]; then
    if ! _build_and_install_dep amrex "$amrex_src" \
            -DAMReX_FORTRAN=ON -DAMReX_FORTRAN_INTERFACES=ON -DAMReX_MPI=ON; then
        return 1 2>/dev/null || exit 1
    fi
fi

# TIM (R8 component to match find_package(TIM COMPONENTS R8)).
if [[ "$_build_tim" == true ]]; then
    if ! _build_and_install_dep tim "$tim_src" \
            -D64BIT=ON -D32BIT=OFF; then
        return 1 2>/dev/null || exit 1
    fi
fi

# --- Expose installs to find_package -------------------------------------
case ":${CMAKE_PREFIX_PATH:-}:" in
    *:"$_prefix":*) ;;
    *) export CMAKE_PREFIX_PATH="$_prefix${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}" ;;
esac

# pFUnit installs into $_prefix/PFUNIT-X.Y/ -- a versioned subdir that
# find_package(PFUNIT) does not auto-walk via CMAKE_PREFIX_PATH alone.
if [[ "$_build_pfunit" == true ]]; then
    _pfunit_cmake_dir=$(ls -d "$_prefix"/PFUNIT-*/cmake 2>/dev/null | head -n1)
    if [[ -n "$_pfunit_cmake_dir" ]]; then
        export PFUNIT_DIR="$_pfunit_cmake_dir"
    fi
fi

# --- Cleanup -------------------------------------------------------------
unset _tag _prefix _parallel _rebuild _build_root _resolved
unset _build_fms _build_pfunit _build_amrex _build_tim
unset mom6_src fms_src tim_src pfunit_src amrex_src _pfunit_cmake_dir
unset -f _ensure_submodule_initialized _resolve_root _build_and_install_dep
