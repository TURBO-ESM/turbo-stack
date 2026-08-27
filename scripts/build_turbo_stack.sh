#!/bin/bash
# Usage: ./scripts/build_turbo_stack.sh [options]
#
# CMake configure, build, and test turbo-stack.
#
# Requires a prepared environment: cmake + MPI compilers on PATH, and any
# from-source deps installed so find_package(FMS|TIM|PFUNIT|AMReX) succeeds.
#
# `TURBO_STACK_ROOT` is self-located from this script (build the checkout you
# run from).
#
# Options:
#   --debug             Build with CMAKE_BUILD_TYPE=Debug 
#   --clean             Clean rebuild from scratch: cmake --fresh (wipe the
#                       configure cache) + --clean-first (clean build artifacts)
#   --ninja             Use Ninja generator instead of the default (Unix Makefiles)
#   --build_dir DIR     Build directory (default: $TURBO_STACK_ROOT/build/default)
#   --infra FMS2|TIM    Infrastructure backend (default: TIM). The chosen
#                       backend must be discoverable via find_package on
#                       CMAKE_PREFIX_PATH; the orchestrator/driver builds it
#                       first via the turbo_build_* wrappers (scripts/lib/common.sh).
#   --tests             Also build pFUnit unit tests and run ctest.  Default:
#                       off -- a plain build produces just the executable.
#   --parallel N, -j N  Parallel build jobs for `cmake --build`.  When omitted,
#                       cmake reads $CMAKE_BUILD_PARALLEL_LEVEL as its own
#                       native default (and falls back to the generator's
#                       default if neither is set: 1 for Make, nproc for Ninja).
#                       Orchestrators set CMAKE_BUILD_PARALLEL_LEVEL once for
#                       the whole pipeline; --parallel is for per-call override.
#   -h, --help          Print this usage text and exit.
#
# Extra arguments for cmake come from the environment, not from flags:
#   TURBO_CMAKE_CONFIGURE_ARGS   appended to the cmake configure line
#   TURBO_CMAKE_BUILD_ARGS       appended to `cmake --build`, e.g.
#                                  TURBO_CMAKE_BUILD_ARGS=-v            (verbose)
#                                  TURBO_CMAKE_BUILD_ARGS='--target MOM6'
# Unknown options are an error, which catches typos like --paralel.

set -eo pipefail

# Source the shared library first (no side effects; just defines functions) so
# --help works while parsing.  TURBO_STACK_ROOT is resolved after parsing (from
# this script's own location).  This script lives in scripts/, so the shared
# library is the sibling lib/ subdir.
# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# Default arguments.  The $build_dir default depends on TURBO_STACK_ROOT, so it
# is filled in after root resolution below.
build_dir=""
build_type="Release"
debug=false
clean=false
ninja=false
infra="TIM"
with_tests=false
parallel=""

# Command line argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build_dir)    _turbo_opt_needs_value "$1" "$#" || exit 1; build_dir="$2"; shift 2 ;;
        --debug)        debug=true; shift ;;
        --clean)        clean=true; shift ;;
        --ninja)        ninja=true; shift ;;
        --infra)        _turbo_opt_needs_value "$1" "$#" || exit 1; infra="$2"; shift 2 ;;
        --tests)        with_tests=true; shift ;;
        --parallel|-j)  _turbo_opt_needs_value "$1" "$#" || exit 1; parallel="$2"; shift 2 ;;
        -h|--help)      turbo_print_header_usage "$0"; exit 0 ;;
        *)
            echo "Error: unknown option '$1' to build_turbo_stack.sh" >&2
            echo "       Extra cmake arguments come from TURBO_CMAKE_CONFIGURE_ARGS /" >&2
            echo "       TURBO_CMAKE_BUILD_ARGS, not from flags." >&2
            exit 1
            ;;
    esac
done

# Resolve TURBO_STACK_ROOT now that --help has had its chance to exit, then fill
# in the $build_dir default relative to it.
turbo_resolve_stack_root
: "${build_dir:=$TURBO_STACK_ROOT/build/default}"

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
# Always pass -DMOM6_INFRA (default TIM) so switching backends -- including
# switching back to the default by dropping --infra -- takes effect on an
# existing build dir instead of a previous choice sticking in the cache.
cmake_generate_options+=("-DMOM6_INFRA=$infra")

# Unit tests are opt-in.  Always pass the option explicitly (ON/OFF) so toggling
# --tests takes effect on an existing build dir without --clean/--fresh --
# a stale cached value would otherwise stick.
if [[ "$with_tests" == true ]]; then
    cmake_generate_options+=("-DTURBO_BUILD_UNIT_TESTS=ON")
else
    cmake_generate_options+=("-DTURBO_BUILD_UNIT_TESTS=OFF")
fi

# Machine- and run-specific configure flags.  An environment variable rather
# than a flag: the need is "on this machine, always pass X" and "for this run,
# also pass Y", which a variable expresses from a shell profile, a qsub
# directive, a flavor's setup_environment recipe, or a CI `env:` block without
# any script having to parse or forward it.  Same reasoning the repo already
# applies to CMAKE_BUILD_PARALLEL_LEVEL.
#
# Placed after the options above so a machine can override what this script
# chose.
if [[ -n "${TURBO_CMAKE_CONFIGURE_ARGS:-}" ]]; then
    turbo_split_cmake_args "$TURBO_CMAKE_CONFIGURE_ARGS" TURBO_CMAKE_CONFIGURE_ARGS
    cmake_generate_options+=("${TURBO_SPLIT_ARGS[@]}")
fi

cmake "${cmake_generate_options[@]}" -S "$source_dir" -B "$build_dir"

# Build the code.  Pass --parallel only when the caller set it; otherwise
# cmake reads CMAKE_BUILD_PARALLEL_LEVEL (or falls back to the generator's
# default).
cmake_build_options=()
[[ -n "$parallel" ]] && cmake_build_options+=("--parallel" "$parallel")
[[ "$clean" == true ]] && cmake_build_options+=("--clean-first")
# As above, for the build phase (e.g. TURBO_CMAKE_BUILD_ARGS=-v).
if [[ -n "${TURBO_CMAKE_BUILD_ARGS:-}" ]]; then
    turbo_split_cmake_args "$TURBO_CMAKE_BUILD_ARGS" TURBO_CMAKE_BUILD_ARGS
    cmake_build_options+=("${TURBO_SPLIT_ARGS[@]}")
fi

cmake --build "$build_dir" "${cmake_build_options[@]}"

# Unit tests are opt-in.  --tests is also what set -DTURBO_BUILD_UNIT_TESTS above,
# and TURBO_CMAKE_CONFIGURE_ARGS is not allowed to override it, so the suite exists
# exactly when this is true.  --no-tests=error: fail if zero tests were registered,
# so a misconfigured suite cannot report a vacuous green (matches the legacy tests
# Makefile).
if [[ "$with_tests" == true ]]; then
    ctest --test-dir "$build_dir" --output-on-failure --no-tests=error
fi
