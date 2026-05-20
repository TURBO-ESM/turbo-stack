#!/bin/bash
# Usage: ./scripts/build_on_derecho.sh [options]
#
# Required environment variables (set these in your shell profile, e.g. ~/.bashrc):
#   TURBO_STACK_ROOT    Path to your turbo-stack repository clone
#
# Optional environment variables (override the corresponding submodule when set):
#   MOM6_ROOT           Path to a MOM6 source checkout (default: submodule)
#   FMS_ROOT            Path to an FMS source checkout (default: submodule)
#   TIM_ROOT            Path to a TIM source checkout (default: submodule)
#   PFUNIT_ROOT         Path to a pFUnit source checkout (default: submodule)
#   AMREX_ROOT          Path to an AMReX source checkout (default: submodule)
#
# Options:
#   --debug                 Full clean rebuild (passed through)
#   --build_dir DIR         Build directory (passed through)
#   --infra FMS2|TIM        Infrastructure backend (passed through).  For TIM,
#                           this script also sources build_dependencies_from_source.sh
#                           --only tim, since spack does not provide TIM.
#   --parallel N, -j N      Parallel build jobs.  Forwarded as --parallel N to
#                           both the deps step and the turbo-stack build step.
#                           Defaults to serial in both child scripts when
#                           omitted.
#
# Examples:
#   build_on_derecho.sh                              # configure + build + test
#   build_on_derecho.sh --debug                      # full clean rebuild
#   build_on_derecho.sh --infra TIM --debug          # full clean rebuild with TIM backend

set -eo pipefail

debug=false
infra=""
build_dir=""
parallel=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)              debug=true; shift ;;
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

# --- Stage 1: environment setup (Derecho) --------------------------------
source "$TURBO_STACK_ROOT/scripts/setup_environment/derecho_cpu_gcc_openmpi.sh"

# --- Stage 1b: build dependencies from source... relies on modules being set up correctly to find the right compiler, MPI, NetCDF, etc. ---
deps_args=()
[[ -n "$parallel" ]] && deps_args+=(--parallel "$parallel")
source "$TURBO_STACK_ROOT/scripts/build_dependencies_from_source.sh" "${deps_args[@]}" #--rebuild

# --- Stage 2: configure + build + test -----------------------------------
build_args=()
[[ "$debug"     == true ]] && build_args+=(--debug)
[[ -n "$infra"           ]] && build_args+=(--infra "$infra")
[[ -n "$build_dir"       ]] && build_args+=(--build_dir "$build_dir")
[[ -n "$parallel"        ]] && build_args+=(--parallel "$parallel")
bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" "${build_args[@]}"
