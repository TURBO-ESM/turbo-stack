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
# self-located from this script (build the checkout you run from).
#
# Options:
#   --debug                 Build with CMAKE_BUILD_TYPE=Debug (passed through)
#   --clean                 Clean rebuild from scratch.  Removes the Stage-1
#                           upstream dep builds/installs AND passes cmake --fresh
#                           --clean-first to the Stage-2 turbo-stack build.
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
#   --cmake-arg ARG         Append ARG to the cmake configure line (repeatable),
#                           e.g. --cmake-arg -DMOM6_ENABLE_TIM_BRIDGE=ON.  Each
#                           occurrence contributes exactly one argument.
#   --recreate-spack-env    Delete and recreate the Spack env from scratch
#   -h, --help              Print this usage text and exit.
#
# Examples:
#   build_local_with_spack_env.sh                       # TIM backend, build the executable
#   build_local_with_spack_env.sh --tests               # also build + run the unit tests
#   build_local_with_spack_env.sh --infra FMS2          # FMS2 backend instead of TIM
#   build_local_with_spack_env.sh --debug --clean       # clean Debug rebuild (deps + turbo-stack)
#   build_local_with_spack_env.sh --recreate-spack-env  # recreate the spack env, then build

set -eo pipefail

# Source the shared library (defines the builder core + helpers; no side effects).
# This script lives in scripts/, so the shared library is the sibling lib/ subdir.
# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# Pre-strip the spack-only option before the common parser sees it (the shared
# turbo_parse_builder_args rejects unknown flags, by design).
_spack_recreate=false
_args=()
for _a in "$@"; do
    case "$_a" in
        --recreate-spack-env) _spack_recreate=true ;;
        *)                    _args+=("$_a") ;;
    esac
done

# --- Stage 1 (env setup) · toolchain (machine-specific) ------------------------
# Activate the Spack env, which supplies Tier 1 (cmake/MPI/NetCDF) AND Tier 1.5
# (pFUnit/AMReX).  FMS/TIM are intentionally not in spack.yaml.
turbo_flavor_setup_toolchain() {
    local env_args=()
    [[ "$_spack_recreate" == true ]] && env_args+=(--recreate)
    # shellcheck source=/dev/null
    source "$TURBO_STACK_ROOT/scripts/setup_environment/spack_local_environment.sh" "${env_args[@]}"
}

# Spack supplies Tier 1 + Tier 1.5, so build only Tier 2 (FMS for FMS2, TIM for
# TIM) from the submodule.  turbo_run_backend_builder (scripts/lib/common.sh)
# does the rest: arg parsing, --clean, submodule guards, the dep build, Stage 2.
turbo_run_backend_builder --build-deps-from-tier 2 "${_args[@]}"
