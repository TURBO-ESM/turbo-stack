#!/bin/bash
# Usage: ./spack/create_spack_environment.sh [env-name] [spack-yaml]
#
# Arguments:
#   env-name   (optional) Name for the Spack environment. Defaults to 'turbo_stack'.
#   spack-yaml (optional) Path to the spack.yaml spec file.
#              Defaults to $TURBO_STACK_ROOT/spack/spack.yaml.
#              Requires TURBO_STACK_ROOT to be set when using the default.
#
# Required environment variables:
#   SPACK_ROOT        Path to your Spack repository clone (e.g. ~/spack).
#                     Clone it from https://github.com/spack/spack if you haven't already.
#
# Optional environment variables:
#   TURBO_STACK_ROOT  Path to the turbo-stack repository root. Required when
#                     using the default spack-yaml argument.
#
# Creates a named Spack environment, installs all packages, and prints
# the activation command. Does NOT activate — user must run the printed command.
#
# To add a new compiler environment:
#   1. Copy spack_gcc.yaml -> spack_<compiler>.yaml and adjust compiler/mpi entries
#   2. Run: ./spack/create_spack_environment.sh turbo-<compiler> spack/spack_<compiler>.yaml

set -e

# --- SPACK_ROOT (required, must come from environment) ---
if [[ -z "${SPACK_ROOT:-}" ]]; then
    echo "Error: SPACK_ROOT is not set." >&2
    echo "Set it to the root of your Spack repository clone (e.g. export SPACK_ROOT=~/spack)." >&2
    exit 1
fi
if [[ ! -f "$SPACK_ROOT/share/spack/setup-env.sh" ]]; then
    echo "Error: SPACK_ROOT ($SPACK_ROOT) does not point to a valid Spack installation." >&2
    echo "Expected file not found: $SPACK_ROOT/share/spack/setup-env.sh" >&2
    echo "Clone Spack from https://github.com/spack/spack and set SPACK_ROOT accordingly." >&2
    exit 1
fi

# --- Environment name (optional, default: turbo_stack) ---
spack_environment_name=${1:-turbo_stack}

# --- Spack yaml file (optional, default: $TURBO_STACK_ROOT/spack/spack.yaml) ---
if [[ -n "${2:-}" ]]; then
    spack_environment_yaml_file="$2"
else
    if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
        echo "Error: TURBO_STACK_ROOT is not set." >&2
        echo "Set it to the root of your turbo-stack clone, or pass the spack yaml path explicitly." >&2
        echo "Usage: $0 [env-name] [spack-yaml]" >&2
        exit 1
    fi
    spack_environment_yaml_file="$TURBO_STACK_ROOT/spack/spack.yaml"
fi

if [[ ! -f "$spack_environment_yaml_file" ]]; then
    echo "Error: spack yaml not found at $spack_environment_yaml_file" >&2
    exit 1
fi

# --- Source Spack ---
source "$SPACK_ROOT/share/spack/setup-env.sh"

# --- Create and install ---
if spack env list | grep -qw "$spack_environment_name"; then
    echo "Environment '$spack_environment_name' already exists."
    echo "  To use it:      spack env activate $spack_environment_name"
    echo "  To rebuild it:  spack env rm $spack_environment_name && $0 $spack_environment_name $spack_environment_yaml_file"
    exit 0
fi

echo "Creating Spack environment '$spack_environment_name' from $spack_environment_yaml_file ..."
spack env create "$spack_environment_name" "$spack_environment_yaml_file"
spack env activate "$spack_environment_name"

echo "Concretizing ..."
spack concretize #--fresh --force

echo "Installing (this may take a while) ..."
spack install

echo ""
echo "Environment '$spack_environment_name' is ready. To use it:"
echo ""
echo "  spack env activate $spack_environment_name"
echo ""