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
#   --build_dir DIR         Build directory for turbo-stack itself (passed
#                           through to build_turbo_stack.sh).  Also controls
#                           where from-source dep cmake builds + installs
#                           land: $DIR/deps/build/<name>/ and
#                           $DIR/deps/install/.  When --build_dir is omitted,
#                           deps land at $TURBO_STACK_ROOT/deps/default/.
#                           Power users who need deps in a path unrelated to
#                           the turbo-stack build dir can source the env
#                           script directly with its --deps-build-root flag.
#   --infra FMS2|TIM        Infrastructure backend (default: FMS2, passed
#                           through to build_turbo_stack.sh).
#   --parallel N, -j N      Parallel build jobs.  Exported as
#                           CMAKE_BUILD_PARALLEL_LEVEL so every downstream
#                           `cmake --build` invocation (deps + turbo-stack)
#                           picks it up natively, without any flag plumbing.
#                           When omitted, cmake's own defaults apply (1 for
#                           Make, nproc for Ninja).
#
# Examples:
#   build_on_derecho.sh                              # configure + build + test
#   build_on_derecho.sh --debug                      # full clean rebuild
#   build_on_derecho.sh --infra TIM --debug          # full clean rebuild with TIM backend

set -eo pipefail

debug=false
infra="FMS2"
build_dir=""
parallel=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)              debug=true; shift ;;
        --infra)              infra="$2"; shift 2 ;;
        --build_dir)          build_dir="$2"; shift 2 ;;
        --parallel|-j)        parallel="$2"; shift 2 ;;
        *)
            echo "Error: unknown option '$1' to build_on_derecho.sh" >&2
            exit 1
            ;;
    esac
done

if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
    echo "Error: TURBO_STACK_ROOT is not set." >&2
    exit 1
fi

# Set CMAKE_BUILD_PARALLEL_LEVEL once -- cmake reads it natively, so every
# `cmake --build` in the rest of the pipeline (deps + turbo-stack) picks
# this up without further flag plumbing.
[[ -n "$parallel" ]] && export CMAKE_BUILD_PARALLEL_LEVEL="$parallel"

# --- Stage 1: environment setup + dependency builds (Derecho) -----------
# When --build_dir is given, place deps next to it ($build_dir/deps).  Else
# let the env script use its own default ($TURBO_STACK_ROOT/deps/default).
env_args=()
[[ -n "$build_dir" ]] && env_args=(--deps-build-root "$build_dir/deps")
source "$TURBO_STACK_ROOT/scripts/setup_environment/derecho_cpu_gcc_openmpi.sh" "${env_args[@]}"

# --- Stage 2: configure + build + test -----------------------------------
build_args=()
[[ "$debug"     == true ]] && build_args+=(--debug)
[[ -n "$infra"           ]] && build_args+=(--infra "$infra")
[[ -n "$build_dir"       ]] && build_args+=(--build_dir "$build_dir")
bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" "${build_args[@]}"
