#!/bin/bash
# Usage: ./scripts/build_turbo_stack.sh [options]
#
# CMake configure, build, and test turbo-stack.
#
# Requires a prepared environment: cmake + MPI compilers on PATH, and any
# from-source deps installed so find_package(FMS|TIM|PFUNIT|AMReX) succeeds.
#
# `TURBO_STACK_ROOT` is self-located (set it only to override).
#
# Options:
#   --debug             Build with CMAKE_BUILD_TYPE=Debug 
#   --clean             Clean rebuild from scratch: cmake --fresh (wipe the
#                       configure cache) + --clean-first (clean build artifacts)
#   --ninja             Use Ninja generator instead of the default (Unix Makefiles)
#   --build_dir DIR     Build directory (default: $TURBO_STACK_ROOT/build/default)
#   --infra FMS2|TIM    Infrastructure backend (default: FMS2). The chosen
#                       backend must be discoverable via find_package on
#                       CMAKE_PREFIX_PATH; the orchestrator/driver builds it
#                       first via the turbo_build_* wrappers (scripts/lib/common.sh).
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

# Locate + source the shared library, then resolve TURBO_STACK_ROOT (self-
# locating; an exported value is an optional override).  This script lives in
# scripts/, so the shared library is the sibling lib/ subdir.
# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
turbo_resolve_stack_root

# Default arguments
build_dir="$TURBO_STACK_ROOT/build/default"
build_type="Release"
debug=false
clean=false
ninja=false
infra=""
parallel=""

# Command line argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build_dir)    build_dir="$2"; shift 2 ;;
        --debug)        debug=true; shift ;;
        --clean)        clean=true; shift ;;
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

# MOM6 is consumed as source by turbo-stack's CMake (read via MOM6_ROOT) and has
# no build_dep fallback, so default it to the in-tree submodule when unset.
turbo_default_mom6_root

# Generate
cmake_generate_options=()
[[ "$ninja" == true ]] && cmake_generate_options+=("-G" "Ninja")
[[ "$debug" == true ]] && build_type="Debug"
[[ "$clean" == true ]] && cmake_generate_options+=("--fresh")
cmake_generate_options+=("-DCMAKE_BUILD_TYPE=$build_type")
if [[ -n "$infra" ]]; then
    cmake_generate_options+=("-DMOM6_INFRA=$infra")
fi

cmake "${cmake_generate_options[@]}" -S "$source_dir" -B "$build_dir"

# Build the code.  Pass --parallel only when the caller set it; otherwise
# cmake reads CMAKE_BUILD_PARALLEL_LEVEL (or falls back to the generator's
# default).
cmake_build_options=()
[[ -n "$parallel" ]] && cmake_build_options+=("--parallel" "$parallel")
[[ "$clean" == true ]] && cmake_build_options+=("--clean-first")
cmake --build "$build_dir" "${cmake_build_options[@]}" "$@"

# Test
# Honor TURBO_BUILD_UNIT_TESTS: when CMake configured with the option OFF,
# the tests/ subdir is skipped (see CMakeLists.txt) and ctest has nothing to
# run.  Read the resolved value from the CMake cache and run ctest only when
# it is the canonical truthy literal that option() writes: ON.  Anything else
# -- OFF, an unreadable cache, or a hand-edited non-canonical value -- skips
# with a tidy log line instead of a confusing empty-ctest error.
turbo_build_unit_tests=$(grep -m1 '^TURBO_BUILD_UNIT_TESTS:BOOL=' "$build_dir/CMakeCache.txt" 2>/dev/null | cut -d= -f2 || true)
if [[ "$turbo_build_unit_tests" == "ON" ]]; then
    ctest --test-dir "$build_dir" --output-on-failure
else
    echo "[build_turbo_stack] TURBO_BUILD_UNIT_TESTS=${turbo_build_unit_tests:-<unset>} -- skipping ctest"
fi
