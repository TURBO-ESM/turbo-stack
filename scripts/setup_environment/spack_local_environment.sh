#!/bin/bash
# scripts/setup_environment/spack_local_environment.sh
#
# SOURCED, not executed.  Sets up the Spack environment so that subsequent
# `cmake` / `ctest` / `find_package(...)` calls find FMS, pFUnit, NetCDF, MPI,
# and the rest of turbo-stack's dependencies.
#
# Pairs with scripts/build_turbo_stack.sh, which assumes the environment has
# already been prepared by this script (or an equivalent module/from-source
# flavor).  See scripts/README.md for the contract.
#
# Usage:
#   source scripts/setup_environment/spack_local_environment.sh [options]
#
# Required environment variables:
#   TURBO_STACK_ROOT    Path to your turbo-stack repository clone
#   SPACK_ROOT          Path to your Spack installation
#
# Options:
#   --create-if-missing  Create the Spack env if it does not exist (default)
#   --no-create          Do not create the Spack env if missing; fail instead
#   --recreate           Delete and recreate the Spack env from scratch
#   --env-name NAME      Spack env name (default: turbo_stack)

_create_if_missing=true
_recreate=false
_env_name="turbo_stack"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --create-if-missing)  _create_if_missing=true;  shift ;;
        --no-create)          _create_if_missing=false; shift ;;
        --recreate)           _recreate=true;           shift ;;
        --env-name)           _env_name="$2";           shift 2 ;;
        *)
            echo "Error: unknown option '$1' to spack_local_environment.sh" >&2
            return 1 2>/dev/null || exit 1
            ;;
    esac
done

# --- Validate required environment ---------------------------------------
if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
    echo "Error: TURBO_STACK_ROOT is not set." >&2
    return 1 2>/dev/null || exit 1
fi
if [[ -z "${SPACK_ROOT:-}" ]]; then
    echo "Error: SPACK_ROOT is not set." >&2
    return 1 2>/dev/null || exit 1
fi
if [[ ! -f "$SPACK_ROOT/share/spack/setup-env.sh" ]]; then
    echo "Error: SPACK_ROOT ($SPACK_ROOT) is not a valid Spack installation." >&2
    return 1 2>/dev/null || exit 1
fi

# --- Make `spack` available in this shell --------------------------------
# shellcheck source=/dev/null
source "$SPACK_ROOT/share/spack/setup-env.sh"

# --- Optionally tear down the env ----------------------------------------
if [[ "$_recreate" == true ]]; then
    if spack env list | grep -Fqw "$_env_name"; then
        echo "Removing Spack environment '$_env_name' ..."
        if ! spack env rm -y "$_env_name"; then
            echo "Error: failed to remove spack env '$_env_name'" >&2
            return 1 2>/dev/null || exit 1
        fi
    fi
fi

# --- Optionally (re)create the env ---------------------------------------
if [[ "$_recreate" == true || "$_create_if_missing" == true ]]; then
    if ! spack env list | grep -Fqw "$_env_name"; then
        if ! bash "$TURBO_STACK_ROOT/spack/create_spack_environment.sh" "$_env_name"; then
            echo "Error: failed to create spack env '$_env_name'" >&2
            return 1 2>/dev/null || exit 1
        fi
    fi
fi

# --- Activate -------------------------------------------------------------
if ! spack env activate "$_env_name"; then
    echo "Error: 'spack env activate $_env_name' failed (env may not exist; pass --create-if-missing)" >&2
    return 1 2>/dev/null || exit 1
fi

unset _create_if_missing _recreate _env_name
