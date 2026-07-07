#!/bin/bash
# scripts/lib/build_dep.sh
#
# SOURCED library.  Defines a `build_dep` function that builds and installs
# one cmake-based dependency, resolving its source from $<NAME>_ROOT or the
# in-tree submodule, with a sentinel that skips rebuilds when nothing changed.
#
# Usage (sourced once, called per dep):
#
#   source scripts/lib/build_dep.sh
#
#   build_dep <name>
#       --build-dir DIR
#       --install-prefix DIR
#       [--rebuild]
#       [--parallel N | -j N]
#       -- [cmake args...]
#
# Parallel jobs:
#   - With --parallel N (or -j N): pass --parallel N to `cmake --build`.
#   - Without: don't pass --parallel; cmake reads $CMAKE_BUILD_PARALLEL_LEVEL
#     as its own native default.  Orchestrators that want to set parallelism
#     once for the whole pipeline should export CMAKE_BUILD_PARALLEL_LEVEL.
#
# Source resolution (first match wins):
#   1. $<NAME>_ROOT env var   set externally (export in your shell to point at
#                             a local dev tree, e.g. a fork or PR branch you
#                             cloned yourself)
#   2. Submodule fallback     per-name table inside this script
#
# Valid <name> values: fms, pfunit, amrex, tim.
#
# Required environment:
#   TURBO_STACK_ROOT  Path to your turbo-stack repository clone (used by the
#                     submodule fallback; not required when $<NAME>_ROOT is set).
#
# Side effects on success:
#   - Appends $install_prefix to CMAKE_PREFIX_PATH (with dedup guard).
#   - For name=pfunit: exports PFUNIT_DIR pointing at the versioned cmake dir.

# Helper: expose a dep's install prefix to find_package(...) for downstream
# cmake invocations.  Called by build_dep both on the rebuild path and on the
# already-installed-skip path so an incremental run still sees the install.
_build_dep_expose_install() {
    local _name=$1
    local _install_prefix=$2
    case ":${CMAKE_PREFIX_PATH:-}:" in
        *:"$_install_prefix":*) ;;
        *) export CMAKE_PREFIX_PATH="$_install_prefix${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}" ;;
    esac

    # pFUnit installs into $_install_prefix/PFUNIT-X.Y/ -- a versioned subdir
    # that find_package(PFUNIT) does not auto-walk via CMAKE_PREFIX_PATH alone.
    if [[ "$_name" == "pfunit" ]]; then
        # Glob + `-d` test rather than `ls ... | head`: a pipeline whose `ls`
        # matches nothing exits non-zero and, under `set -eo pipefail`, would
        # abort the whole build right after a successful install. This loop is
        # pipefail-safe and silently no-ops when the versioned dir is absent.
        local _pfunit_cmake_dir
        for _pfunit_cmake_dir in "$_install_prefix"/PFUNIT-*/cmake; do
            if [[ -d "$_pfunit_cmake_dir" ]]; then
                export PFUNIT_DIR="$_pfunit_cmake_dir"
                break
            fi
        done
    fi
}

build_dep() {
    # --- Parse arguments ------------------------------------------------
    local _name=""
    local _build_dir=""
    local _install_prefix=""
    local _rebuild=false
    local _parallel=""
    local _cmake_args=()

    if [[ $# -eq 0 ]]; then
        echo "Error: build_dep requires a dep name as the first argument" >&2
        return 1
    fi
    _name="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --build-dir)      _build_dir="$2"; shift 2 ;;
            --install-prefix) _install_prefix="$2"; shift 2 ;;
            --rebuild)        _rebuild=true; shift ;;
            --parallel|-j)    _parallel="$2"; shift 2 ;;
            --)               shift; _cmake_args=("$@"); break ;;
            *)
                echo "Error: unknown option '$1' to build_dep" >&2
                return 1
                ;;
        esac
    done

    # --- Validate -------------------------------------------------------
    if [[ -z "$_build_dir" ]]; then
        echo "Error: build_dep $_name: --build-dir is required" >&2
        return 1
    fi
    if [[ -z "$_install_prefix" ]]; then
        echo "Error: build_dep $_name: --install-prefix is required" >&2
        return 1
    fi
    # Map <name> to the conventional $<NAME>_ROOT env var name.
    local _root_var=""
    case "$_name" in
        fms)    _root_var="FMS_ROOT" ;;
        pfunit) _root_var="PFUNIT_ROOT" ;;
        amrex)  _root_var="AMREX_ROOT" ;;
        tim)    _root_var="TIM_ROOT" ;;
        *)
            echo "Error: build_dep: unknown dep '$_name' (valid: fms, pfunit, amrex, tim)" >&2
            return 1
            ;;
    esac

    # Submodule fallback path for this dep (used when $<NAME>_ROOT is unset).
    local _submodule_path=""
    case "$_name" in
        fms)    _submodule_path="$TURBO_STACK_ROOT/submodules/infra/FMS2" ;;
        pfunit) _submodule_path="$TURBO_STACK_ROOT/submodules/pFUnit" ;;
        amrex)  _submodule_path="$TURBO_STACK_ROOT/submodules/amrex" ;;
        tim)    _submodule_path="$TURBO_STACK_ROOT/submodules/infra/TIM" ;;
    esac

    # --- Resolve source -------------------------------------------------
    local _resolved=""
    if [[ -n "${!_root_var:-}" ]]; then
        _resolved="${!_root_var}"
        echo "[build_dep] $_name: source = $_resolved (from \$$_root_var)"
    else
        _resolved="$_submodule_path"
        echo "[build_dep] $_name: source = $_resolved (submodule fallback)"
    fi

    if [[ ! -d "$_resolved" ]]; then
        echo "Error: build_dep $_name: resolved source '$_resolved' is not a directory" >&2
        return 1
    fi

    # --- Compute sentinel inputs ----------------------------------------
    # Source SHA (best-effort -- not all sources are git checkouts).
    local _sha=""
    if [[ -d "$_resolved/.git" || -f "$_resolved/.git" ]]; then
        _sha=$(git -C "$_resolved" rev-parse HEAD 2>/dev/null || echo "")
    fi

    # Working-tree fingerprint.  The HEAD SHA alone misses *uncommitted* edits,
    # so the documented "export <NAME>_ROOT to a local dev tree and iterate"
    # workflow would be silently skipped -- HEAD never moves while you edit, so
    # a stale install looks current.  When the tree is dirty, fold a hash of the
    # uncommitted changes (tracked `diff HEAD` plus the porcelain status, which
    # also captures added/untracked paths) into the fingerprint: an edit forces
    # a rebuild, an unchanged rerun still skips.
    local _tree="$_sha"
    if [[ -n "$_sha" ]]; then
        local _dirty
        _dirty=$(git -C "$_resolved" status --porcelain 2>/dev/null || echo "")
        if [[ -n "$_dirty" ]]; then
            local _diff_hash
            _diff_hash=$( { git -C "$_resolved" diff HEAD 2>/dev/null; printf '%s\n' "$_dirty"; } \
                | sha256sum | cut -d' ' -f1)
            _tree="${_sha}-dirty-${_diff_hash:0:16}"
        fi
    fi

    local _src_abs
    _src_abs=$(cd "$_resolved" && pwd)

    # cmake-args hash: sort first so flag order doesn't matter, then sha256.
    local _cmake_args_hash
    if [[ ${#_cmake_args[@]} -eq 0 ]]; then
        _cmake_args_hash=$(echo -n "" | sha256sum | cut -d' ' -f1)
    else
        _cmake_args_hash=$(printf '%s\n' "${_cmake_args[@]}" | LC_ALL=C sort | sha256sum | cut -d' ' -f1)
    fi

    local _sentinel="$_build_dir/.installed"

    # --- Decide whether to skip, rebuild, or fresh-build ----------------
    if [[ "$_rebuild" == true ]]; then
        echo "[build_dep] $_name force-rebuild requested"
        rm -rf "$_build_dir"
    elif [[ -f "$_sentinel" ]]; then
        local _saved_sha="" _saved_tree="" _saved_src="" _saved_prefix="" _saved_hash=""
        local _k _v
        while IFS='=' read -r _k _v; do
            case "$_k" in
                sha)             _saved_sha="$_v" ;;
                tree)            _saved_tree="$_v" ;;
                source)          _saved_src="$_v" ;;
                install_prefix)  _saved_prefix="$_v" ;;
                cmake_args_hash) _saved_hash="$_v" ;;
            esac
        done < "$_sentinel"

        if [[ "$_saved_sha" == "$_sha" \
           && "$_saved_tree" == "$_tree" \
           && "$_saved_src" == "$_src_abs" \
           && "$_saved_prefix" == "$_install_prefix" \
           && "$_saved_hash" == "$_cmake_args_hash" ]]; then
            echo "[build_dep] $_name @ ${_sha:0:8} already installed -- skipping"
            _build_dep_expose_install "$_name" "$_install_prefix"
            return 0
        fi

        # A pure *source* change (new commit or uncommitted edits) with the same
        # source path, cmake args, and install prefix is rebuilt incrementally:
        # reconfigure is a near-no-op and `cmake --build` recompiles only what
        # changed.  Only wipe the build dir for a change CMake cannot absorb in
        # place -- a different source directory, cmake args, or install prefix
        # (where a stale cache would otherwise linger).  --rebuild forces a wipe.
        if [[ "$_saved_src" == "$_src_abs" \
           && "$_saved_prefix" == "$_install_prefix" \
           && "$_saved_hash" == "$_cmake_args_hash" ]]; then
            if [[ "$_saved_sha" != "$_sha" ]]; then
                echo "[build_dep] $_name source changed (${_saved_sha:0:8} -> ${_sha:0:8}) -- incremental rebuild"
            else
                echo "[build_dep] $_name has uncommitted changes since last build -- incremental rebuild"
            fi
        else
            if [[ "$_saved_src" != "$_src_abs" ]]; then
                echo "[build_dep] $_name source path changed -- clean rebuild"
            else
                echo "[build_dep] $_name config changed (cmake args or install prefix) -- clean rebuild"
            fi
            rm -rf "$_build_dir"
        fi
    fi

    # --- Configure + build + install ------------------------------------
    echo "[build_dep] $_name: configuring (build dir: $_build_dir)"
    cmake -S "$_resolved" -B "$_build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$_install_prefix" \
        "${_cmake_args[@]}" \
        || return 1

    # Pass --parallel to cmake only when the caller explicitly set it.
    # Otherwise cmake reads $CMAKE_BUILD_PARALLEL_LEVEL as its own default.
    local _cmake_build_args=()
    [[ -n "$_parallel" ]] && _cmake_build_args=(--parallel "$_parallel")

    if [[ -n "$_parallel" ]]; then
        echo "[build_dep] $_name: building + installing ($_parallel parallel jobs)"
    else
        echo "[build_dep] $_name: building + installing (parallelism from CMAKE_BUILD_PARALLEL_LEVEL=${CMAKE_BUILD_PARALLEL_LEVEL:-cmake default})"
    fi
    cmake --build "$_build_dir" "${_cmake_build_args[@]}" --target install || return 1

    # --- Write sentinel atomically --------------------------------------
    {
        echo "sha=$_sha"
        echo "tree=$_tree"
        echo "source=$_src_abs"
        echo "install_prefix=$_install_prefix"
        echo "cmake_args_hash=$_cmake_args_hash"
    } > "$_sentinel.tmp" && mv "$_sentinel.tmp" "$_sentinel"

    # --- Side effects: expose installs to find_package ------------------
    _build_dep_expose_install "$_name" "$_install_prefix"
}
