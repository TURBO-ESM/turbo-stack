#!/bin/bash
# Usage: ./scripts/build_with_spack.sh [options]
#
# One-command build for the Spack flavor: sources
# scripts/setup_environment/spack_local_environment.sh, optionally builds TIM
# from source via build_dep (when --infra TIM, since spack does not package
# TIM), then calls scripts/build_turbo_stack.sh to configure, build, and test.
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
#   --build_dir DIR         Build directory (passed through)
#   --infra FMS2|TIM        Infrastructure backend (passed through).  For TIM,
#                           this script also calls `build_dep tim` since spack
#                           does not provide TIM.
#   --parallel N, -j N      Parallel build jobs.  Forwarded as --parallel N to
#                           the TIM build_dep call (when --infra TIM) and to
#                           the turbo-stack build step.  Defaults to serial in
#                           both when omitted.
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
        --)                   shift; break ;;
        *)                    break ;;
    esac
done

if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
    echo "Error: TURBO_STACK_ROOT is not set." >&2
    exit 1
fi

# --- Stage 1: environment setup (Spack flavor) ---------------------------
env_args=()
[[ "$recreate_spack_env" == true ]] && env_args+=(--recreate)
# shellcheck source=/dev/null
source "$TURBO_STACK_ROOT/scripts/setup_environment/spack_local_environment.sh" "${env_args[@]}"

# --- Stage 1b: TIM is not in spack -- build from source when requested ---
if [[ "$infra" == "TIM" ]]; then
    # shellcheck source=/dev/null
    source "$TURBO_STACK_ROOT/scripts/build_dep.sh"
    tim_parallel_args=()
    [[ -n "$parallel" ]] && tim_parallel_args=(--parallel "$parallel")
    build_dep tim \
        --build-dir "$TURBO_STACK_ROOT/deps/default/build/tim" \
        --install-prefix "$TURBO_STACK_ROOT/deps/default/install" \
        "${tim_parallel_args[@]}" \
        -- -D64BIT=ON -D32BIT=OFF
fi

# --- Stage 2: configure + build + test -----------------------------------
build_args=()
[[ "$debug"     == true ]] && build_args+=(--debug)
[[ "$ninja"     == true ]] && build_args+=(--ninja)
[[ -n "$infra"           ]] && build_args+=(--infra "$infra")
[[ -n "$build_dir"       ]] && build_args+=(--build_dir "$build_dir")
[[ -n "$parallel"        ]] && build_args+=(--parallel "$parallel")
bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" "${build_args[@]}"
