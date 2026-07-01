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
#   --clean                 Clean rebuild from scratch (passed through:
#                           cmake --fresh + --clean-first)
#   --ninja                 Use Ninja generator (passed through)
#   --build_dir DIR         Build directory for turbo-stack itself (passed
#                           through).  Also controls where the FMS/TIM dep
#                           cmake builds + installs land: $DIR/deps/build/<dep>/
#                           and $DIR/deps/install/.  When --build_dir is
#                           omitted, deps land at $TURBO_STACK_ROOT/deps/default/.
#   --infra FMS2|TIM        Infrastructure backend (default: FMS2, passed
#                           through).  Builds the selected backend from source:
#                           FMS for FMS2, TIM for TIM.  The two are mutually
#                           exclusive.
#   --parallel N, -j N      Parallel build jobs.  Exported as
#                           CMAKE_BUILD_PARALLEL_LEVEL so every downstream
#                           `cmake --build` invocation (FMS/TIM deps + turbo-stack)
#                           picks it up natively, without any flag plumbing.
#                           When omitted, cmake's own defaults apply (1 for
#                           Make, nproc for Ninja).
#   --recreate-spack-env    Delete and recreate the Spack env from scratch
#
# Examples:
#   build_local_with_spack_env.sh                              # configure + build + test
#   build_local_with_spack_env.sh --debug                      # full clean rebuild
#   build_local_with_spack_env.sh --infra TIM --clean          # full clean rebuild with TIM backend
#   build_local_with_spack_env.sh --recreate-spack-env --clean # recreate spack env then full clean rebuild

set -eo pipefail

recreate_spack_env=false
debug=false
clean=false
ninja=false
infra="FMS2"
build_dir=""
parallel=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --recreate-spack-env) recreate_spack_env=true; shift ;;
        --debug)              debug=true; shift ;;
        --clean)              clean=true; shift ;;
        --ninja)              ninja=true; shift ;;
        --infra)              infra="$2"; shift 2 ;;
        --build_dir)          build_dir="$2"; shift 2 ;;
        --parallel|-j)        parallel="$2"; shift 2 ;;
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

# Locate + source the shared library, then resolve TURBO_STACK_ROOT (self-
# locating; an exported value is an optional override).  This script lives in
# scripts/, so the shared library is the sibling lib/ subdir.
# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
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
[[ -n "$build_dir"       ]] && build_args+=(--build_dir "$build_dir")
bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" "${build_args[@]}"
