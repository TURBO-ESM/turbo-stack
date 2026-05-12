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
#   --debug           Cleans the build directory and rebuilds from scratch
#   --ninja           Use Ninja generator instead of the default (Unix Makefiles)
#   --build_dir DIR   Build directory (default: $TURBO_STACK_ROOT/build/default)
#   --infra FMS2|TIM  Infrastructure backend (default: FMS2); TIM also requires TIM_ROOT

set -eo pipefail

if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
    echo "Error: TURBO_STACK_ROOT is not set." >&2
    exit 1
fi

# Default arguments
build_dir="$TURBO_STACK_ROOT/build/default"
build_type="Release"
debug=false
ninja=false
infra=""

# Command line argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build_dir)   build_dir="$2"; shift 2 ;;
        --debug)       debug=true; shift ;;
        --ninja)       ninja=true; shift ;;
        --infra)       infra="$2"; shift 2 ;;
        *)             break ;;
    esac
done

source_dir="$TURBO_STACK_ROOT"

# Generate
cmake_generate_options=()
#cmake_generate_options+=("-DCMAKE_C_COMPILER=$CC")
#cmake_generate_options+=("-DCMAKE_CXX_COMPILER=$CXX")
[[ "$ninja" == true ]] && cmake_generate_options+=("-G" "Ninja")
if [[ "$debug" == true ]]; then
    build_type="Debug"
    cmake_generate_options+=("--fresh")
fi
cmake_generate_options+=("-DCMAKE_BUILD_TYPE=$build_type")
if [[ -n "$infra" ]]; then
    cmake_generate_options+=("-DTURBO_INFRA=$infra")
fi

# Pre-build TIM before configuring turbo-stack so find_package(TIM) can use the build tree.
# TIM_ROOT (env var): TIM source directory — used to build TIM.
# TIM_DIR  (cmake):   directory containing TIMConfig.cmake — CMake's standard find_package hint.
if [[ "$infra" == "TIM" ]]; then
    if [[ -z "${TIM_ROOT:-}" ]]; then
        echo "Error: --infra TIM requires TIM_ROOT to be set in the environment." >&2
        exit 1
    fi
    tim_build_dir="$TURBO_STACK_ROOT/build/tim"
    echo "--- Building TIM ($TIM_ROOT) ---"
    # Delete the TIM build directory if it is stale (wrong source) or a full
    # clean rebuild is requested.  rm -rf is used instead of cmake --fresh
    # because --fresh only removes CMakeCache.txt/CMakeFiles/, leaving behind
    # generated .cmake config files that would shadow the correct ones.
    _tim_needs_clean=false
    if [[ "$debug" == true ]]; then
        _tim_needs_clean=true
    elif [[ -f "$tim_build_dir/CMakeCache.txt" ]]; then
        cached_src=$(grep "^CMAKE_HOME_DIRECTORY:INTERNAL=" "$tim_build_dir/CMakeCache.txt" | cut -d= -f2)
        [[ "$cached_src" != "$TIM_ROOT" ]] && _tim_needs_clean=true
    fi
    [[ "$_tim_needs_clean" == true ]] && rm -rf "$tim_build_dir"

    tim_cmake_opts=("-DCMAKE_BUILD_TYPE=$build_type" "-D64BIT=ON" "-D32BIT=OFF")
    [[ "$ninja" == true ]] && tim_cmake_opts=("-G" "Ninja" "${tim_cmake_opts[@]}")
    cmake "${tim_cmake_opts[@]}" -S "$TIM_ROOT" -B "$tim_build_dir"
    cmake --build "$tim_build_dir"
    cmake_generate_options+=("-DTIM_DIR=$tim_build_dir/lib/cmake/tim")
fi

cmake "${cmake_generate_options[@]}" -S "$source_dir" -B "$build_dir"

# Build the code.
cmake_build_options=()
if [[ "$debug" == true ]]; then
    cmake_build_options+=("--clean-first")
fi
cmake --build "$build_dir" "${cmake_build_options[@]}"

# Test
cmake_test_options=()
cmake_test_options+=("--output-on-failure")
ctest --test-dir "$build_dir" "${cmake_test_options[@]}"
