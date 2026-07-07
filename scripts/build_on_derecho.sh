#!/bin/bash
# Usage: ./scripts/build_on_derecho.sh [options]
#
# `TURBO_STACK_ROOT` is self-located from this script (build the checkout you run
# from). See scripts/README.md for the dependency tier model.
#
# Optional environment variables (hot-swap a dep's source; default = submodule):
#   MOM6_ROOT / FMS_ROOT / TIM_ROOT   out-of-tree source overrides
#
# Options:
#   --debug                 Build with CMAKE_BUILD_TYPE=Debug (passed through)
#   --clean                 Clean rebuild from scratch.  Removes the Tier-2 dep
#                           builds/installs AND passes cmake --fresh
#                           --clean-first to the Tier-3 turbo-stack build.
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
#   build_on_derecho.sh --debug --clean        # clean Debug rebuild (deps + Tier 3)

set -eo pipefail

# Source the shared library first (no side effects; just defines functions), so
# --help and the --clean guard are available while parsing.  This script lives
# in scripts/, so the shared library is the sibling lib/ subdir.
# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

debug=false
clean=false
infra="TIM"
with_tests=false
build_dir=""
parallel=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)              debug=true; shift ;;
        --clean)              clean=true; shift ;;
        --infra)              infra="$2"; shift 2 ;;
        --tests)              with_tests=true; shift ;;
        --build_dir)          build_dir="$2"; shift 2 ;;
        --parallel|-j)        parallel="$2"; shift 2 ;;
        -h|--help)            turbo_print_header_usage "$0"; exit 0 ;;
        *)
            echo "Error: unknown option '$1' to build_on_derecho.sh" >&2
            exit 1
            ;;
    esac
done

if [[ "$infra" != "FMS2" && "$infra" != "TIM" ]]; then
    echo "Error: --infra must be FMS2 or TIM (got '$infra')" >&2
    exit 1
fi

# Resolve TURBO_STACK_ROOT (self-locating; a mismatching exported value is a
# hard error -- see turbo_resolve_stack_root).
turbo_resolve_stack_root

# Set CMAKE_BUILD_PARALLEL_LEVEL once -- cmake reads it natively, so every
# `cmake --build` in the rest of the pipeline (deps + turbo-stack) picks
# this up without further flag plumbing.
[[ -n "$parallel" ]] && export CMAKE_BUILD_PARALLEL_LEVEL="$parallel"

# Where the from-source Tier-2 deps build + install: $build_dir/deps when given,
# else $TURBO_STACK_ROOT/deps/default.
if [[ -n "$build_dir" ]]; then
    deps_build_root="$build_dir/deps"
else
    deps_build_root="$TURBO_STACK_ROOT/deps/default"
fi

# --clean covers Tier 2 as well as Tier 3: wipe the dep builds/installs here, and
# forward --clean to build_turbo_stack.sh (cmake --fresh --clean-first) below.
# This is the same "Tier 2 + Tier 3" definition the end-to-end driver uses (see
# scripts/lib/common.sh).
if [[ "$clean" == true ]]; then
    turbo_validate_clean_paths "$deps_build_root" || exit 1
    echo "[--clean] removing Tier-2 dep artifacts under $deps_build_root"
    rm -rf "$deps_build_root"
fi

# Guard the submodules this build consumes (skipped when the matching *_ROOT
# overrides).  Derecho's modules provide none of the Tier-2 deps, so pFUnit and
# the per-infra deps are all built from submodule.
turbo_require_submodule submodules/MOM6   MOM6   MOM6_ROOT
turbo_require_submodule submodules/MARBL  MARBL
[[ "$with_tests" == true ]] && turbo_require_submodule submodules/pFUnit pFUnit PFUNIT_ROOT
if [[ "$infra" == "TIM" ]]; then
    turbo_require_submodule submodules/infra/TIM TIM   TIM_ROOT
    turbo_require_submodule submodules/amrex     AMReX AMREX_ROOT
else
    turbo_require_submodule submodules/infra/FMS2 FMS  FMS_ROOT
fi

# --- Tier 1: toolchain (Lmod modules only; no dependency builds) ---------
# shellcheck source=/dev/null
source "$TURBO_STACK_ROOT/scripts/setup_environment/derecho_cpu_gcc_openmpi.sh"

# --- Tier 2: build deps explicitly ---------------------------------------
# Derecho's modules provide none of these, so build from submodule (or each
# $<NAME>_ROOT override).  Canonical flags live in scripts/lib/common.sh.
# pFUnit is built only when --tests is given; the infra backend -- plus
# AMReX, which TIM links -- only for the selected --infra.

if [[ "$with_tests" == true ]]; then
    turbo_build_pfunit "$deps_build_root/build" "$deps_build_root/install"
fi

if [[ "$infra" == "TIM" ]]; then
    turbo_build_amrex "$deps_build_root/build" "$deps_build_root/install"
    turbo_build_tim   "$deps_build_root/build" "$deps_build_root/install"
fi

if [[ "$infra" == "FMS2" ]]; then
    turbo_build_fms   "$deps_build_root/build" "$deps_build_root/install"
fi

# --- Tier 3: configure + build + test turbo-stack ------------------------
build_args=()
[[ "$debug"      == true ]] && build_args+=(--debug)
[[ "$clean"      == true ]] && build_args+=(--clean)
[[ -n "$infra"           ]] && build_args+=(--infra "$infra")
[[ "$with_tests" == true ]] && build_args+=(--tests)
[[ -n "$build_dir"       ]] && build_args+=(--build_dir "$build_dir")
bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" "${build_args[@]}"
