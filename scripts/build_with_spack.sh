#!/bin/bash
# Usage: ./scripts/build_with_spack.sh [options]
#
# One-command build for the Spack flavor: sources
# scripts/setup_environment/spack_local_environment.sh, builds FMS (and TIM
# when --infra TIM) from source via build_dep, then calls
# scripts/build_turbo_stack.sh to configure, build, and test.  Spack provides
# only cmake/MPI/NetCDF/pFUnit/AMReX; FMS is intentionally not in spack.yaml
# because turbo-stack tracks features ahead of the released FMS package.
#
# For the modules + from-source flavor (e.g. Derecho), source the appropriate
# scripts/setup_environment/<machine>.sh manually and call
# scripts/build_turbo_stack.sh directly.  See scripts/README.md for details.
#
# Required environment variables:
#   SPACK_ROOT          Path to your Spack installation
#   TURBO_STACK_ROOT    Path to your turbo-stack repository clone
#
# Options:
#   --debug                 Full clean rebuild (passed through)
#   --ninja                 Use Ninja generator (passed through)
#   --build_dir DIR         Build directory for turbo-stack itself (passed
#                           through).  Also controls where the FMS/TIM dep
#                           cmake builds + installs land: $DIR/deps/build/<dep>/
#                           and $DIR/deps/install/.  When --build_dir is
#                           omitted, deps land at $TURBO_STACK_ROOT/deps/default/.
#   --infra FMS2|TIM        Infrastructure backend (passed through).  Selecting
#                           TIM adds a `build_dep tim` step; FMS is always
#                           built from source either way.
#   --parallel N, -j N      Parallel build jobs.  Exported as
#                           CMAKE_BUILD_PARALLEL_LEVEL so every downstream
#                           `cmake --build` invocation (FMS/TIM deps + turbo-stack)
#                           picks it up natively, without any flag plumbing.
#                           When omitted, cmake's own defaults apply (1 for
#                           Make, nproc for Ninja).
#   --recreate-spack-env    Delete and recreate the Spack env from scratch
#
# Examples:
#   build_with_spack.sh                              # configure + build + test
#   build_with_spack.sh --debug                      # full clean rebuild
#   build_with_spack.sh --infra TIM --debug          # full clean rebuild with TIM backend
#   build_with_spack.sh --recreate-spack-env --debug # recreate spack env then full clean rebuild

set -eo pipefail

recreate_spack_env=false
debug=false
ninja=false
infra=""
build_dir=""
parallel=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --recreate-spack-env) recreate_spack_env=true; shift ;;
        --debug)              debug=true; shift ;;
        --ninja)              ninja=true; shift ;;
        --infra)              infra="$2"; shift 2 ;;
        --build_dir)          build_dir="$2"; shift 2 ;;
        --parallel|-j)        parallel="$2"; shift 2 ;;
        *)
            echo "Error: unknown option '$1' to build_with_spack.sh" >&2
            exit 1
            ;;
    esac
done

if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
    echo "Error: TURBO_STACK_ROOT is not set." >&2
    exit 1
fi

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

# --- Stage 1: environment setup (Spack flavor) ---------------------------
env_args=()
[[ "$recreate_spack_env" == true ]] && env_args+=(--recreate)
# shellcheck source=/dev/null
source "$TURBO_STACK_ROOT/scripts/setup_environment/spack_local_environment.sh" "${env_args[@]}"

# --- Stage 1b: build deps not coming from spack ------------------------
# FMS and TIM are both built from source.  FMS used to come from spack,
# but turbo-stack tracks features ahead of the released package, so we
# always defer to $FMS_ROOT (or the submodule fallback when FMS_ROOT is
# unset) to avoid quietly linking a stale version.  TIM has never been
# in spack.
# shellcheck source=/dev/null
source "$TURBO_STACK_ROOT/scripts/build_dep.sh"

build_dep fms \
    --build-dir "$deps_build_root/build/fms" \
    --install-prefix "$deps_build_root/install" \
    -- -D64BIT=ON -D32BIT=OFF -DFPIC=ON -DOPENMP=OFF

if [[ "$infra" == "TIM" ]]; then
    build_dep tim \
        --build-dir "$deps_build_root/build/tim" \
        --install-prefix "$deps_build_root/install" \
        -- -D64BIT=ON -D32BIT=OFF
fi

# --- Stage 2: configure + build + test -----------------------------------
build_args=()
[[ "$debug"     == true ]] && build_args+=(--debug)
[[ "$ninja"     == true ]] && build_args+=(--ninja)
[[ -n "$infra"           ]] && build_args+=(--infra "$infra")
[[ -n "$build_dir"       ]] && build_args+=(--build_dir "$build_dir")
bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" "${build_args[@]}"
