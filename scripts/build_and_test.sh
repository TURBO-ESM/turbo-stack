#!/bin/bash
# Usage: ./scripts/build_and_test.sh [options] -- <build_and_test.py args>
#
# Sets up and activates a Spack environment, then runs build_and_test.py.
# Users who manage their own environment (modules, manual) can call build_and_test.py directly.
#
# Required environment variables:
#   SPACK_ROOT          Path to your Spack installation
#   TURBO_STACK_ROOT    Path to your turbo-stack repository clone (used in the python script)
#
# Options:
#   --create-spack-env      Create the Spack environment if it does not exist
#   --recreate-spack-env    Delete and recreate the Spack environment from scratch
#   --spack-env NAME        Name of the Spack environment (default: turbo_stack)

set -e

spack_env_name="turbo_stack"
create_spack_env=false
recreate_spack_env=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --create-spack-env)   create_spack_env=true; shift ;;
        --recreate-spack-env) recreate_spack_env=true; shift ;;
        --spack-env)          spack_env_name="$2"; shift 2 ;;
        --)                   shift; break ;;
        *)                    break ;;
    esac
done

if [[ -z "${SPACK_ROOT:-}" ]]; then
    echo "Error: SPACK_ROOT is not set." >&2
    exit 1
fi
if [[ ! -f "$SPACK_ROOT/share/spack/setup-env.sh" ]]; then
    echo "Error: SPACK_ROOT ($SPACK_ROOT) is not a valid Spack installation." >&2
    exit 1
fi

source "$SPACK_ROOT/share/spack/setup-env.sh"

if [[ "$recreate_spack_env" == true ]]; then
    if spack env list | grep -qw "$spack_env_name"; then
        echo "Removing Spack environment '$spack_env_name' ..."
        spack env rm -y "$spack_env_name"
    fi
    create_spack_env=true
fi

if [[ "$create_spack_env" == true ]]; then
    bash "$TURBO_STACK_ROOT/spack/create_spack_environment.sh" "$spack_env_name"
fi

spack env activate "$spack_env_name"

python3 "$TURBO_STACK_ROOT/scripts/build_and_test.py" "$@"
