#!/bin/bash
# Usage: ./scripts/build_local_with_system_toolchain.sh [options]
#
# One-command, build-everything-from-source local build.  This is the closest
# replacement for the old `build.sh` on a laptop / workstation: you bring your
# own toolchain (compilers, MPI, NetCDF, CMake already on PATH -- system
# packages, Homebrew, an OS module system, or an already-activated Spack/Conda
# env), and turbo-stack builds ALL of its upstream submodule deps from source --
# pFUnit + AMReX (Tier 1.5) and FMS/TIM (Tier 2) -- then builds turbo-stack
# itself (Tier 3).  Nothing is fetched; everything comes from `submodules/`.
#
# This is the generic-local sibling of the other single-backend builders; they
# differ only in Stage-1 (environment setup):
#   build_local_with_system_toolchain.sh  toolchain already on PATH; build all deps from submodule  (this file)
#   build_local_with_spack_env.sh         Spack supplies the toolchain + pFUnit/AMReX; build FMS/TIM
#   build_on_derecho.sh                   Lmod modules supply the toolchain; build all deps from submodule
#
# Prepare your toolchain BEFORE running (see local_toolchain_on_path.sh), e.g.:
#   module load <compiler> <mpi> <netcdf> cmake      # an OS module system
#   spack env activate <env>                         # an existing Spack env
#   brew install gcc open-mpi netcdf netcdf-fortran cmake             # macOS
# Prefer Spack to manage the whole toolchain in one step?  Use
# build_local_with_spack_env.sh instead.
#
# `TURBO_STACK_ROOT` is self-located from this script (build the checkout you run
# from).  See scripts/README.md for the dependency tier model.
#
# Optional environment variables (hot-swap a dep's source; default = submodule):
#   MOM6_ROOT / FMS_ROOT / TIM_ROOT   out-of-tree source overrides
#
# Options:
#   --debug                 Build with CMAKE_BUILD_TYPE=Debug (passed through)
#   --clean                 Clean rebuild from scratch.  Removes the Stage-1
#                           upstream dep builds/installs AND passes cmake --fresh
#                           --clean-first to the Stage-2 turbo-stack build.
#   --ninja                 Use Ninja generator (passed through)
#   --infra FMS2|TIM        Infrastructure backend (default: TIM, passed
#                           through to build_turbo_stack.sh).
#   --tests                 Also build pFUnit + the unit-test suite and run
#                           ctest (default: off -- a plain build produces just
#                           the executable, and pFUnit is not built).
#   --build_dir DIR         Build directory for turbo-stack itself (passed
#                           through to build_turbo_stack.sh).  Also controls
#                           where from-source dep cmake builds + installs
#                           land: $DIR/deps/build/<name>/ and
#                           $DIR/deps/install/.  When --build_dir is omitted,
#                           deps land at $TURBO_STACK_ROOT/deps/default/.
#   --parallel N, -j N      Parallel build jobs.  Exported as
#                           CMAKE_BUILD_PARALLEL_LEVEL so every downstream
#                           `cmake --build` invocation (deps + turbo-stack)
#                           picks it up natively, without any flag plumbing.
#                           When omitted, cmake's own defaults apply (1 for
#                           Make, nproc for Ninja).
#   -h, --help              Print this usage text and exit.
#
# Examples:
#   build_local_with_system_toolchain.sh                        # TIM backend, build the executable
#   build_local_with_system_toolchain.sh --tests                # also build + run the unit tests
#   build_local_with_system_toolchain.sh --infra FMS2           # FMS2 backend instead of TIM
#   build_local_with_system_toolchain.sh --debug --clean        # clean Debug rebuild (deps + turbo-stack)

set -eo pipefail

# Source the shared library first (no side effects; just defines functions), so
# --help and the --clean guard are available while parsing.  This script lives
# in scripts/, so the shared library is the sibling lib/ subdir.
# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

debug=false
clean=false
ninja=false
infra="TIM"
with_tests=false
build_dir=""
parallel=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)              debug=true; shift ;;
        --clean)              clean=true; shift ;;
        --ninja)              ninja=true; shift ;;
        --infra)              infra="$2"; shift 2 ;;
        --tests)              with_tests=true; shift ;;
        --build_dir)          build_dir="$2"; shift 2 ;;
        --parallel|-j)        parallel="$2"; shift 2 ;;
        -h|--help)            turbo_print_header_usage "$0"; exit 0 ;;
        *)
            echo "Error: unknown option '$1' to build_local_with_system_toolchain.sh" >&2
            exit 1
            ;;
    esac
done

if [[ "$infra" != "FMS2" && "$infra" != "TIM" ]]; then
    echo "Error: --infra must be FMS2 or TIM (got '$infra')" >&2
    exit 1
fi

# Resolve TURBO_STACK_ROOT (self-locating; a mismatching exported value is a
# hard error -- see turbo_resolve_stack_root).
turbo_resolve_stack_root

# Set CMAKE_BUILD_PARALLEL_LEVEL once -- cmake reads it natively, so every
# `cmake --build` in the rest of the pipeline (deps + turbo-stack) picks
# this up without further flag plumbing.
[[ -n "$parallel" ]] && export CMAKE_BUILD_PARALLEL_LEVEL="$parallel"

# Where the from-source upstream deps build + install: $build_dir/deps when given,
# else $TURBO_STACK_ROOT/deps/default.
if [[ -n "$build_dir" ]]; then
    deps_build_root="$build_dir/deps"
else
    deps_build_root="$TURBO_STACK_ROOT/deps/default"
fi

# --clean covers the Stage-1 deps as well as the Stage-2 build: wipe the dep
# builds/installs here, and forward --clean to build_turbo_stack.sh (cmake
# --fresh --clean-first) below.  This is the same "deps + turbo-stack" definition
# the end-to-end driver uses (see scripts/lib/common.sh).
if [[ "$clean" == true ]]; then
    turbo_validate_clean_paths "$deps_build_root" || exit 1
    echo "[--clean] removing upstream dep artifacts under $deps_build_root"
    rm -rf "$deps_build_root"
fi

# Guard the submodules this build consumes (skipped when the matching *_ROOT
# overrides).  Nothing here comes from a package manager, so pFUnit and the
# per-infra deps are all built from submodule -- same as the Derecho builder.
turbo_require_submodule submodules/MOM6   MOM6   MOM6_ROOT
turbo_require_submodule submodules/MARBL  MARBL
[[ "$with_tests" == true ]] && turbo_require_submodule submodules/pFUnit pFUnit PFUNIT_ROOT
if [[ "$infra" == "TIM" ]]; then
    turbo_require_submodule submodules/infra/TIM TIM   TIM_ROOT
    turbo_require_submodule submodules/amrex     AMReX AMREX_ROOT
else
    turbo_require_submodule submodules/infra/FMS2 FMS  FMS_ROOT
fi

# --- Stage 1 (env setup) · toolchain: verify the toolchain already on PATH ---
# No spack, no modules: this recipe builds nothing and only checks that your
# compiler / MPI / NetCDF / CMake are present, failing early with a clear
# message if not.
# shellcheck source=/dev/null
source "$TURBO_STACK_ROOT/scripts/setup_environment/local_toolchain_on_path.sh"

# --- Stage 1 (env setup) · build upstream deps (Tier 1.5 + Tier 2) explicitly ---
# A bring-your-own-toolchain machine provides none of the upstream submodule
# deps, so build them all from submodule (or each $<NAME>_ROOT override).
# Canonical flags live in scripts/lib/common.sh.  pFUnit is built only when
# --tests is given; the infra backend -- plus AMReX, which TIM links -- only for
# the selected --infra.

if [[ "$with_tests" == true ]]; then
    turbo_build_pfunit "$deps_build_root/build" "$deps_build_root/install"
fi

if [[ "$infra" == "TIM" ]]; then
    turbo_build_amrex "$deps_build_root/build" "$deps_build_root/install"
    turbo_build_tim   "$deps_build_root/build" "$deps_build_root/install"
fi

if [[ "$infra" == "FMS2" ]]; then
    turbo_build_fms   "$deps_build_root/build" "$deps_build_root/install"
fi

# --- Stage 2 · build turbo-stack (Tier 3): configure + build + test ------
build_args=()
[[ "$debug"      == true ]] && build_args+=(--debug)
[[ "$clean"      == true ]] && build_args+=(--clean)
[[ "$ninja"      == true ]] && build_args+=(--ninja)
[[ -n "$infra"           ]] && build_args+=(--infra "$infra")
[[ "$with_tests" == true ]] && build_args+=(--tests)
[[ -n "$build_dir"       ]] && build_args+=(--build_dir "$build_dir")
bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" "${build_args[@]}"
