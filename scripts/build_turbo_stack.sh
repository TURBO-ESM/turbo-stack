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
#                       CMAKE_PREFIX_PATH; build_dep.sh (called from the
#                       per-machine env script) handles that for from-source
#                       flavors.
#   --parallel N, -j N  Parallel build jobs for `cmake --build`.  When omitted,
#                       cmake reads $CMAKE_BUILD_PARALLEL_LEVEL as its own
#                       native default (and falls back to the generator's
#                       default if neither is set: 1 for Make, nproc for Ninja).
#                       Orchestrators set CMAKE_BUILD_PARALLEL_LEVEL once for
#                       the whole pipeline; --parallel is for per-call override.
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
parallel=""

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

# Build the code.  Pass --parallel only when the caller set it; otherwise
# cmake reads CMAKE_BUILD_PARALLEL_LEVEL (or falls back to the generator's
# default).
cmake_build_options=()
[[ -n "$parallel" ]] && cmake_build_options+=("--parallel" "$parallel")
if [[ "$debug" == true ]]; then
    cmake_build_options+=("--clean-first")
fi
cmake --build "$build_dir" "${cmake_build_options[@]}" "$@"

# Test
# Honor TURBO_BUILD_UNIT_TESTS: when CMake configured with the option OFF,
# the tests/ subdir is skipped (see CMakeLists.txt) and ctest has nothing
# to run -- worse, --test-dir would still succeed but a future
# --output-on-failure would mislead.  Read the resolved value from the
# CMake cache so users who pass -DTURBO_BUILD_UNIT_TESTS=OFF (via -- or by
# editing the cache) get a tidy "skipped" log instead.
turbo_build_unit_tests=$(grep -m1 '^TURBO_BUILD_UNIT_TESTS:BOOL=' "$build_dir/CMakeCache.txt" 2>/dev/null | cut -d= -f2 || true)
turbo_build_unit_tests=${turbo_build_unit_tests:-ON}
if [[ "$turbo_build_unit_tests" == "ON" || "$turbo_build_unit_tests" == "TRUE" \
   || "$turbo_build_unit_tests" == "1"  || "$turbo_build_unit_tests" == "YES" ]]; then
    ctest --test-dir "$build_dir" --output-on-failure
else
    echo "[build_turbo_stack] TURBO_BUILD_UNIT_TESTS=$turbo_build_unit_tests -- skipping ctest"
fi
