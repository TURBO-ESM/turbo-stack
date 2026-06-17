#!/bin/bash
#PBS -N turbo-stack-new-build-system-test
#PBS -A NCGD0067
#PBS -q main
#PBS -l select=1:ncpus=128:mpiprocs=128:mem=100GB
#PBS -l walltime=01:00:00
#PBS -j oe
#PBS -V

# Usage: ./test_new_build_system_on_derecho.sh [options]
#
# Drives the FMS2 and TIM build flavors of turbo-stack on Derecho end-to-end,
# against the new-build-system PR branches in MOM6 / TIM / FMS.  Trusts the
# caller to have turbo-stack already checked out at the branch and state they
# want tested -- the script does NOT pull, switch branches, or update
# submodules under $TURBO_STACK_ROOT.  All artifacts (fetched source clones,
# dep cmake builds + installs, turbo-stack builds, logs) land under
# $TURBO_BUILD_SYSTEM_TEST_DIR; nothing is written into $TURBO_STACK_ROOT.
#
# Options:
#   --only FMS2|TIM       Run only the named flavor (default: both)
#   --parallel N, -j N    Parallel build jobs, exported as
#                         CMAKE_BUILD_PARALLEL_LEVEL for every downstream
#                         `cmake --build` invocation (deps + both
#                         turbo-stack flavors).  Default: 128 (one full
#                         Derecho compute node).
#   --clean               Before doing anything else, rm -rf all artifacts
#                         under $TURBO_BUILD_SYSTEM_TEST_DIR (override clones,
#                         turbo-stack build dirs, dep cmake builds + installs,
#                         logs).  Forces a from-scratch run.  Without --clean,
#                         existing override clones are fetched + reset to
#                         origin/<branch> (idempotent), and dep installs are
#                         reused via build_dep's sentinel-skip.
#
# Configuration (env vars; export before invoking, or pass inline as `VAR=val ./script.sh`):
#
#   TURBO_STACK_ROOT             Path to turbo-stack clone.  Defaults to the directory containing this script.
#
#   TURBO_BUILD_SYSTEM_TEST_DIR  Where override clones, build artifacts, and
#                                per-flavor logs live.  Default:
#                                $TMPDIR/turbo_build_system_test (or
#                                /tmp/turbo_build_system_test if $TMPDIR is unset).
#
#   fetch_MOM6 / fetch_TIM / fetch_FMS
#                                (default: true)  When true, this script clones
#                                the configured PR branch into the override dir
#                                and exports <NAME>_ROOT for downstream
#                                build_dep calls.  Set to false to keep this
#                                script out of the override dir entirely --
#                                typically combined with an exported <NAME>_ROOT
#                                pointing at a local dev tree.
#
#   MOM6_ROOT / TIM_ROOT / FMS_ROOT
#                                Local checkouts to test against.  When set,
#                                build_dep (called from the env script) and
#                                turbo-stack's CMakeLists pick these up via the
#                                env-var precedence layer.  Pair with
#                                fetch_<NAME>=false to suppress this script's
#                                clone step.  Example:
#                                  fetch_MOM6=false MOM6_ROOT=$HOME/dev/MOM6 \
#                                      ./test_new_build_system_on_derecho.sh

set -euo pipefail

# Argument parsing ----------------------------------------------------------------------

jobs=128
only=""
clean=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)         only="$2"; shift 2 ;;
        --parallel|-j)  jobs="$2"; shift 2 ;;
        --clean)        clean=true; shift ;;
        *)
            echo "Error: unknown option '$1' to test_new_build_system_on_derecho.sh" >&2
            exit 1
            ;;
    esac
done

if [[ -n "$only" && "$only" != "FMS2" && "$only" != "TIM" ]]; then
    echo "Error: --only must be FMS2 or TIM (got '$only')" >&2
    exit 1
fi

run_fms2=true
run_tim=true
[[ "$only" == "FMS2" ]] && run_tim=false
[[ "$only" == "TIM"  ]] && run_fms2=false

# Configuration -------------------------------------------------------------------------

export TURBO_STACK_ROOT="${TURBO_STACK_ROOT:-$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)}"
if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
    echo "Error: TURBO_STACK_ROOT could not be resolved." >&2
    exit 1
fi

# URLs and branches for each fetched dep.  These should be the PR branches that
# implement the new CMake build system but are not yet pinned by turbo-stack's
# submodules.  Edit to point at other PRs / forks when testing different
# combinations.  The fetch_<NAME> defaults below use `:=` so callers can flip
# them off without editing this file (see header for examples).
: "${fetch_MOM6:=true}"
MOM6_REPO_URL="https://github.com/TURBO-ESM/MOM6.git"
MOM6_BRANCH="192-feature-cmake-build-system-for-MOM6"

: "${fetch_TIM:=true}"
TIM_REPO_URL="https://github.com/TURBO-ESM/TIM.git"
TIM_BRANCH="192-feature-cmake-build-system-for-TIM"

: "${fetch_FMS:=true}"
FMS_REPO_URL="https://github.com/TURBO-ESM/FMS.git"
FMS_BRANCH="192-feature-cmake-build-system-for-FMS"

# `:=` applies the default for TURBO_BUILD_SYSTEM_TEST_DIR when unset OR empty, so the
# result is always non-empty.  TURBO_STACK_ROOT is required and validated above.
: "${TURBO_BUILD_SYSTEM_TEST_DIR:=${TMPDIR:-/tmp}/turbo_build_system_test}"
export TURBO_BUILD_SYSTEM_TEST_DIR

# Per-flavor build logs land here.  Overwritten on each run; copy them aside if
# you need history across runs.  The actual mkdir happens after the optional
# --clean step so a dangerous TURBO_BUILD_SYSTEM_TEST_DIR triggers the safety guard
# below before any filesystem state is created.
log_dir="$TURBO_BUILD_SYSTEM_TEST_DIR/logs"

# Where the clones of the dependencies we will use instead of the submodules
# from turbo-stack live.  These are populated by fetch_source below; build_dep
# (called from the env script) then uses them instead of the submodules because
# *_ROOT is set.
deps_that_override_submodules_dir="$TURBO_BUILD_SYSTEM_TEST_DIR/deps_that_override_submodules"

# Where we will build turbo-stack.  Each per-flavor block below points its own
# --build_dir at a subdir under here.
build_dir="$TURBO_BUILD_SYSTEM_TEST_DIR/turbo-stack-build"

# Where the from-source deps (FMS / pFUnit / AMReX / TIM) build + install.
# Shared across both flavors: the env script is sourced ONCE with this path,
# deps build once, and both turbo-stack-build flavors find them via the
# CMAKE_PREFIX_PATH the env script appends.  The deps don't depend on
# MOM6_INFRA, so sharing is safe -- the second flavor's cmake config picks
# the same install tree and the build_dep sentinel-skip avoids a rebuild.
shared_deps_dir="$TURBO_BUILD_SYSTEM_TEST_DIR/shared-deps"

# Helpers -------------------------------------------------------------------------------

# Source the fetch_source library; clone-or-update logic now lives there.
# shellcheck source=/dev/null
source "$TURBO_STACK_ROOT/scripts/fetch_source.sh"

# Optional clean step -------------------------------------------------------------------

if [[ "$clean" == true ]]; then
    # Sanity-check the paths before rm -rf -- we own these locations by
    # construction (default is under $TMPDIR), but a caller could plausibly
    # export TURBO_BUILD_SYSTEM_TEST_DIR=/ by accident.
    for d in "$TURBO_BUILD_SYSTEM_TEST_DIR" "$TURBO_STACK_ROOT"; do
        case "$d" in
            "" | / | "$HOME")
                echo "Refusing to --clean: '$d' is too broad." >&2
                exit 1
                ;;
        esac
    done
    echo "[--clean] removing override clones, prior build artifacts, deps, and logs"
    rm -rf "$build_dir" \
           "$shared_deps_dir" \
           "$deps_that_override_submodules_dir" \
           "$log_dir"
fi

# Working-directory setup ---------------------------------------------------------------

# Both mkdirs are idempotent.  Placed after --clean so the safety guard above
# has already vetted $TURBO_BUILD_SYSTEM_TEST_DIR before we touch the filesystem.
mkdir -p "$TURBO_BUILD_SYSTEM_TEST_DIR" \
         "$build_dir" \
         "$shared_deps_dir" \
         "$log_dir" \
         "$deps_that_override_submodules_dir"

# Clone or update the override repos ----------------------------------------------------

# MOM6 / TIM / FMS are PR branches not yet pinned by turbo-stack's submodules.
# fetch_source pulls each into $deps_that_override_submodules_dir and exports
# the matching <NAME>_ROOT, which downstream build_dep calls (in the env
# script) and turbo-stack's CMakeLists.txt then pick up via the env-var
# precedence layer.
cd "$deps_that_override_submodules_dir"

if [[ "$fetch_MOM6" == true ]]; then
    fetch_source --name MOM6 --url "$MOM6_REPO_URL" --branch "$MOM6_BRANCH" \
                 --dest "$deps_that_override_submodules_dir/MOM6"
fi

if [[ "$fetch_TIM" == true ]]; then
    fetch_source --name TIM --url "$TIM_REPO_URL" --branch "$TIM_BRANCH" \
                 --dest "$deps_that_override_submodules_dir/TIM"
fi

if [[ "$fetch_FMS" == true ]]; then
    fetch_source --name FMS --url "$FMS_REPO_URL" --branch "$FMS_BRANCH" \
                 --dest "$deps_that_override_submodules_dir/FMS"
fi

# Record what we're testing -------------------------------------------------------------

# Print the SHA + branch of every checkout so a run is reproducible later --
# paste this into the PR description or the post-mortem.
# Tolerates an unset / empty repo_root: the script header documents a
# `fetch_<NAME>=false <NAME>_ROOT=...` workflow, but a user who didn't export
# the ROOT path would otherwise trip `set -u` here before any build runs.
_print_version() {
    local label="$1" repo_root="$2"
    if [[ -z "$repo_root" ]]; then
        printf "  %-12s @ <not set>\n" "$label"
        return
    fi
    local sha branch
    sha=$(git -C "$repo_root" rev-parse HEAD)
    branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD)
    printf "  %-12s @ %s  (branch %s)\n" "$label" "$sha" "$branch"
}

echo
echo "================================================================"
echo "Testing matrix"
echo "================================================================"
_print_version "turbo-stack" "$TURBO_STACK_ROOT"
_print_version "MOM6"        "${MOM6_ROOT:-}"
_print_version "TIM"         "${TIM_ROOT:-}"
_print_version "FMS"         "${FMS_ROOT:-}"
echo "================================================================"

# Build shared deps once ----------------------------------------------------------------

# Set CMAKE_BUILD_PARALLEL_LEVEL before sourcing the env script -- cmake reads
# it natively in every downstream `cmake --build` invocation (both the dep
# builds and the per-flavor turbo-stack builds below).  No --parallel plumbing
# needed past this point.
export CMAKE_BUILD_PARALLEL_LEVEL="$jobs"

# Source the env script ONCE.  It loads modules, then builds + installs
# FMS / pFUnit / AMReX / TIM into $shared_deps_dir and appends the install
# prefix to CMAKE_PREFIX_PATH.  Both flavors below find the deps that way --
# no rebuild between flavors.  set -e is intentionally still active here:
# any failure (modules, dep build) bails the whole test driver.
echo
echo "=== Shared deps build starting at $(date) (deps_build_root: $shared_deps_dir) ==="
# shellcheck source=/dev/null
source "$TURBO_STACK_ROOT/scripts/setup_environment/derecho_cpu_gcc_openmpi.sh" \
    --deps-build-root "$shared_deps_dir"
echo "=== Shared deps build finished at $(date) ==="

# Run each flavor's turbo-stack build -----------------------------------------------------

# Drop `set -e` around the build invocations so a failure in one flavor doesn't
# skip the other.  Capture each build's exit code via ${PIPESTATUS[0]} -- the
# leftmost command in the pipe (build_turbo_stack.sh), not tee's exit code.
fms2_rc=0
tim_rc=0
set +e

if [[ "$run_fms2" == true ]]; then
    fms_build_dir="$build_dir/turbo-stack-with-FMS2"
    echo
    echo "=== FMS2 turbo-stack build starting at $(date) (log: $log_dir/turbo-stack-with-FMS2.log, build dir: $fms_build_dir) ==="
    bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" --infra FMS2 \
                                                           --build_dir "$fms_build_dir" 2>&1 \
                                                           | tee "$log_dir/turbo-stack-with-FMS2.log"
    fms2_rc=${PIPESTATUS[0]}
    echo "=== FMS2 turbo-stack build finished at $(date) (exit $fms2_rc) ==="
fi

if [[ "$run_tim" == true ]]; then
    tim_build_dir="$build_dir/turbo-stack-with-TIM"
    echo
    echo "=== TIM turbo-stack build starting at $(date) (log: $log_dir/turbo-stack-with-TIM.log, build dir: $tim_build_dir) ==="
    bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" --infra TIM \
                                                          --build_dir "$tim_build_dir" 2>&1 \
                                                          | tee "$log_dir/turbo-stack-with-TIM.log"
    tim_rc=${PIPESTATUS[0]}
    echo "=== TIM turbo-stack build finished at $(date) (exit $tim_rc) ==="
fi

set -e

# Summary -------------------------------------------------------------------------------

_verdict() {
    local label="$1" ran="$2" rc="$3"
    if [[ "$ran" != true ]]; then
        echo "  $label : SKIPPED"
    elif [[ "$rc" -eq 0 ]]; then
        echo "  $label : PASS"
    else
        echo "  $label : FAIL (exit $rc)"
    fi
}

echo
echo "================================================================"
echo "Build summary"
echo "================================================================"
_verdict "turbo-stack with FMS2" "$run_fms2" "$fms2_rc"
_verdict "turbo-stack with TIM" "$run_tim"  "$tim_rc"
echo "================================================================"

# Propagate failure so the test script's own exit code is meaningful.
if [[ "$run_fms2" == true && $fms2_rc -ne 0 ]] || [[ "$run_tim" == true && $tim_rc -ne 0 ]]; then
    exit 1
fi
