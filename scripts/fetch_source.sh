#!/bin/bash
# scripts/fetch_source.sh
#
# SOURCED library.  Defines a `fetch_source` function that clones a git
# repository (or fetches + hard-resets an existing checkout) into a given
# destination and exports the conventional <NAME>_ROOT env var.
#
# Intended for source-only-consumed deps (e.g. MOM6, MARBL) that turbo-stack's
# own CMakeLists.txt reads via <NAME>_ROOT but does not build separately.
# Buildable deps (FMS, pFUnit, AMReX, TIM) should use `build_dep --clone`
# from scripts/build_dep.sh instead, which handles cloning + building in one
# call.
#
# Usage (sourced once, called per repo):
#
#   source scripts/fetch_source.sh
#
#   fetch_source --name NAME --url URL --branch REF --dest DIR [--force]
#
# Options:
#   --name NAME    Short label; the function exports <NAME_UPPER>_ROOT=$DEST.
#                  E.g. --name MOM6 exports MOM6_ROOT.
#   --url URL      Git URL.  Required (no default).  See rationale below.
#   --branch REF   Branch, tag, or commit to check out.  Required.
#   --dest DIR     Where to clone.  Required.
#   --force        rm -rf $dest first, then re-clone fresh.
#
# Behavior:
#   - If $dest/.git exists: git fetch + checkout -B branch origin/branch +
#     reset --hard + recursive submodule update.  Idempotent on rerun.
#   - Else: git clone --branch ... --recurse-submodules.
#   - On success: exports <NAME_UPPER>_ROOT="$dest".
#
# Why --url is required (no default): parsing .gitmodules would yield the
# upstream URL, but this helper is most often used to point at TURBO-ESM forks
# or PR branches.  A hardcoded name-to-URL map would duplicate .gitmodules and
# rot when forks move.  Requiring explicit --url keeps callers self-documenting.

fetch_source() {
    local _name=""
    local _url=""
    local _branch=""
    local _dest=""
    local _force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)    _name="$2"; shift 2 ;;
            --url)     _url="$2"; shift 2 ;;
            --branch)  _branch="$2"; shift 2 ;;
            --dest)    _dest="$2"; shift 2 ;;
            --force)   _force=true; shift ;;
            *)
                echo "Error: unknown option '$1' to fetch_source" >&2
                return 1
                ;;
        esac
    done

    if [[ -z "$_name" || -z "$_url" || -z "$_branch" || -z "$_dest" ]]; then
        echo "Error: fetch_source requires --name, --url, --branch, and --dest" >&2
        return 1
    fi

    if [[ "$_force" == true && -d "$_dest" ]]; then
        echo "[fetch_source] $_name: --force, removing existing $_dest"
        rm -rf "$_dest"
    fi

    mkdir -p "$(dirname "$_dest")"

    # `git clone --branch` and `origin/$ref` only accept branch/tag refs.
    # Detect SHA-shaped refs (7–40 hex chars) and take the detached-checkout
    # path so a commit SHA can be used in place of a branch name.
    local _ref_is_sha=false
    if [[ "$_branch" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
        _ref_is_sha=true
    fi
    if [[ -d "$_dest/.git" ]]; then
        echo "[fetch_source] $_name: $_dest exists -- fetching to $_branch"
        if [[ "$_ref_is_sha" == true ]]; then
            git -C "$_dest" fetch origin || return 1
            git -C "$_dest" checkout --detach "$_branch" || return 1
        else
            git -C "$_dest" fetch origin "$_branch" || return 1
            git -C "$_dest" checkout -B "$_branch" "origin/$_branch" || return 1
            git -C "$_dest" reset --hard "origin/$_branch" || return 1
        fi
        git -C "$_dest" submodule update --init --recursive --force || return 1
    else
        echo "[fetch_source] $_name: cloning $_url ($_branch) into $_dest"
        if [[ "$_ref_is_sha" == true ]]; then
            git clone --recurse-submodules -- "$_url" "$_dest" || return 1
            git -C "$_dest" checkout --detach "$_branch" || return 1
            git -C "$_dest" submodule update --init --recursive --force || return 1
        else
            git clone --branch "$_branch" --recurse-submodules -- "$_url" "$_dest" || return 1
        fi
    fi

    # Export <NAME_UPPER>_ROOT.
    local _root_var
    _root_var="$(echo "$_name" | tr '[:lower:]' '[:upper:]')_ROOT"
    export "$_root_var=$_dest"
}
