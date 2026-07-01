#!/bin/bash
# Usage: ./scripts/build_on_derecho.sh [options]
#
# `TURBO_STACK_ROOT` is self-located (set it only to override). See
# scripts/README.md for the dependency tier model.
#
# Optional environment variables (hot-swap a dep's source; default = submodule):
#   MOM6_ROOT / FMS_ROOT / TIM_ROOT   out-of-tree source overrides
#   PFUNIT_ROOT / AMREX_ROOT          also honored by build_dep
#
# Options:
#   --debug                 Build with CMAKE_BUILD_TYPE=Debug (passed through)
#   --clean                 Clean rebuild from scratch (passed through:
#                           cmake --fresh + --clean-first)
#   --build_dir DIR         Build directory for turbo-stack itself (passed
#                           through to build_turbo_stack.sh).  Also controls
#                           where from-source dep cmake builds + installs
#                           land: $DIR/deps/build/<name>/ and
#                           $DIR/deps/install/.  When --build_dir is omitted,
#                           deps land at $TURBO_STACK_ROOT/deps/default/.
#   --infra FMS2|TIM        Infrastructure backend (default: FMS2, passed
#                           through to build_turbo_stack.sh).
#   --parallel N, -j N      Parallel build jobs.  Exported as
#                           CMAKE_BUILD_PARALLEL_LEVEL so every downstream
#                           `cmake --build` invocation (deps + turbo-stack)
#                           picks it up natively, without any flag plumbing.
#                           When omitted, cmake's own defaults apply (1 for
#                           Make, nproc for Ninja).
#
# Examples:
#   build_on_derecho.sh                              # configure + build + test
#   build_on_derecho.sh --debug                      # full clean rebuild
#   build_on_derecho.sh --infra TIM --debug          # full clean rebuild with TIM backend

set -eo pipefail

debug=false
clean=false
infra="FMS2"
build_dir=""
parallel=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)              debug=true; shift ;;
        --clean)              clean=true; shift ;;
        --infra)              infra="$2"; shift 2 ;;
        --build_dir)          build_dir="$2"; shift 2 ;;
        --parallel|-j)        parallel="$2"; shift 2 ;;
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

# Locate + source the shared library, then resolve TURBO_STACK_ROOT (self-
# locating; an exported value is an optional override).  This script lives in
# scripts/, so the shared library is the sibling lib/ subdir.
# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
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

# Guard the submodules this build consumes (skipped when the matching *_ROOT
# overrides).  Derecho's modules provide none of the Tier-2 deps, so pFUnit and
# the per-infra deps are all built from submodule.
turbo_require_submodule submodules/MOM6   MOM6   MOM6_ROOT
turbo_require_submodule submodules/MARBL  MARBL
turbo_require_submodule submodules/pFUnit pFUnit PFUNIT_ROOT
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
# pFUnit is always needed (unit tests); the infra backend -- plus AMReX, which
# TIM links -- only for the selected --infra.

turbo_build_pfunit "$deps_build_root/build" "$deps_build_root/install"

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
[[ -n "$build_dir"       ]] && build_args+=(--build_dir "$build_dir")
bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" "${build_args[@]}"
