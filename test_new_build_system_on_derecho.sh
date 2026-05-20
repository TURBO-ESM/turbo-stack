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
#   TURBO_BUILD_TEST_DIR  Where override clones, build artifacts, and per-flavor
#                         logs live (default: $HOME/turbo_build_pr_tester)

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

# `:=` applies the default for TURBO_BUILD_TEST_DIR when unset OR empty, so the
# result is always non-empty.  TURBO_STACK_ROOT is required and validated above.
: "${TURBO_BUILD_TEST_DIR:=$HOME/turbo_build_pr_tester}"
export TURBO_BUILD_TEST_DIR

# Branch names for each repo under test.  Centralized here so retargeting the
# script at a different PR set is a one-block edit.
MOM6_BRANCH="192-feature-cmake-build-system-for-MOM6"
TIM_BRANCH="192-feature-cmake-build-system-for-TIM"
FMS_BRANCH="192-feature-cmake-build-system-for-FMS"

# Per-flavor build logs land here.  Overwritten on each run; copy them aside if
# you need history across runs.  The actual mkdir happens after the optional
# --clean step so a dangerous TURBO_BUILD_TEST_DIR triggers the safety guard
# below before any filesystem state is created.
log_dir="$TURBO_BUILD_TEST_DIR/logs"

# Helpers -------------------------------------------------------------------------------

# Idempotent fetch-or-clone.  If $dest already has a git checkout, fetch the
# requested branch and hard-reset to origin/<branch> (this is a PR tester, not
# a dev tree -- we always want exactly origin's state).  Otherwise clone fresh.
_clone_or_update() {
    local repo_url="$1" branch="$2" dest="$3"
    if [[ -d "$dest/.git" ]]; then
        echo "[clone_or_update] $dest exists -- fetching and resetting to origin/$branch"
        git -C "$dest" fetch origin "$branch"
        git -C "$dest" checkout -B "$branch" "origin/$branch"
        git -C "$dest" reset --hard "origin/$branch"
        git -C "$dest" submodule update --init --recursive --force
    else
        echo "[clone_or_update] cloning $repo_url ($branch) into $dest"
        git clone --branch "$branch" --recurse-submodules -- "$repo_url" "$dest"
    fi
}

# Optional clean step -------------------------------------------------------------------

if [[ "$clean" == true ]]; then
    # Sanity-check the paths before rm -rf -- we own these locations by
    # construction (config-section defaults are under $HOME), but a caller
    # could plausibly export TURBO_BUILD_TEST_DIR=/ by accident.
    for d in "$TURBO_BUILD_TEST_DIR" "$TURBO_STACK_ROOT"; do
        case "$d" in
            "" | / | "$HOME")
                echo "Refusing to --clean: '$d' is too broad." >&2
                exit 1
                ;;
        esac
    done
    echo "[--clean] removing override clones, prior build artifacts, and logs"
    rm -rf "$TURBO_BUILD_TEST_DIR/MOM6" \
           "$TURBO_BUILD_TEST_DIR/TIM" \
           "$TURBO_BUILD_TEST_DIR/FMS" \
           "$TURBO_STACK_ROOT/build" \
           "$TURBO_STACK_ROOT/deps" \
           "$log_dir"
fi

# Working-directory setup ---------------------------------------------------------------

# Both mkdirs are idempotent.  Placed after --clean so the safety guard above
# has already vetted $TURBO_BUILD_TEST_DIR before we touch the filesystem.
mkdir -p "$TURBO_BUILD_TEST_DIR" "$log_dir"

# Clone or update the override repos ----------------------------------------------------

# MOM6 / TIM / FMS are PR branches not yet pinned by turbo-stack's submodules.
# Pulling them into $TURBO_BUILD_TEST_DIR and exporting *_ROOT makes
# build_dependencies_from_source.sh use these checkouts instead of the
# submodules.  *_ROOT must be set BEFORE the env setup script runs, since
# build_dependencies_from_source.sh reads them at the top.
cd "$TURBO_BUILD_TEST_DIR"

export MOM6_ROOT="$TURBO_BUILD_TEST_DIR/MOM6"
_clone_or_update https://github.com/TURBO-ESM/MOM6.git "$MOM6_BRANCH" "$MOM6_ROOT"

export TIM_ROOT="$TURBO_BUILD_TEST_DIR/TIM"
_clone_or_update https://github.com/TURBO-ESM/TIM.git "$TIM_BRANCH" "$TIM_ROOT"

export FMS_ROOT="$TURBO_BUILD_TEST_DIR/FMS"
_clone_or_update https://github.com/TURBO-ESM/FMS.git "$FMS_BRANCH" "$FMS_ROOT"

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
    echo
    echo "=== FMS2 build starting at $(date) (log: $log_dir/fms2.log) ==="
    "$TURBO_STACK_ROOT/scripts/build_on_derecho.sh" --infra FMS2 --parallel "$jobs" 2>&1 \
        | tee "$log_dir/fms2.log"
    fms2_rc=${PIPESTATUS[0]}
    echo "=== FMS2 build finished at $(date) (exit $fms2_rc) ==="
fi

if [[ "$run_tim" == true ]]; then
    echo
    echo "=== TIM build starting at $(date) (log: $log_dir/tim.log) ==="
    "$TURBO_STACK_ROOT/scripts/build_on_derecho.sh" --infra TIM --parallel "$jobs" 2>&1 \
        | tee "$log_dir/tim.log"
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
_verdict "FMS2" "$run_fms2" "$fms2_rc"
_verdict "TIM " "$run_tim"  "$tim_rc"
echo "================================================================"

# Propagate failure so the test script's own exit code is meaningful.
if [[ "$run_fms2" == true && $fms2_rc -ne 0 ]] || [[ "$run_tim" == true && $tim_rc -ne 0 ]]; then
    exit 1
fi
