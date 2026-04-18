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
#   --create-spack-env    Create the Spack environment if it does not exist
#   --recreate-spack-env  Delete and recreate the Spack environment from scratch
#
# Examples:
#   build.sh                              # configure + build + test
#   build.sh --debug                      # full clean rebuild
#   build.sh --recreate-spack-env --debug # recreate spack env then full clean rebuild

set -e

# Default arguments
create_spack_env=false
recreate_spack_env=false
debug=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --create-spack-env)   create_spack_env=true; shift ;;
        --recreate-spack-env) recreate_spack_env=true; shift ;;
        --debug)              debug=true; shift ;;
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
[[ "$debug" == true ]] && build_args+=(--debug)
bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" "${build_args[@]}"

## Hardcoded generate options for now, but could be made into arguments in the future.
#source_dir="$TURBO_STACK_ROOT"
#build_dir="$TURBO_STACK_ROOT/build/default"
#generator="Ninja" 
#
## Generate
#cmake_generate_options=()
##cmake_generate_options+=("-DCMAKE_C_COMPILER=$CC")
##cmake_generate_options+=("-DCMAKE_CXX_COMPILER=$CXX")
#if [[ "$generator" != "" ]]; then
#    cmake_generate_options+=("-G" "$generator")
#fi
#if [[ "$debug" == true ]]; then
#    cmake_generate_options+=("-DCMAKE_BUILD_TYPE=Debug")
#    cmake_generate_options+=("--fresh")
#fi
#cmake "${cmake_generate_options[@]}" -S "$source_dir" -B "$build_dir"
#
## Build# Build the code. 
#cmake_build_options=()
#if [[ "$debug" == true ]]; then
#    cmake_build_options+=("--clean-first")
#fi
#cmake --build "$build_dir" "${cmake_build_options[@]}"
#
## Test
#cmake_test_options=()
#cmake_test_options+=("--output-on-failure")
#ctest --test-dir "$build_dir" "${cmake_test_options[@]}"