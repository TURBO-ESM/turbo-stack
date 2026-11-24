#!/bin/bash
# Usage: ./scripts/build_on_derecho.sh [options]
#
# `TURBO_STACK_ROOT` is self-located from this script (build the checkout you run
# from). See scripts/README.md for the dependency tier model.  Derecho's Lmod
# modules provide only Tier 1, so this builder builds Tier 1.5 (pFUnit/AMReX) and
# Tier 2 (FMS/TIM) from the submodules, then builds turbo-stack (Tier 3).
#
# Optional environment variables (hot-swap a dep's source; default = submodule):
#   MOM6_ROOT / FMS_ROOT / TIM_ROOT / PROTOMOMXX_ROOT   out-of-tree source overrides
#
# Options:
#   --compiler gnu|intel    Compiler toolchain to load (default: gnu):
#                           gnu = GCC + OpenMPI, intel = Intel oneAPI + Cray
#                           MPICH.
#   --debug                 Build with CMAKE_BUILD_TYPE=Debug (passed through)
#   --clean                 Clean rebuild from scratch.  Removes the Stage-1
#                           upstream dep builds/installs AND passes cmake --fresh
#                           --clean-first to the Stage-2 turbo-stack build.
#   --ninja                 Use Ninja generator (passed through)
#   --infra FMS2|TIM        Infrastructure backend (default: TIM, passed
#                           through to build_turbo_stack.sh).
#   --tests                 Also build pFUnit + the unit-test suite and run
#                           ctest (default: off -- a plain build produces just
#                           the executable, and pFUnit is not built).
#   --build_dir DIR         Build directory for turbo-stack itself (passed
#                           through to build_turbo_stack.sh).  Also controls
#                           where from-source dep cmake builds + installs
#                           land: $DIR/deps/build/<name>/ and
#                           $DIR/deps/install/.  Default:
#                           $TURBO_STACK_ROOT/build/<compiler>-<infra>
#                           (e.g. build/gnu-TIM), so each compiler and backend
#                           keeps its own build.
#   --parallel N, -j N      Parallel build jobs.  Exported as
#                           CMAKE_BUILD_PARALLEL_LEVEL so every downstream
#                           `cmake --build` invocation (deps + turbo-stack)
#                           picks it up natively, without any flag plumbing.
#                           When omitted, cmake's own defaults apply (1 for
#                           Make, nproc for Ninja).
#   -h, --help              Print this usage text and exit.
#
# Examples:
#   build_on_derecho.sh                        # TIM backend, build the executable
#   build_on_derecho.sh --tests                # also build + run the unit tests
#   build_on_derecho.sh --infra FMS2           # FMS2 backend instead of TIM
#   build_on_derecho.sh --compiler intel       # Intel instead of GCC, in build/intel-TIM
#   build_on_derecho.sh --debug --clean        # clean Debug rebuild (deps + turbo-stack)
#
# The MOM6 executable lands at <build dir>/mom6_build/config_src/drivers/solo_driver/MOM6,
# where examples/*/job-derecho.sh look for it.

set -eo pipefail

# Source the shared library (defines the builder core + helpers; no side effects).
# This script lives in scripts/, so the shared library is the sibling lib/ subdir.
# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# Pre-strip the Derecho-only option before the common parser sees it (the shared
# turbo_parse_builder_args rejects unknown flags, by design).
_derecho_compiler=gnu
_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --compiler) _turbo_opt_needs_value "$1" "$#" || exit 1; _derecho_compiler="$2"; shift 2 ;;
        *)          _args+=("$1"); shift ;;
    esac
done
case "$_derecho_compiler" in
    gnu)   _derecho_recipe=derecho_cpu_gcc_openmpi.sh ;;
    intel) _derecho_recipe=derecho_cpu_intel_craympich.sh ;;
    *) echo "Error: --compiler must be gnu or intel (got '$_derecho_compiler')" >&2; exit 1 ;;
esac

# --- Stage 1 (env setup) · toolchain (machine-specific) ------------------------
# Load the chosen Derecho CPU toolchain via Lmod modules (builds nothing).
turbo_flavor_setup_toolchain() {
    # shellcheck source=/dev/null
    source "$TURBO_STACK_ROOT/scripts/setup_environment/$_derecho_recipe"
}

# One build directory per compiler and backend, so building another doesn't
# overwrite this one; its from-source deps go in its deps/ subdirectory.
turbo_flavor_default_build_dir() {
    echo "$TURBO_STACK_ROOT/build/${_derecho_compiler}-${TURBO_B_INFRA}"
}

# Derecho's modules provide only Tier 1, so build Tier 1.5 (pFUnit/AMReX) and
# Tier 2 (FMS/TIM) from the submodules.  turbo_run_backend_builder
# (scripts/lib/common.sh) does the rest: arg parsing, --clean, submodule guards,
# the tiered dep builds, and Stage 2.
turbo_run_backend_builder --build-deps-from-tier 1.5 "${_args[@]}"
