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
# Drives the FMS2 and TIM build flavors of turbo-stack on Derecho end-to-end.
# By default it tests the MOM6 / TIM / FMS sources that turbo-stack pins as
# submodules -- now that the CMake-build-system PRs are merged and the submodule
# pins point at the merged commits.  Trusts the caller to have turbo-stack
# already checked out at the branch and state they want tested, WITH its
# submodules initialized (git submodule update --init --recursive) -- the script
# does NOT pull, switch branches, or update submodules under $TURBO_STACK_ROOT.
#
# Any of MOM6 / TIM / FMS can optionally be overridden with an out-of-tree
# checkout instead of its submodule -- e.g. to test an un-pinned PR branch or a
# local dev tree (see fetch_<NAME> / <NAME>_ROOT below).  All artifacts (any
# override clones, dep cmake builds + installs, turbo-stack builds, logs) land
# under $TURBO_BUILD_SYSTEM_TEST_DIR; nothing is written into $TURBO_STACK_ROOT.
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
#                                (default: false)  When false (the default), the
#                                source pinned by turbo-stack's submodule is
#                                used.  When true, this script clones the
#                                configured branch into the override dir and
#                                exports <NAME>_ROOT, so that clone is used
#                                INSTEAD of the submodule.  Set true to test an
#                                un-pinned PR branch; or leave it false and
#                                export <NAME>_ROOT yourself to test a local dev
#                                tree.
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

# Resolve TURBO_STACK_ROOT automatically.
# No single source is reliable across both batch and interactive runs (a batch
# job's script is copied to the PBS spool dir, so self-location fails there), so
# we try each candidate in order and validate it against a known repo file before
# trusting it. A wrong guess is rejected rather than silently used.
_resolve_turbo_stack_root() {
    local candidate args script
    local marker="scripts/fetch_source.sh"

    # 0. explicit override, if someone really wants one
    [[ -n "${TURBO_STACK_ROOT:-}" && -f "${TURBO_STACK_ROOT}/${marker}" ]] \
        && { printf '%s\n' "$TURBO_STACK_ROOT"; return 0; }

    # 1. self-location — correct for a direct run (interactive job or plain shell)
    candidate=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd) || candidate=
    [[ -n "$candidate" && -f "${candidate}/${marker}" ]] \
        && { printf '%s\n' "$candidate"; return 0; }

    # 2. PBS submit dir — correct for `qsub this_script.sh` run from the repo directory
    [[ -n "${PBS_O_WORKDIR:-}" && -f "${PBS_O_WORKDIR}/${marker}" ]] \
        && { printf '%s\n' "$PBS_O_WORKDIR"; return 0; }

    # 3. reconstruct the submitted script path from PBS — correct for
    #    `qsub path/to/this/script.sh` from any directory (PBS_O_WORKDIR is the submit
    #    cwd, not the script's dir; the script is the last token of Submit_arguments)
    if [[ -n "${PBS_JOBID:-}" ]] && command -v qstat >/dev/null 2>&1; then
        args=$(qstat -f "$PBS_JOBID" 2>/dev/null | sed -n 's/^[[:space:]]*Submit_arguments = //p')
        script=${args##* }
        if [[ -n "$script" && "$script" != "--" ]]; then
            [[ "$script" == /* ]] || script="${PBS_O_WORKDIR:-$PWD}/$script"
            candidate=$(cd -P -- "$(dirname -- "$script")" 2>/dev/null && pwd) || candidate=
            [[ -n "$candidate" && -f "${candidate}/${marker}" ]] \
                && { printf '%s\n' "$candidate"; return 0; }
        fi
    fi

    return 1
}

if ! TURBO_STACK_ROOT=$(_resolve_turbo_stack_root); then
    echo "Error: could not locate the turbo-stack root automatically." >&2
    echo "  As a last resort, set it explicitly: export TURBO_STACK_ROOT=/path/to/turbo-stack" >&2
    exit 1
fi
export TURBO_STACK_ROOT

# Override sources, consulted ONLY when the matching fetch_<NAME> is true.  By
# default fetch_<NAME> is false and the in-tree submodule is used instead.  The
# branches below default to each repo's integration branch -- the merge target
# of the CMake-build-system PRs -- so flipping a fetch on tests the latest tip
# against the stack; edit a URL/branch to point at a specific PR or fork.  The
# `:=` defaults let callers flip a fetch on without editing this file (e.g.
# `fetch_MOM6=true ./test_new_build_system_on_derecho.sh`).
: "${fetch_MOM6:=false}"
MOM6_REPO_URL="https://github.com/TURBO-ESM/MOM6.git"
MOM6_BRANCH="dev/turbo"

: "${fetch_TIM:=false}"
TIM_REPO_URL="https://github.com/TURBO-ESM/TIM.git"
TIM_BRANCH="main"

: "${fetch_FMS:=false}"
FMS_REPO_URL="https://github.com/TURBO-ESM/FMS.git"
FMS_BRANCH="dev/turbo"

# `:=` applies the default for TURBO_BUILD_SYSTEM_TEST_DIR when unset OR empty, so the
# result is always non-empty.  TURBO_STACK_ROOT is required and validated above.
: "${TURBO_BUILD_SYSTEM_TEST_DIR:=${TMPDIR:-/tmp}/turbo_build_system_test}"
export TURBO_BUILD_SYSTEM_TEST_DIR

# Per-flavor build logs land here.  Overwritten on each run; copy them aside if
# you need history across runs.  The actual mkdir happens after the optional
# --clean step so a dangerous TURBO_BUILD_SYSTEM_TEST_DIR triggers the safety guard
# below before any filesystem state is created.
log_dir="$TURBO_BUILD_SYSTEM_TEST_DIR/logs"

# Where any override clones live (populated by fetch_source below only for the
# components whose fetch_<NAME>=true).  When an override clone exists its
# <NAME>_ROOT is exported, so build_dep (called from the env script) and
# turbo-stack's CMakeLists use it instead of the submodule.  With the defaults
# (all fetch_<NAME>=false) this directory stays empty and the submodules win.
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

# Optionally override a component's submodule with an out-of-tree clone.  For
# each fetch_<NAME>=true, fetch_source pulls the configured branch into
# $deps_that_override_submodules_dir and exports the matching <NAME>_ROOT, which
# downstream build_dep calls (in the env script) and turbo-stack's CMakeLists.txt
# then pick up via the env-var precedence layer -- taking priority over the
# submodule.  With the defaults (all false) nothing is fetched and the
# submodules are used as-is.
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

# Print the effective source of each component (SHA + branch) so a run is
# reproducible later -- paste this into the PR description or the post-mortem.
# Each component uses its in-tree submodule unless overridden by a set
# <NAME>_ROOT (an override clone from fetch_<NAME>=true, or a local dev tree).
_print_source() {
    local label="$1" override_root="$2" submodule_path="$3"
    local src kind
    if [[ -n "$override_root" ]]; then
        src="$override_root"; kind="override"
    else
        src="$submodule_path"; kind="submodule"
    fi
    if [[ ! -e "$src/.git" ]]; then
        printf "  %-12s @ <uninitialized: %s>  (%s)\n" "$label" "$src" "$kind"
        return
    fi
    local sha branch
    sha=$(git -C "$src" rev-parse HEAD)
    branch=$(git -C "$src" rev-parse --abbrev-ref HEAD)
    printf "  %-12s @ %s  (%s, branch %s)\n" "$label" "$sha" "$kind" "$branch"
}

echo
echo "================================================================"
echo "Testing matrix"
echo "================================================================"
printf "  %-12s @ %s  (branch %s)\n" "turbo-stack" \
    "$(git -C "$TURBO_STACK_ROOT" rev-parse HEAD)" \
    "$(git -C "$TURBO_STACK_ROOT" rev-parse --abbrev-ref HEAD)"
_print_source "MOM6" "${MOM6_ROOT:-}" "$TURBO_STACK_ROOT/submodules/MOM6"
_print_source "TIM"  "${TIM_ROOT:-}"  "$TURBO_STACK_ROOT/submodules/infra/TIM"
_print_source "FMS"  "${FMS_ROOT:-}"  "$TURBO_STACK_ROOT/submodules/infra/FMS2"
echo "================================================================"

# Guard: a component sourced from its submodule (no <NAME>_ROOT override)
# requires that submodule to be initialized -- this script deliberately does not
# touch $TURBO_STACK_ROOT, so fail early with a clear remedy rather than deep
# inside a cmake configure.
_require_submodule() {
    local label="$1" override_root="$2" submodule_path="$3" root_var="$4"
    [[ -n "$override_root" ]] && return 0   # overridden -- submodule not needed
    if [[ ! -f "$submodule_path/CMakeLists.txt" ]]; then
        echo "Error: $label submodule at '$submodule_path' is not initialized." >&2
        echo "       Initialize it first (this script will not modify \$TURBO_STACK_ROOT):" >&2
        echo "         git -C \"\$TURBO_STACK_ROOT\" submodule update --init --recursive" >&2
        echo "       Or test an out-of-tree source: set fetch_$label=true, or export $root_var=/path/to/$label" >&2
        exit 1
    fi
}
_require_submodule "MOM6" "${MOM6_ROOT:-}" "$TURBO_STACK_ROOT/submodules/MOM6"       "MOM6_ROOT"
_require_submodule "TIM"  "${TIM_ROOT:-}"  "$TURBO_STACK_ROOT/submodules/infra/TIM"  "TIM_ROOT"
_require_submodule "FMS"  "${FMS_ROOT:-}"  "$TURBO_STACK_ROOT/submodules/infra/FMS2" "FMS_ROOT"

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
