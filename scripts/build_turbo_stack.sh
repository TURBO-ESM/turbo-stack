#!/bin/bash
# Usage: ./scripts/build_turbo_stack.sh [options]
#
# CMake configure, build, and test turbo-stack.
#
# Requires a prepared environment: cmake + MPI compilers on PATH, and any
# from-source deps installed so find_package(FMS|TIM|PFUNIT|AMReX) succeeds.
# Either run via the orchestrator (scripts/build_with_spack.sh) or first
# source a per-machine recipe under scripts/setup_environment/.
#
# Required environment variables:
#   TURBO_STACK_ROOT    Path to your turbo-stack repository clone
#
# Options:
#   --debug             Cleans the build directory and rebuilds from scratch
#   --ninja             Use Ninja generator instead of the default (Unix Makefiles)
#   --build_dir DIR     Build directory (default: $TURBO_STACK_ROOT/build/default)
#   --infra FMS2|TIM    Infrastructure backend (default: FMS2). The chosen
#                       backend must be discoverable via find_package on
#                       CMAKE_PREFIX_PATH; build_dependencies_from_source.sh
#                       handles that for from-source flavors.
#   --parallel N, -j N  Parallel build jobs for `cmake --build` (default: 1).
#                       Pass an explicit N to parallelize.  The default stays
#                       serial because `nproc` over-reports on shared login
#                       nodes and on PBS/SLURM allocations that don't pin
#                       cpusets -- caller knows the right value, this script
#                       doesn't.
#   --                  End of options to this script.  Anything after `--` is
#                       appended verbatim to `cmake --build`, e.g.
#                         ... -- -v                 (cmake's own --verbose)
#                         ... -- --target MOM6      (build a specific target)
#                         ... -- -- -j 16           (forward -j 16 to the generator)
#                       Unknown options that are NOT preceded by `--` are an
#                       error (catches typos like --paralel).

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
parallel="1"

# Command line argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build_dir)    build_dir="$2"; shift 2 ;;
        --debug)        debug=true; shift ;;
        --ninja)        ninja=true; shift ;;
        --infra)        infra="$2"; shift 2 ;;
        --parallel|-j)  parallel="$2"; shift 2 ;;
        --)             shift; break ;;
        *)
            echo "Error: unknown option '$1' to build_turbo_stack.sh" >&2
            echo "       Pass unknown args after '--' to forward them to \`cmake --build\`." >&2
            exit 1
            ;;
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

cmake "${cmake_generate_options[@]}" -S "$source_dir" -B "$build_dir"

# Build the code.
cmake_build_options=("--parallel" "$parallel")
if [[ "$debug" == true ]]; then
    cmake_build_options+=("--clean-first")
fi
cmake --build "$build_dir" "${cmake_build_options[@]}" "$@"

# Test
cmake_test_options=()
cmake_test_options+=("--output-on-failure")
ctest --test-dir "$build_dir" "${cmake_test_options[@]}"
