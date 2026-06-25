#!/usr/bin/env bash
# scripts/lib/common.sh
#
# SOURCED shared library for turbo-stack's build/test orchestration.  Holds the
# machine-INDEPENDENT primitives shared by the end-to-end test drivers
# (test_turbo_stack_locally.sh, test_turbo_stack_on_derecho.sh) and
# the thinner entry points (build_turbo_stack.sh, build_local_with_spack_env.sh,
# build_on_derecho.sh).  Each driver supplies only its machine-specific Tier-1
# toolchain step (spack vs Lmod modules); everything here is common.
#
# The dependency model these functions implement is documented in
# docs/dependency_tiers_prompt.md (the build-policy contract) and the pipeline in
# docs/turbo_stack_pipeline_prompt.md.
#
# Source AFTER `set -euo pipefail` in the caller; every function is written to be
# safe under nounset/errexit.  Sourcing has NO side effects beyond defining
# functions -- in particular it does NOT load modules or build anything (that is
# the whole point of keeping Tier 1 out of "setup" and dep builds explicit).
#
# Two patterns compose these functions:
#   * single-backend builder (build_local_with_spack_env.sh / build_on_derecho.sh):
#       turbo_resolve_stack_root
#       turbo_require_submodule ...                            # guard the deps it builds
#       <source the machine's Tier-1 toolchain env script>     # builds nothing
#       turbo_build_fms "$b" "$p"  (and/or pfunit/amrex/tim)   # explicit Tier 2
#       build_turbo_stack.sh --infra X                         # Tier 3 (defaults MOM6_ROOT)
#   * end-to-end test driver (test_turbo_stack_locally.sh / _on_derecho.sh):
#       turbo_resolve_stack_root
#       TURBO_JOBS=<default>; turbo_parse_driver_args "$@"
#       turbo_run_test_driver <builder>                        # whole driver body (both backends)

# Guard against double-sourcing (the wrappers may be reached via several paths).
[[ -n "${_TURBO_COMMON_SH:-}" ]] && return 0
_TURBO_COMMON_SH=1

# ── Root resolution ──────────────────────────────────────────────────────────
# Resolve, validate, export, and announce TURBO_STACK_ROOT.  common.sh always
# lives at <root>/scripts/lib/common.sh, so its own path is the most reliable
# anchor -- it is the real file even in a PBS spool run (only the submitted
# driver script is copied to the spool, not the libraries it sources).  An
# exported TURBO_STACK_ROOT is honored as an explicit override but WARNS when it
# disagrees with this checkout -- the multi-copy footgun reviewers flagged.
turbo_resolve_stack_root() {
    local marker="scripts/lib/common.sh"
    local self=""
    self=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd) || self=""

    local resolved=""
    if [[ -n "${TURBO_STACK_ROOT:-}" && -f "${TURBO_STACK_ROOT}/${marker}" ]]; then
        resolved="$TURBO_STACK_ROOT"
        if [[ -n "$self" && -f "${self}/${marker}" && "$self" != "$resolved" ]]; then
            echo "[common] WARNING: exported TURBO_STACK_ROOT=$resolved differs from this" >&2
            echo "[common]          checkout ($self). Using the exported value -- unset" >&2
            echo "[common]          TURBO_STACK_ROOT to use the checkout you launched from." >&2
        fi
    elif [[ -n "$self" && -f "${self}/${marker}" ]]; then
        resolved="$self"
    elif [[ -n "${PBS_O_WORKDIR:-}" && -f "${PBS_O_WORKDIR}/${marker}" ]]; then
        resolved="$PBS_O_WORKDIR"
    elif [[ -n "${PBS_JOBID:-}" ]] && command -v qstat >/dev/null 2>&1; then
        # qsub'd from a directory other than the repo: reconstruct the submitted
        # script path (last token of Submit_arguments) and take its directory.
        local args script cand
        args=$(qstat -f "$PBS_JOBID" 2>/dev/null | sed -n 's/^[[:space:]]*Submit_arguments = //p')
        script=${args##* }
        if [[ -n "$script" && "$script" != "--" ]]; then
            [[ "$script" == /* ]] || script="${PBS_O_WORKDIR:-$PWD}/$script"
            cand=$(cd -P -- "$(dirname -- "$script")" 2>/dev/null && pwd) || cand=""
            [[ -n "$cand" && -f "${cand}/${marker}" ]] && resolved="$cand"
        fi
    fi

    if [[ -z "$resolved" ]]; then
        echo "Error: could not locate the turbo-stack root." >&2
        echo "  Run from inside a turbo-stack checkout, or set TURBO_STACK_ROOT=/path/to/turbo-stack." >&2
        return 1
    fi
    export TURBO_STACK_ROOT="$resolved"
    echo "[common] TURBO_STACK_ROOT = $TURBO_STACK_ROOT"
}

# ── Driver argument parsing ──────────────────────────────────────────────────
# Shared by the end-to-end test drivers.  Sets globals:
#   TURBO_ONLY      "" | FMS2 | TIM
#   TURBO_CLEAN     true | false
#   TURBO_JOBS      overwritten only if --parallel/-j is given (set a default
#                   before calling to control the no-flag value)
#   TURBO_RUN_FMS2  true | false   (derived from --only)
#   TURBO_RUN_TIM   true | false
turbo_parse_driver_args() {
    TURBO_ONLY=""
    TURBO_CLEAN=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --only)        TURBO_ONLY="$2"; shift 2 ;;
            --parallel|-j) TURBO_JOBS="$2"; shift 2 ;;
            --clean)       TURBO_CLEAN=true; shift ;;
            *) echo "Error: unknown option '$1'" >&2; return 1 ;;
        esac
    done
    if [[ -n "$TURBO_ONLY" && "$TURBO_ONLY" != "FMS2" && "$TURBO_ONLY" != "TIM" ]]; then
        echo "Error: --only must be FMS2 or TIM (got '$TURBO_ONLY')" >&2
        return 1
    fi
    TURBO_RUN_FMS2=true
    TURBO_RUN_TIM=true
    [[ "$TURBO_ONLY" == "FMS2" ]] && TURBO_RUN_TIM=false
    [[ "$TURBO_ONLY" == "TIM"  ]] && TURBO_RUN_FMS2=false
    return 0
}

# ── --clean safety guard ─────────────────────────────────────────────────────
# Refuse to rm -rf an obviously-too-broad path (empty, /, or $HOME) before a
# driver wipes its artifact directories.
turbo_validate_clean_paths() {
    local d
    for d in "$@"; do
        case "$d" in
            "" | / | "$HOME")
                echo "Refusing to operate on '$d': path is too broad." >&2
                return 1 ;;
        esac
    done
    return 0
}

# ── Testing matrix (reproducibility) ─────────────────────────────────────────
# Print the effective source (SHA + branch) of each hot-swappable component.
# Call BEFORE turbo_default_mom6_root so a set <NAME>_ROOT reflects a real user
# override, not the submodule default.
_turbo_print_source() {
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

turbo_print_matrix() {
    echo
    echo "================================================================"
    echo "Testing matrix"
    echo "================================================================"
    printf "  %-12s @ %s  (branch %s)\n" "turbo-stack" \
        "$(git -C "$TURBO_STACK_ROOT" rev-parse HEAD)" \
        "$(git -C "$TURBO_STACK_ROOT" rev-parse --abbrev-ref HEAD)"
    _turbo_print_source "MOM6" "${MOM6_ROOT:-}" "$TURBO_STACK_ROOT/submodules/MOM6"
    _turbo_print_source "TIM"  "${TIM_ROOT:-}"  "$TURBO_STACK_ROOT/submodules/infra/TIM"
    _turbo_print_source "FMS"  "${FMS_ROOT:-}"  "$TURBO_STACK_ROOT/submodules/infra/FMS2"
    echo "================================================================"
}

# ── Submodule guard ──────────────────────────────────────────────────────────
# Require an in-tree submodule to be initialized (this library never mutates
# $TURBO_STACK_ROOT).  Skips the check when the component is overridden via its
# <override_var>.  Fails early with the exact remedy instead of a deep CMake or
# build_dep failure.
turbo_require_submodule() {
    local rel="$1" label="${2:-$1}" override_var="${3:-}"
    [[ -n "$override_var" && -n "${!override_var:-}" ]] && return 0
    local path="$TURBO_STACK_ROOT/$rel"
    # `.git` (a gitlink file or dir) exists iff the submodule is initialized.
    # Don't key on CMakeLists.txt: some submodules (e.g. MARBL) don't ship one.
    if [[ ! -e "$path/.git" ]]; then
        echo "Error: $label submodule at '$path' is not initialized." >&2
        echo "       Initialize it first (this script will not modify \$TURBO_STACK_ROOT):" >&2
        echo "         git -C \"\$TURBO_STACK_ROOT\" submodule update --init --recursive" >&2
        [[ -n "$override_var" ]] && \
            echo "       Or test an out-of-tree source: export $override_var=/path/to/$label" >&2
        return 1
    fi
    return 0
}

# ── MOM6 source default ──────────────────────────────────────────────────────
# MOM6 is consumed as source by turbo-stack's CMake (read via MOM6_ROOT) and has
# NO build_dep fallback, unlike FMS/TIM.  Default it to the in-tree submodule
# when unset.  (FMS_ROOT/TIM_ROOT are intentionally left alone: build_dep falls
# back to their submodules on its own, and leaving them unset keeps the matrix's
# override/submodule labelling truthful.)
turbo_default_mom6_root() {
    if [[ -z "${MOM6_ROOT:-}" ]]; then
        export MOM6_ROOT="$TURBO_STACK_ROOT/submodules/MOM6"
        echo "[common] MOM6_ROOT unset -> defaulting to submodule: $MOM6_ROOT"
    fi
}

# ── Tier-2 build wrappers (canonical flags — single source of truth) ─────────
# Build a convenience dependency from its submodule (or its $<NAME>_ROOT
# override, resolved inside build_dep).  Args: <build_root> <install_prefix>.
# The per-dep cmake flags live here ONLY -- a flag change edits one place, not
# every machine env script.
_turbo_ensure_build_dep() {
    declare -F build_dep >/dev/null 2>&1 || source "$TURBO_STACK_ROOT/scripts/lib/build_dep.sh"
}
_turbo_ensure_fetch_source() {
    declare -F fetch_source >/dev/null 2>&1 || source "$TURBO_STACK_ROOT/scripts/lib/fetch_source.sh"
}

turbo_build_fms() {
    _turbo_ensure_build_dep
    build_dep fms --build-dir "$1/fms" --install-prefix "$2" \
        -- -D64BIT=ON -D32BIT=OFF -DFPIC=ON -DOPENMP=OFF
}

turbo_build_pfunit() {
    _turbo_ensure_build_dep
    build_dep pfunit --build-dir "$1/pfunit" --install-prefix "$2" \
        -- -DSKIP_MPI=NO -DSKIP_ESMF=YES -DENABLE_TESTS=OFF
}

turbo_build_amrex() {
    _turbo_ensure_build_dep
    build_dep amrex --build-dir "$1/amrex" --install-prefix "$2" \
        -- -DAMReX_FORTRAN=ON -DAMReX_FORTRAN_INTERFACES=ON -DAMReX_MPI=ON \
           -DAMReX_TINY_PROFILE=ON
}

turbo_build_tim() {
    _turbo_ensure_build_dep
    build_dep tim --build-dir "$1/tim" --install-prefix "$2" \
        -- -D64BIT=ON -D32BIT=OFF
}

# ── Run one labeled command, tee'd, capturing its rc ─────────────────────────
# Used by the end-to-end test drivers to invoke the real single-backend builder
# (build_local_with_spack_env.sh / build_on_derecho.sh) once per backend, so each
# backend is built + tested from scratch through the same code path a user runs.
# The exit code is stashed in TURBO_LAST_RC (NOT returned) so the caller's
# `set -e` can't abort between backends:
#   turbo_run_flavor "FMS2" "$log" bash "$builder" --infra FMS2 --build_dir "$d"
#   fms_rc=$TURBO_LAST_RC
turbo_run_flavor() {
    local label="$1" log_file="$2"; shift 2
    echo
    echo "=== ${label}: started $(date) ==="
    echo "===   \$ $*"
    echo "===   log: $log_file"
    # Capture the leftmost pipe stage (the command), not tee.  Toggle errexit
    # locally and restore it so a failure becomes a recorded rc rather than an
    # abort, regardless of the caller's set -e state.
    local _errexit=0; case $- in *e*) _errexit=1 ;; esac
    set +e
    "$@" 2>&1 | tee "$log_file"
    TURBO_LAST_RC=${PIPESTATUS[0]}
    [[ "$_errexit" == 1 ]] && set -e
    echo "=== ${label}: finished $(date) (exit $TURBO_LAST_RC) ==="
    return 0
}

# ── Verdict line ─────────────────────────────────────────────────────────────
turbo_verdict() {
    local label="$1" ran="$2" rc="$3"
    if [[ "$ran" != true ]]; then
        echo "  $label : SKIPPED"
    elif [[ "$rc" -eq 0 ]]; then
        echo "  $label : PASS"
    else
        echo "  $label : FAIL (exit $rc)"
    fi
}

# ── Opt-in source overrides (clone a branch instead of using the submodule) ──
# For each fetch_<NAME>=true, clone the configured branch into <override_dir> and
# export <NAME>_ROOT, so build_dep / turbo-stack's CMake use it instead of the
# submodule.  Off by default (all fetch_<NAME>=false -> submodules win).  URL and
# branch are overridable via <NAME>_REPO_URL / <NAME>_BRANCH.  Shared by both
# end-to-end test drivers.
turbo_fetch_overrides() {
    local override_dir="$1"
    : "${fetch_MOM6:=false}"; : "${fetch_TIM:=false}"; : "${fetch_FMS:=false}"
    [[ "$fetch_MOM6" == true || "$fetch_TIM" == true || "$fetch_FMS" == true ]] || return 0
    _turbo_ensure_fetch_source
    mkdir -p "$override_dir"
    [[ "$fetch_MOM6" == true ]] && fetch_source --name MOM6 \
        --url "${MOM6_REPO_URL:-https://github.com/TURBO-ESM/MOM6.git}" \
        --branch "${MOM6_BRANCH:-dev/turbo}" --dest "$override_dir/MOM6"
    [[ "$fetch_TIM" == true ]] && fetch_source --name TIM \
        --url "${TIM_REPO_URL:-https://github.com/TURBO-ESM/TIM.git}" \
        --branch "${TIM_BRANCH:-main}" --dest "$override_dir/TIM"
    [[ "$fetch_FMS" == true ]] && fetch_source --name FMS \
        --url "${FMS_REPO_URL:-https://github.com/TURBO-ESM/FMS.git}" \
        --branch "${FMS_BRANCH:-dev/turbo}" --dest "$override_dir/FMS"
    return 0
}

# ── Run the end-to-end test driver for one machine ───────────────────────────
# The full driver body shared by both end-to-end test drivers: derive the
# artifact layout from $TURBO_BUILD_SYSTEM_TEST_DIR, honor --clean, fetch any
# opt-in overrides, print the provenance matrix, then run the single-backend
# <builder> once per selected backend (TURBO_RUN_FMS2 / TURBO_RUN_TIM) in its own
# process under <test_dir>/turbo-stack-with-<backend>, and print a verdict.
# Returns non-zero if any selected backend failed.  The ONLY per-machine input is
# <builder>; the caller sets TURBO_JOBS and runs turbo_parse_driver_args first.
turbo_run_test_driver() {
    local builder="$1"
    : "${TURBO_BUILD_SYSTEM_TEST_DIR:=${TMPDIR:-/tmp}/turbo_build_system_test}"
    export TURBO_BUILD_SYSTEM_TEST_DIR
    local log_dir="$TURBO_BUILD_SYSTEM_TEST_DIR/logs"
    local override_dir="$TURBO_BUILD_SYSTEM_TEST_DIR/deps_that_override_submodules"

    if [[ "${TURBO_CLEAN:-false}" == true ]]; then
        turbo_validate_clean_paths "$TURBO_BUILD_SYSTEM_TEST_DIR" "$TURBO_STACK_ROOT" || return 1
        echo "[--clean] removing all artifacts under $TURBO_BUILD_SYSTEM_TEST_DIR"
        rm -rf "$TURBO_BUILD_SYSTEM_TEST_DIR"
    fi
    mkdir -p "$log_dir"

    turbo_fetch_overrides "$override_dir"          # opt-in; no-op unless fetch_*=true
    [[ -n "${TURBO_JOBS:-}" ]] && export CMAKE_BUILD_PARALLEL_LEVEL="$TURBO_JOBS"

    turbo_print_matrix                             # record what's being tested

    # Build + test each selected backend in its own process via the real builder.
    local fms2_rc=0 tim_rc=0
    if [[ "${TURBO_RUN_FMS2:-true}" == true ]]; then
        turbo_run_flavor "FMS2 build+test" "$log_dir/turbo-stack-with-FMS2.log" \
            bash "$builder" --infra FMS2 --build_dir "$TURBO_BUILD_SYSTEM_TEST_DIR/turbo-stack-with-FMS2"
        fms2_rc=$TURBO_LAST_RC
    fi
    if [[ "${TURBO_RUN_TIM:-true}" == true ]]; then
        turbo_run_flavor "TIM build+test" "$log_dir/turbo-stack-with-TIM.log" \
            bash "$builder" --infra TIM --build_dir "$TURBO_BUILD_SYSTEM_TEST_DIR/turbo-stack-with-TIM"
        tim_rc=$TURBO_LAST_RC
    fi

    echo
    echo "================================================================"
    echo "Build summary"
    echo "================================================================"
    turbo_verdict "turbo-stack with FMS2" "${TURBO_RUN_FMS2:-true}" "$fms2_rc"
    turbo_verdict "turbo-stack with TIM"  "${TURBO_RUN_TIM:-true}"  "$tim_rc"
    echo "================================================================"

    [[ "${TURBO_RUN_FMS2:-true}" == true && $fms2_rc -ne 0 ]] && return 1
    [[ "${TURBO_RUN_TIM:-true}"  == true && $tim_rc  -ne 0 ]] && return 1
    return 0
}
