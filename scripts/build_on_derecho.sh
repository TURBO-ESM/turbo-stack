#!/bin/bash
# Usage: ./scripts/build_on_derecho.sh [options]
#
# Options:
#   --debug                 Full clean rebuild (passed through)
#   --build_dir DIR         Build directory (passed through)
#   --infra FMS2|TIM        Infrastructure backend (passed through).  For TIM,
#                           this script also sources build_dependencies_from_source.sh
#                           --only tim, since spack does not provide TIM.
#
# Examples:
#   build_on_derecho.sh                              # configure + build + test
#   build_on_derecho.sh --debug                      # full clean rebuild
#   build_on_derecho.sh --infra TIM --debug          # full clean rebuild with TIM backend

set -eo pipefail

#############################################################################
# Move this somewhere else later or just have it be set by the user, but for now just hardcoded
export TURBO_STACK_ROOT=/glade/u/home/htorres/turbo_build_pr_tester/turbo-stack
export MOM6_ROOT=/glade/u/home/htorres/turbo_build_pr_tester/MOM6
export TIM_ROOT=/glade/u/home/htorres/turbo_build_pr_tester/TIM
export FMS_ROOT=/glade/u/home/htorres/turbo_build_pr_tester/FMS
#############################################################################

debug=false
infra=""
build_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)              debug=true; shift ;;
        --infra)              infra="$2"; shift 2 ;;
        --build_dir)          build_dir="$2"; shift 2 ;;
        --)                   shift; break ;;
        *)                    break ;;
    esac
done

if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
    echo "Error: TURBO_STACK_ROOT is not set." >&2
    exit 1
fi

# --- Stage 1: environment setup (Derecho) --------------------------------
source "$TURBO_STACK_ROOT/scripts/setup_environment/derecho.sh"

# --- Stage 1b: build dependencies from source... relies on modules being set up correctly to find the right compiler, MPI, NetCDF, etc. ---
source "$TURBO_STACK_ROOT/scripts/build_dependencies_from_source.sh" #--rebuild

# --- Stage 2: configure + build + test -----------------------------------
build_args=()
[[ "$debug"     == true ]] && build_args+=(--debug)
[[ "$ninja"     == true ]] && build_args+=(--ninja)
[[ -n "$infra"           ]] && build_args+=(--infra "$infra")
[[ -n "$build_dir"       ]] && build_args+=(--build_dir "$build_dir")
bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" "${build_args[@]}"
