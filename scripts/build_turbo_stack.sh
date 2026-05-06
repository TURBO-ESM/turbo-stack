#!/bin/bash
# Usage: ./scripts/build_turbo_stack.sh [options]
#
# CMake configure, build, and test turbo-stack.
# Requires the spack environment to be active (call via build.sh, or activate manually).
#
# Required environment variables:
#   TURBO_STACK_ROOT    Path to your turbo-stack repository clone
#
# Options:
#   --debug           Adds --fresh to cmake configure and --clean-first to cmake build
#   --build_dir DIR   Build directory (default: $TURBO_STACK_ROOT/build/default)
#   --infra FMS2|TIM  Infrastructure backend (default: FMS2); TIM also requires TIM_ROOT

set -e

# Default arguments
build_dir="$TURBO_STACK_ROOT/build/default"
debug=false
infra=""

# Command line argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build_dir)   build_dir="$2"; shift 2 ;;
        --debug)       debug=true; shift ;;
        --infra)       infra="$2"; shift 2 ;;
        *)             break ;;
    esac
done

# Hardcoded generate options for now, but could be made into arguments in the future.
source_dir="$TURBO_STACK_ROOT"
generator="Ninja" 

# Generate
cmake_generate_options=()
#cmake_generate_options+=("-DCMAKE_C_COMPILER=$CC")
#cmake_generate_options+=("-DCMAKE_CXX_COMPILER=$CXX")
if [[ "$generator" != "" ]]; then
    cmake_generate_options+=("-G" "$generator")
fi
if [[ "$debug" == true ]]; then
    cmake_generate_options+=("-DCMAKE_BUILD_TYPE=Debug")
    cmake_generate_options+=("--fresh")
fi
if [[ -n "$infra" ]]; then
    cmake_generate_options+=("-DTURBO_INFRA=$infra")
fi
cmake "${cmake_generate_options[@]}" -S "$source_dir" -B "$build_dir"

# Build# Build the code. 
cmake_build_options=()
if [[ "$debug" == true ]]; then
    cmake_build_options+=("--clean-first")
fi
cmake --build "$build_dir" "${cmake_build_options[@]}"

# Test
cmake_test_options=()
cmake_test_options+=("--output-on-failure")
ctest --test-dir "$build_dir" "${cmake_test_options[@]}"