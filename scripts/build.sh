#!/bin/bash
# Usage: ./scripts/build.sh [options]
#
# Sets up and activates a Spack environment, then calls build_turbo_stack.sh.
# If the spack environment is already active, build_turbo_stack.sh can be called directly.
#
# Required environment variables:
#   SPACK_ROOT          Path to your Spack installation
#   TURBO_STACK_ROOT    Path to your turbo-stack repository clone
#
# Options:
#   --debug               Full clean rebuild (passed through to build_turbo_stack.sh)
#   --build_dir DIR       Build directory (passed through to build_turbo_stack.sh)
#   --infra FMS2|TIM      Infrastructure backend (passed through; TIM requires TIM_ROOT)
#   --create-spack-env    Create the Spack environment if it does not exist
#   --recreate-spack-env  Delete and recreate the Spack environment from scratch
#
# Examples:
#   build.sh                              # configure + build + test
#   build.sh --debug                      # full clean rebuild
#   build.sh --infra TIM --debug          # full clean rebuild with TIM backend
#   build.sh --recreate-spack-env --debug # recreate spack env then full clean rebuild

set -e

# Default arguments
create_spack_env=false
recreate_spack_env=false
debug=false
infra=""
build_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --create-spack-env)   create_spack_env=true; shift ;;
        --recreate-spack-env) recreate_spack_env=true; shift ;;
        --debug)              debug=true; shift ;;
        --infra)              infra="$2"; shift 2 ;;
        --build_dir)          build_dir="$2"; shift 2 ;;
        --)                   shift; break ;;
        *)                    break ;;
    esac
done

#######################################
# Environment Management
#######################################
if [[ -z "${SPACK_ROOT:-}" ]]; then
    echo "Error: SPACK_ROOT is not set." >&2
    exit 1
fi
if [[ ! -f "$SPACK_ROOT/share/spack/setup-env.sh" ]]; then
    echo "Error: SPACK_ROOT ($SPACK_ROOT) is not a valid Spack installation." >&2
    exit 1
fi

source "$SPACK_ROOT/share/spack/setup-env.sh"

# Default Spack environment name. Maybe give the option to override this with a command line argument in the future.
spack_env_name="turbo_stack"

if [[ "$recreate_spack_env" == true ]]; then
    if spack env list | grep -qw "$spack_env_name"; then
        echo "Removing Spack environment '$spack_env_name' ..."
        spack env rm -y "$spack_env_name"
    fi
    create_spack_env=true
fi

if [[ "$create_spack_env" == true ]]; then
    bash "$TURBO_STACK_ROOT/spack/create_spack_environment.sh" "$spack_env_name"
fi

spack env activate "$spack_env_name"

#######################################
# Build Turbo Stack and run tests
#######################################

build_args=()
[[ "$debug"     == true ]] && build_args+=(--debug)
[[ -n "$infra"           ]] && build_args+=(--infra "$infra")
[[ -n "$build_dir"       ]] && build_args+=(--build_dir "$build_dir")
bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" "${build_args[@]}"