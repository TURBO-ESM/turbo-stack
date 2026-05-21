#!/bin/bash
# Usage: ./test_new_build_system_on_derecho.sh [options]
#
# Drives the FMS2 and TIM build flavors of turbo-stack on Derecho end-to-end,
# against the new-build-system PR branches in MOM6 / TIM / FMS.  Trusts the
# caller to have turbo-stack already checked out at the branch and state they
# want tested -- the script does NOT pull, switch branches, or update
# submodules under $TURBO_STACK_ROOT.
#
# Options:
#   --only FMS2|TIM       Run only the named flavor (default: both)
#   --parallel N, -j N    Parallel build jobs, forwarded to build_on_derecho.sh
#                         (default: 128 -- one full Derecho compute node)
#   --clean               Before doing anything else, rm -rf the override repo
#                         clones (MOM6 / TIM / FMS), turbo-stack's build/ and
#                         deps/ directories, and the per-flavor logs.  Forces a
#                         from-scratch run.  Without --clean, existing override
#                         clones are fetched + reset to origin/<branch>
#                         (idempotent).
#
# Configuration:
#   TURBO_STACK_ROOT      Path to turbo-stack clone (required, no default)
#   TURBO_BUILD_SYSTEM_TEST_DIR  Where override clones, build artifacts, and per-flavor
#                         logs live (default: $TMPDIR/turbo_build_system_test,
#                         or /tmp if $TMPDIR is unset).

set -euo pipefail

if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
    echo "Error: TURBO_STACK_ROOT is not set." >&2
    exit 1
fi

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

# The branches of the dependencies we want to test -- these should be PR
# branches that implement the new CMake build system, but are not yet pinned
# by turbo-stack's submodules.  When the fetch_<NAME> flag below is true, the
# script clones (or updates) into $deps_that_override_submodules_dir and sets
# <NAME>_ROOT so build_dep (called from the env script) and turbo-stack's own
# CMakeLists pick that source up instead of the submodule.
#
# Setting fetch_<NAME>=false here does NOT mean "use the submodule" -- it just
# means "don't have this script clone." If the caller exports <NAME>_ROOT
# before launching the script, that path still wins; the script just doesn't
# overwrite it.  Use this when iterating against a local dev tree:
#   export MOM6_ROOT=/path/to/local/MOM6
#   fetch_MOM6=false ./test_new_build_system_on_derecho.sh   (after editing)
#
# Could change the branches/URLs below to point at other PRs or forks to test
# other combinations of turbo-stack + dependency versions.
fetch_MOM6=true
MOM6_REPO_URL="https://github.com/TURBO-ESM/MOM6.git"
MOM6_BRANCH="192-feature-cmake-build-system-for-MOM6"

fetch_TIM=true
TIM_REPO_URL="https://github.com/TURBO-ESM/TIM.git"
TIM_BRANCH="192-feature-cmake-build-system-for-TIM"

fetch_FMS=true
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

# Where we will build turbo-stack.  
build_dir="$TURBO_BUILD_SYSTEM_TEST_DIR/turbo-stack-build"

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
    echo "[--clean] removing override clones, prior build artifacts, and logs"
    # Note: $TURBO_STACK_ROOT/deps is where deps built from submodules land.
    rm -rf "$build_dir" \
           "$deps_that_override_submodules_dir" \
           "$TURBO_STACK_ROOT/deps" \
           "$log_dir"
fi

# Working-directory setup ---------------------------------------------------------------

# Both mkdirs are idempotent.  Placed after --clean so the safety guard above
# has already vetted $TURBO_BUILD_SYSTEM_TEST_DIR before we touch the filesystem.
mkdir -p "$TURBO_BUILD_SYSTEM_TEST_DIR" "$build_dir" "$log_dir" "$deps_that_override_submodules_dir"

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
_print_version() {
    local label="$1" repo_root="$2"
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
_print_version "MOM6"        "$MOM6_ROOT"
_print_version "TIM"         "$TIM_ROOT"
_print_version "FMS"         "$FMS_ROOT"
echo "================================================================"

# Run the build and test script ---------------------------------------------------------

# Drop `set -e` around the build invocations so a failure in one flavor doesn't
# skip the other.  Capture each build's exit code via ${PIPESTATUS[0]} -- the
# leftmost command in the pipe (build_on_derecho.sh), not tee's exit code.
fms2_rc=0
tim_rc=0
set +e

if [[ "$run_fms2" == true ]]; then
    fms_build_dir="$build_dir/turbo-stack-with-FMS2"
    echo
    echo "=== FMS2 build starting at $(date) (log: $log_dir/turbo-stack-with-FMS2.log, build dir: $fms_build_dir) ==="
    "$TURBO_STACK_ROOT/scripts/build_on_derecho.sh" --infra FMS2 \
                                                    --build_dir "$fms_build_dir" \
                                                    --parallel "$jobs" 2>&1 \
                                                    | tee "$log_dir/turbo-stack-with-FMS2.log"
    fms2_rc=${PIPESTATUS[0]}
    echo "=== FMS2 build finished at $(date) (exit $fms2_rc) ==="
fi

if [[ "$run_tim" == true ]]; then
    tim_build_dir="$build_dir/turbo-stack-with-TIM"
    echo
    echo "=== TIM build starting at $(date) (log: $log_dir/turbo-stack-with-TIM.log, build dir: $tim_build_dir) ==="
    "$TURBO_STACK_ROOT/scripts/build_on_derecho.sh" --infra TIM \
                                                    --build_dir "$tim_build_dir" \
                                                    --parallel "$jobs" 2>&1 \
                                                    | tee "$log_dir/turbo-stack-with-TIM.log"
    tim_rc=${PIPESTATUS[0]}
    echo "=== TIM build finished at $(date) (exit $tim_rc) ==="
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
