#!/usr/bin/env bash
# scripts/lib/common.sh
#
# SOURCED shared library for turbo-stack's build/test orchestration.  Holds the
# machine-INDEPENDENT primitives shared by the end-to-end test drivers
# (test_turbo_stack_locally.sh, test_turbo_stack_on_derecho.sh) and
# the thinner entry points (build_turbo_stack.sh, build_local_with_spack_env.sh,
# build_on_derecho.sh).  Each driver supplies only its machine-specific Stage-1
# toolchain step (spack vs Lmod modules); everything here is common.
#
# The dependency model these functions implement is documented in
# docs/dependency_tiers_prompt.md (the build-policy contract) and the pipeline in
# docs/build_test_orchestration_prompt.md.
#
# Source AFTER `set -euo pipefail` in the caller; every function is written to be
# safe under nounset/errexit.  Sourcing has NO side effects beyond defining
# functions -- in particular it does NOT load modules or build anything (that is
# the whole point of keeping the toolchain out of "setup" and dep builds explicit).
#
# Two patterns compose these functions:
#   * single-backend builder (build_local_with_spack_env.sh / build_on_derecho.sh):
#       turbo_resolve_stack_root
#       turbo_require_submodule ...                            # guard the deps it builds
#       <source the machine's Stage-1 toolchain env script>   # builds nothing
#       turbo_build_fms "$b" "$p"  (and/or pfunit/amrex/tim)   # Stage 1: build deps (Tier 1.5 + Tier 2)
#       build_turbo_stack.sh --infra X                         # Stage 2: build turbo-stack (Tier 3; defaults MOM6_ROOT)
#   * end-to-end test driver (test_turbo_stack_locally.sh / _on_derecho.sh):
#       turbo_resolve_stack_root
#       TURBO_JOBS=<default>; turbo_parse_driver_args "$@"
#       turbo_run_test_driver <builder>                        # whole driver body (both backends)

# Guard against double-sourcing (the wrappers may be reached via several paths).
[[ -n "${_TURBO_COMMON_SH:-}" ]] && return 0
_TURBO_COMMON_SH=1

# ── Usage / --help ───────────────────────────────────────────────────────────
# Print a script's own leading comment block as its usage text: skip the
# shebang, then echo the contiguous "#" header lines (leading "# " stripped),
# stopping at the first non-comment line.  Every user-facing script keeps its
# usage in that header, so --help stays in sync from one source of truth.
turbo_print_header_usage() {
    local file="$1" line stripped shebang_seen=false
    [[ -r "$file" ]] || { echo "usage: (no header found for '$file')"; return 0; }
    while IFS= read -r line; do
        if [[ "$shebang_seen" == false && "$line" == '#!'* ]]; then
            shebang_seen=true
            continue
        fi
        [[ "$line" == '#'* ]] || break
        stripped="${line#\#}"          # drop leading '#'
        printf '%s\n' "${stripped# }"  # drop one following space, keep indent
    done < "$file"
}

# ── Root resolution ──────────────────────────────────────────────────────────
# Resolve, validate, export, and announce TURBO_STACK_ROOT.  common.sh always
# lives at <root>/scripts/lib/common.sh, so its own path is the most reliable
# anchor -- it is the real file even in a PBS spool run (only the submitted
# driver script is copied to the spool, not the libraries it sources).
#
# turbo-stack is a top-level orchestrator: you build the checkout you run from,
# so there is no "root override" -- the script's own location always wins.
#   1. This script's own checkout wins.  A stale exported TURBO_STACK_ROOT that
#      DISAGREES with this checkout is a hard error (unset it), so it can never
#      silently steer the build onto another copy -- the footgun reviewers
#      flagged.  TURBO_STACK_ROOT is never USED to select the root; it is only
#      read to catch that mismatch.
#   2. Fallbacks, only when the script cannot locate itself (e.g. an unusual PBS
#      spool): PBS_O_WORKDIR, then the qsub'd script's directory.
#
# To point turbo-stack at a local dev tree of a co-developed *dependency*, use
# the submodule overrides (MOM6_ROOT / FMS_ROOT / TIM_ROOT).
turbo_resolve_stack_root() {
    local marker="scripts/lib/common.sh"
    local self=""
    self=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd) || self=""

    local resolved=""
    if [[ -n "$self" && -f "${self}/${marker}" ]]; then
        # Self-location wins.  Refuse to guess when an exported value disagrees.
        if [[ -n "${TURBO_STACK_ROOT:-}" ]]; then
            local exported_abs=""
            exported_abs=$(cd -P -- "$TURBO_STACK_ROOT" 2>/dev/null && pwd) || exported_abs="$TURBO_STACK_ROOT"
            if [[ "$exported_abs" != "$self" ]]; then
                echo "Error: exported TURBO_STACK_ROOT=$TURBO_STACK_ROOT disagrees with the" >&2
                echo "       checkout this script lives in ($self)." >&2
                echo "       TURBO_STACK_ROOT is not used to select the checkout; unset it and" >&2
                echo "       run the scripts from the copy you want to build." >&2
                return 1
            fi
        fi
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
        echo "  Run the script from inside a turbo-stack checkout." >&2
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
#
# _turbo_opt_needs_value guards value-taking options in a parse loop: it errors
# clearly when no argument follows, instead of consuming a nonexistent "$2" --
# which under the drivers' `set -u` aborts with a cryptic "unbound variable".
# Call it first in the case arm, before touching "$2":
#   --foo) _turbo_opt_needs_value "$1" "$#" || return 1; FOO="$2"; shift 2 ;;
_turbo_opt_needs_value() {
    if [[ "$2" -lt 2 ]]; then
        echo "Error: option '$1' requires a value" >&2
        return 1
    fi
}
turbo_parse_driver_args() {
    TURBO_ONLY=""
    TURBO_CLEAN=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --only)        _turbo_opt_needs_value "$1" "$#" || return 1; TURBO_ONLY="$2"; shift 2 ;;
            --parallel|-j) _turbo_opt_needs_value "$1" "$#" || return 1; TURBO_JOBS="$2"; shift 2 ;;
            --clean)       TURBO_CLEAN=true; shift ;;
            -h|--help)     turbo_print_header_usage "$0"; exit 0 ;;
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
            "" | / | . | .. | "$HOME")
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
    sha=$(git -C "$src" rev-parse HEAD 2>/dev/null) || sha="<unknown>"
    branch=$(git -C "$src" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch="<unknown>"
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

# ── Upstream-dep build wrappers (Stage 1; Tier 1.5 + Tier 2 canonical flags) ──
# Build an upstream dependency from its submodule (or its $<NAME>_ROOT
# override, resolved inside build_dep).  Args: <build_root> <install_prefix>.
# The per-dep cmake flags live here ONLY -- a flag change edits one place, not
# every machine env script.
_turbo_ensure_build_dep() {
    declare -F build_dep >/dev/null 2>&1 || source "$TURBO_STACK_ROOT/scripts/lib/build_dep.sh"
}

turbo_build_fms() {
    _turbo_ensure_build_dep
    build_dep fms --build-dir "$1/fms" --install-prefix "$2" \
        -- -D64BIT=ON -D32BIT=OFF -DFPIC=ON -DOPENMP=OFF
}

turbo_build_pfunit() {
    _turbo_ensure_build_dep
    # -DSKIP_OPENMP=YES works around a clang bug where find_package(PFUNIT)
    # fails to locate OpenMP (carried over from the legacy pfunit-utils build).
    build_dep pfunit --build-dir "$1/pfunit" --install-prefix "$2" \
        -- -DSKIP_MPI=NO -DSKIP_ESMF=YES -DSKIP_OPENMP=YES -DENABLE_TESTS=OFF
}

turbo_build_amrex() {
    _turbo_ensure_build_dep
    build_dep amrex --build-dir "$1/amrex" --install-prefix "$2" \
        -- -DAMReX_FORTRAN=ON -DAMReX_FORTRAN_INTERFACES=ON -DAMReX_MPI=ON \
           -DAMReX_TINY_PROFILE=ON
}

turbo_build_tim() {
    _turbo_ensure_build_dep
    # TIM_ENABLE_MOM_BRIDGE builds TIM::mom_bridge, the C++ side of the AMReX
    # kernels MOM6 calls from its `#ifdef _TIM` branches.  Unconditional: TIM
    # always *provides* the bridge, and MOM6's own CMake decides whether to link
    # it (only MOM6 knows whether its branch has the call sites).  Keying it on
    # the lane would also defeat build_dep's sentinel, which folds cmake args into
    # its hash -- TIM would rebuild on every backend switch.  See scripts/README.md.
    build_dep tim --build-dir "$1/tim" --install-prefix "$2" \
        -- -D64BIT=ON -D32BIT=OFF -DTIM_ENABLE_MOM_BRIDGE=ON
}

# ── Single-backend builder core (Stage 1 + Stage 2; machine-independent) ──────
# The shared body of every single-backend builder (build_local_with_spack_env.sh,
# build_local_with_system_toolchain.sh, build_on_derecho.sh).  Each flavor script
# supplies only the two machine-specific facts:
#   1. a turbo_flavor_setup_toolchain function that puts the Tier-1 toolchain on
#      PATH (sourced; builds nothing), and
#   2. the lowest dependency TIER it must build from submodule
#      (--build-deps-from-tier) -- i.e. the first tier the toolchain does NOT
#      hand you prebuilt.  See docs/dependency_tiers.png:
#        spack   provides Tier 1 + 1.5 (cmake/MPI/NetCDF + pFUnit/AMReX) -> build from Tier 2
#        modules provides Tier 1 only                                    -> build from Tier 1.5
#        on-PATH provides Tier 1 only (user sets it up)                  -> build from Tier 1.5
# Tier 2 (FMS/TIM) is always built from submodule (no flavor packages it); Tier 3
# (turbo-stack/MOM6/MARBL) is built in Stage 2 by build_turbo_stack.sh.

# Parse the flags common to every single-backend builder into TURBO_B_* globals.
# --help/errors exit the calling builder (this runs during its execution).
turbo_parse_builder_args() {
    TURBO_B_DEBUG=false; TURBO_B_CLEAN=false; TURBO_B_NINJA=false
    TURBO_B_INFRA="TIM"; TURBO_B_TESTS=false; TURBO_B_BUILD_DIR=""; TURBO_B_PARALLEL=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug)       TURBO_B_DEBUG=true; shift ;;
            --clean)       TURBO_B_CLEAN=true; shift ;;
            --ninja)       TURBO_B_NINJA=true; shift ;;
            --infra)       _turbo_opt_needs_value "$1" "$#" || exit 1; TURBO_B_INFRA="$2"; shift 2 ;;
            --tests)       TURBO_B_TESTS=true; shift ;;
            --build_dir)   _turbo_opt_needs_value "$1" "$#" || exit 1; TURBO_B_BUILD_DIR="$2"; shift 2 ;;
            --parallel|-j) _turbo_opt_needs_value "$1" "$#" || exit 1; TURBO_B_PARALLEL="$2"; shift 2 ;;
            -h|--help)     turbo_print_header_usage "$0"; exit 0 ;;
            *) echo "Error: unknown option '$1' to $(basename -- "$0")" >&2; exit 1 ;;
        esac
    done
    if [[ "$TURBO_B_INFRA" != "FMS2" && "$TURBO_B_INFRA" != "TIM" ]]; then
        echo "Error: --infra must be FMS2 or TIM (got '$TURBO_B_INFRA')" >&2; exit 1
    fi
}

# The buildable submodule tiers are 1.5 and 2; a flavor builds "from" the lowest
# one its toolchain didn't supply.  Only "from 1.5" includes Tier 1.5; Tier 2 is
# always built, so it needs no predicate.
_turbo_builds_tier_1_5() { [[ "$1" == "1.5" ]]; }

# Guard the submodules this build consumes -- the always-inline Tier-3 sources
# (MOM6/MARBL) plus the members of each tier being built from submodule.  Each
# guard is skipped when the dep's *_ROOT override is set.  Reads TURBO_B_*.
turbo_guard_builder_submodules() {
    local from_tier="$1"
    turbo_require_submodule submodules/MOM6  MOM6  MOM6_ROOT
    turbo_require_submodule submodules/MARBL MARBL
    if _turbo_builds_tier_1_5 "$from_tier"; then
        [[ "$TURBO_B_TESTS" == true ]] && turbo_require_submodule submodules/pFUnit pFUnit PFUNIT_ROOT
        [[ "$TURBO_B_INFRA" == "TIM" ]] && turbo_require_submodule submodules/amrex AMReX AMREX_ROOT
    fi
    if [[ "$TURBO_B_INFRA" == "TIM" ]]; then
        turbo_require_submodule submodules/infra/TIM TIM TIM_ROOT
    else
        turbo_require_submodule submodules/infra/FMS2 FMS FMS_ROOT
    fi
}

# Build, from <deps_build_root>/{build,install}, the submodule dep tiers this
# flavor doesn't get prebuilt.  Tier 1.5 = pFUnit (only with --tests) + AMReX
# (only for TIM); Tier 2 = the selected backend (FMS for FMS2, TIM for TIM).
turbo_build_builder_dep_tiers() {
    local deps_build_root="$1" from_tier="$2"
    local b="$deps_build_root/build" p="$deps_build_root/install"
    if _turbo_builds_tier_1_5 "$from_tier"; then
        [[ "$TURBO_B_TESTS" == true ]] && turbo_build_pfunit "$b" "$p"
        [[ "$TURBO_B_INFRA" == "TIM" ]] && turbo_build_amrex "$b" "$p"
    fi
    if [[ "$TURBO_B_INFRA" == "TIM" ]]; then
        turbo_build_tim "$b" "$p"
    else
        turbo_build_fms "$b" "$p"
    fi
}

# The full single-backend builder body.  A flavor script defines
# turbo_flavor_setup_toolchain, then calls:
#   turbo_run_backend_builder --build-deps-from-tier {1.5|2} "$@"
# ("$@" being the user's CLI args).  Runs Stage 1 (toolchain + submodule dep
# tiers) then Stage 2 (build_turbo_stack.sh).
turbo_run_backend_builder() {
    local from_tier="1.5"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --build-deps-from-tier) from_tier="$2"; shift 2 ;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    case "$from_tier" in
        1.5|2) ;;
        *) echo "Error: --build-deps-from-tier must be 1.5 or 2 (got '$from_tier')" >&2; return 1 ;;
    esac
    if ! declare -F turbo_flavor_setup_toolchain >/dev/null 2>&1; then
        echo "Error: builder must define turbo_flavor_setup_toolchain before calling turbo_run_backend_builder" >&2
        return 1
    fi

    turbo_parse_builder_args "$@"
    # Resolve TURBO_STACK_ROOT (self-locating; a mismatching exported value is a
    # hard error -- see turbo_resolve_stack_root).
    turbo_resolve_stack_root

    # Set CMAKE_BUILD_PARALLEL_LEVEL once -- cmake reads it natively, so every
    # `cmake --build` downstream (deps + turbo-stack) picks it up with no plumbing.
    [[ -n "$TURBO_B_PARALLEL" ]] && export CMAKE_BUILD_PARALLEL_LEVEL="$TURBO_B_PARALLEL"

    # Where the from-source upstream deps build + install: $build_dir/deps when
    # given, else $TURBO_STACK_ROOT/deps/default.
    local deps_build_root
    if [[ -n "$TURBO_B_BUILD_DIR" ]]; then
        deps_build_root="$TURBO_B_BUILD_DIR/deps"
    else
        deps_build_root="$TURBO_STACK_ROOT/deps/default"
    fi

    # --clean covers Stage-1 deps as well as the Stage-2 build: wipe the dep
    # builds/installs here, and forward --clean to build_turbo_stack.sh below.
    if [[ "$TURBO_B_CLEAN" == true ]]; then
        turbo_validate_clean_paths "$deps_build_root" || return 1
        echo "[--clean] removing upstream dep artifacts under $deps_build_root"
        rm -rf "$deps_build_root"
    fi

    turbo_guard_builder_submodules "$from_tier"

    # --- Stage 1 (env setup) · toolchain (flavor hook; sources a recipe) ------
    turbo_flavor_setup_toolchain

    # --- Stage 1 (env setup) · build the submodule dep tiers -----------------
    turbo_build_builder_dep_tiers "$deps_build_root" "$from_tier"

    # --- Stage 2 · build turbo-stack (Tier 3): configure + build + test ------
    local build_args=()
    [[ "$TURBO_B_DEBUG" == true ]] && build_args+=(--debug)
    [[ "$TURBO_B_CLEAN" == true ]] && build_args+=(--clean)
    [[ "$TURBO_B_NINJA" == true ]] && build_args+=(--ninja)
    [[ -n "$TURBO_B_INFRA" ]]      && build_args+=(--infra "$TURBO_B_INFRA")
    [[ "$TURBO_B_TESTS" == true ]] && build_args+=(--tests)
    [[ -n "$TURBO_B_BUILD_DIR" ]]  && build_args+=(--build_dir "$TURBO_B_BUILD_DIR")
    bash "$TURBO_STACK_ROOT/scripts/build_turbo_stack.sh" "${build_args[@]}"
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

# ── Source overrides ─────────────────────────────────────────────────────────
# To swap a component's source for the submodule, export $<NAME>_ROOT (pointing
# at a local clone) before running a driver; build_dep and turbo-stack's CMake
# pick it up. There is no built-in clone step -- clone the fork/branch yourself.

# ── Run the end-to-end test driver for one machine ───────────────────────────
# The full driver body shared by both end-to-end test drivers: derive the
# artifact layout from $TURBO_BUILD_SYSTEM_TEST_DIR, honor --clean, print the
# provenance matrix, then run the single-backend
# <builder> once per selected backend (TURBO_RUN_FMS2 / TURBO_RUN_TIM) in its own
# process under <test_dir>/turbo-stack-with-<backend>, and print a verdict.
# Returns non-zero if any selected backend failed.  The ONLY per-machine input is
# <builder>; the caller sets TURBO_JOBS and runs turbo_parse_driver_args first.
turbo_run_test_driver() {
    local builder="$1"
    : "${TURBO_BUILD_SYSTEM_TEST_DIR:=${TMPDIR:-/tmp}/turbo_build_system_test}"
    export TURBO_BUILD_SYSTEM_TEST_DIR
    local log_dir="$TURBO_BUILD_SYSTEM_TEST_DIR/logs"

    # --clean here wipes the whole artifact dir, which holds BOTH the Stage-1 dep
    # builds/installs (under each backend's deps/) and the Stage-2 turbo-stack
    # build.  That is the same thing --clean means in the single-backend
    # orchestrators (build_on_derecho.sh / build_local_with_spack_env.sh), which
    # remove their deps dir and pass --clean to build_turbo_stack.sh for the
    # turbo-stack build.  One definition of "clean" across every entry point:
    # Stage-1 deps + Stage-2 build.
    if [[ "${TURBO_CLEAN:-false}" == true ]]; then
        turbo_validate_clean_paths "$TURBO_BUILD_SYSTEM_TEST_DIR" "$TURBO_STACK_ROOT" || return 1
        # Never wipe the checkout: refuse if the artifact dir resolves to (or
        # contains) the repo root -- e.g. TURBO_BUILD_SYSTEM_TEST_DIR set to it.
        local _td _sr
        _td=$(cd -P -- "$TURBO_BUILD_SYSTEM_TEST_DIR" 2>/dev/null && pwd) || _td="$TURBO_BUILD_SYSTEM_TEST_DIR"
        _sr=$(cd -P -- "$TURBO_STACK_ROOT" 2>/dev/null && pwd) || _sr="$TURBO_STACK_ROOT"
        if [[ "$_td" == "$_sr" || "$_sr" == "$_td"/* ]]; then
            echo "Refusing --clean: TURBO_BUILD_SYSTEM_TEST_DIR ($_td) is or contains the repo root ($_sr)." >&2
            return 1
        fi
        echo "[--clean] removing all artifacts (deps + turbo-stack build) under $TURBO_BUILD_SYSTEM_TEST_DIR"
        rm -rf "$TURBO_BUILD_SYSTEM_TEST_DIR"
    fi
    mkdir -p "$log_dir"

    [[ -n "${TURBO_JOBS:-}" ]] && export CMAKE_BUILD_PARALLEL_LEVEL="$TURBO_JOBS"

    turbo_print_matrix                             # record what's being tested

    # Build + test each selected backend in its own process via the real builder.
    local fms2_rc=0 tim_rc=0
    if [[ "${TURBO_RUN_FMS2:-true}" == true ]]; then
        turbo_run_flavor "FMS2 build+test" "$log_dir/turbo-stack-with-FMS2.log" \
            bash "$builder" --infra FMS2 --build_dir "$TURBO_BUILD_SYSTEM_TEST_DIR/turbo-stack-with-FMS2" --tests
        fms2_rc=$TURBO_LAST_RC
    fi
    if [[ "${TURBO_RUN_TIM:-true}" == true ]]; then
        turbo_run_flavor "TIM build+test" "$log_dir/turbo-stack-with-TIM.log" \
            bash "$builder" --infra TIM --build_dir "$TURBO_BUILD_SYSTEM_TEST_DIR/turbo-stack-with-TIM" --tests
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
