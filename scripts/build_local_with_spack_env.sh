#!/bin/bash
# Usage: ./scripts/build_local_with_spack_env.sh [options]
#
# One-command build for the Spack flavor: sources
# scripts/setup_environment/spack_local_environment.sh, builds the selected
# infra backend (FMS for FMS2, TIM for --infra TIM) via the turbo_build_*
# wrappers, then calls scripts/build_turbo_stack.sh to configure/build/test.  Spack
# provides only cmake/MPI/NetCDF/pFUnit/AMReX; FMS is intentionally not in
# spack.yaml because turbo-stack tracks features ahead of the released FMS
# package.
#
# For the modules + from-source flavor (e.g. Derecho), source the appropriate
# scripts/setup_environment/<machine>.sh manually and call
# scripts/build_turbo_stack.sh directly.  See scripts/README.md for details.
#
# Required: SPACK_ROOT (your Spack installation).  TURBO_STACK_ROOT is
# self-located (set it only to override).
#
# Options:
#   --debug                 Build with CMAKE_BUILD_TYPE=Debug (passed through)
#   --clean                 Clean rebuild from scratch.  Removes the Tier-2 dep
#                           builds/installs AND passes cmake --fresh
#                           --clean-first to the Tier-3 turbo-stack build.
#   --ninja                 Use Ninja generator (passed through)
#   --infra FMS2|TIM        Infrastructure backend (default: TIM, passed
#                           through).  Builds the selected backend from source:
#                           FMS for FMS2, TIM for TIM.  The two are mutually
#                           exclusive.
#   --tests                 Also build + run the pFUnit unit tests (default:
#                           off).  pFUnit itself comes from spack.
#   --build_dir DIR         Build directory for turbo-stack itself (passed
#                           through).  Also controls where the FMS/TIM dep
#                           cmake builds + installs land: $DIR/deps/build/<dep>/
#                           and $DIR/deps/install/.  When --build_dir is
#                           omitted, deps land at $TURBO_STACK_ROOT/deps/default/.
#   --parallel N, -j N      Parallel build jobs.  Exported as
#                           CMAKE_BUILD_PARALLEL_LEVEL so every downstream
#                           `cmake --build` invocation (FMS/TIM deps + turbo-stack)
#                           picks it up natively, without any flag plumbing.
#                           When omitted, cmake's own defaults apply (1 for
#                           Make, nproc for Ninja).
#   --recreate-spack-env    Delete and recreate the Spack env from scratch
#   -h, --help              Print this usage text and exit.
#
# Examples:
#   build_local_with_spack_env.sh                       # TIM backend, build the executable
#   build_local_with_spack_env.sh --tests               # also build + run the unit tests
#   build_local_with_spack_env.sh --infra FMS2          # FMS2 backend instead of TIM
#   build_local_with_spack_env.sh --debug --clean       # clean Debug rebuild (deps + Tier 3)
#   build_local_with_spack_env.sh --recreate-spack-env  # recreate the spack env, then build

set -eo pipefail

# Source the shared library first (no side effects; just defines functions), so
# --help and the --clean guard are available while parsing.  This script lives
# in scripts/, so the shared library is the sibling lib/ subdir.
# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

recreate_spack_env=false
debug=false
clean=false
ninja=false
infra="TIM"
with_tests=false
build_dir=""
parallel=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --recreate-spack-env) recreate_spack_env=true; shift ;;
        --debug)              debug=true; shift ;;
        --clean)              clean=true; shift ;;
        --ninja)              ninja=true; shift ;;
        --infra)              infra="$2"; shift 2 ;;
        --tests)              with_tests=true; shift ;;
        --build_dir)          build_dir="$2"; shift 2 ;;
        --parallel|-j)        parallel="$2"; shift 2 ;;
        -h|--help)            turbo_print_header_usage "$0"; exit 0 ;;
        *)
            echo "Error: unknown option '$1' to build_local_with_spack_env.sh" >&2
            exit 1
            ;;
    esac
done

if [[ "$infra" != "FMS2" && "$infra" != "TIM" ]]; then
    echo "Error: --infra must be FMS2 or TIM (got '$infra')" >&2
    exit 1
fi

# Resolve TURBO_STACK_ROOT (self-locating; an exported value is an optional
# override).
turbo_resolve_stack_root

# Set CMAKE_BUILD_PARALLEL_LEVEL once -- cmake reads it natively, so every
# `cmake --build` in the rest of the pipeline (FMS/TIM deps + turbo-stack) picks
# this up without further flag plumbing.
[[ -n "$parallel" ]] && export CMAKE_BUILD_PARALLEL_LEVEL="$parallel"

# Where the inline FMS/TIM build_deps land their builds + installs: derive
# from --build_dir if given, else fall back to $TURBO_STACK_ROOT/deps/default.
if [[ -n "$build_dir" ]]; then
    deps_build_root="$build_dir/deps"
else
    deps_build_root="$TURBO_STACK_ROOT/deps/default"
fi

# --clean covers Tier 2 as well as Tier 3: wipe the dep builds/installs here, and
# forward --clean to build_turbo_stack.sh (cmake --fresh --clean-first) below.
# This is the same "Tier 2 + Tier 3" definition the end-to-end driver uses (see
# scripts/lib/common.sh).
if [[ "$clean" == true ]]; then
    turbo_validate_clean_paths "$deps_build_root" || exit 1
    echo "[--clean] removing Tier-2 dep artifacts under $deps_build_root"
    rm -rf "$deps_build_root"
fi

# Guard the submodules this build consumes (skipped when the matching *_ROOT
# overrides).  pFUnit + AMReX come from spack here, so only MOM6 / MARBL and the
# selected infra backend need an initialized submodule.
turbo_require_submodule submodules/MOM6  MOM6  MOM6_ROOT
turbo_require_submodule submodules/MARBL MARBL
if [[ "$infra" == "TIM" ]]; then
    turbo_require_submodule submodules/infra/TIM TIM TIM_ROOT
else
    turbo_require_submodule submodules/infra/FMS2 FMS FMS_ROOT
fi

# --- Tier 1: toolchain (spack env; no dependency builds) -----------------
env_args=()
[[ "$recreate_spack_env" == true ]] && env_args+=(--recreate)
# shellcheck source=/dev/null
source "$TURBO_STACK_ROOT/scripts/setup_environment/spack_local_environment.sh" "${env_args[@]}"

# --- Tier 2: build the infra backend from source -------------------------
# Spack provides pFUnit + AMReX; FMS is intentionally NOT in spack (turbo-stack
# tracks features ahead of the released package) and TIM has never been, so
# build the selected backend from its submodule (or its $<NAME>_ROOT override).
# FMS2 and TIM are mutually exclusive.  Canonical flags live in
# scripts/lib/common.sh's turbo_build_* wrappers.

if [[ "$infra" == "TIM" ]]; then
    turbo_build_tim "$deps_build_root/build" "$deps_build_root/install"
fi

if [[ "$infra" == "FMS2" ]]; then
    turbo_build_fms "$deps_build_root/build" "$deps_build_root/install"
fi

# --- Tier 3: configure + build + test turbo-stack ------------------------
build_args=()
[[ "$debug"     == true ]] && build_args+=(--debug)
[[ "$clean"     == true ]] && build_args+=(--clean)
[[ "$ninja"     == true ]] && build_args+=(--ninja)
[[ -n "$infra"           ]] && build_args+=(--infra "$infra")
[[ "$with_tests" == true ]] && build_args+=(--tests)
[[ -n "$build_dir"       ]] && build_args+=(--build_dir "$build_dir")
bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" "${build_args[@]}"
