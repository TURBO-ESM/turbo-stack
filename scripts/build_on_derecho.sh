#!/bin/bash
# Usage: ./scripts/build_on_derecho.sh [options]
#
# `TURBO_STACK_ROOT` is self-located from this script (build the checkout you run
# from). See scripts/README.md for the dependency tier model.  Derecho's Lmod
# modules provide only Tier 1, so this builder builds Tier 1.5 (pFUnit/AMReX) and
# Tier 2 (FMS/TIM) from the submodules, then builds turbo-stack (Tier 3).
#
# Optional environment variables (hot-swap a dep's source; default = submodule):
#   MOM6_ROOT / FMS_ROOT / TIM_ROOT   out-of-tree source overrides
#
# Options:
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
#                           $DIR/deps/install/.  When --build_dir is omitted,
#                           deps land at $TURBO_STACK_ROOT/deps/default/.
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
#   build_on_derecho.sh --debug --clean        # clean Debug rebuild (deps + turbo-stack)

set -eo pipefail

# Source the shared library (defines the builder core + helpers; no side effects).
# This script lives in scripts/, so the shared library is the sibling lib/ subdir.
# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# --- Stage 1 (env setup) · toolchain (machine-specific) ------------------------
# Load Derecho's CPU / gcc / OpenMPI toolchain via Lmod modules (builds nothing).
turbo_flavor_setup_toolchain() {
    # shellcheck source=/dev/null
    source "$TURBO_STACK_ROOT/scripts/setup_environment/derecho_cpu_gcc_openmpi.sh"
}

# Derecho's modules provide only Tier 1, so build Tier 1.5 (pFUnit/AMReX) and
# Tier 2 (FMS/TIM) from the submodules.  turbo_run_backend_builder
# (scripts/lib/common.sh) does the rest: arg parsing, --clean, submodule guards,
# the tiered dep builds, and Stage 2.
turbo_run_backend_builder --build-deps-from-tier 1.5 "$@"
