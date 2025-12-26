#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat expanding empty variables as an error

###############################################################################
# User Input
###############################################################################

# Set to 1 to enable debugging features in this script.
export DEBUG=1

###############################################################################
# Check Pre-requisites
###############################################################################
if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
    echo "Error: TURBO_STACK_ROOT environment variable is not set. It should point to where you cloned the turbo-stack repository." >&2
    exit 1
fi
if [[ ! -d "$TURBO_STACK_ROOT" ]]; then
    echo "Error: TURBO_STACK_ROOT environment variable does not point to a valid directory. It should point to where you cloned the turbo-stack repository." >&2
    exit 1
fi

# Path to the turbo mini-app that should be within the turbo stack repository
turbo_mini_app_root=${TURBO_STACK_ROOT}/src/amrex_mini_app
if [ ! -d "${turbo_mini_app_root}" ]; then
  echo "Error: turbo_mini_app_root=${turbo_mini_app_root} is not a valid directory."
  exit 1
fi

###############################################################################
# Environment Setup
###############################################################################
module purge
module load gcc cray-mpich hdf5 cmake # had problems when also loading cmake and ncarcompilers module
module list

# Looks like the gcc module on derecho does not set CXX... so set it manually here.
export CXX="$(which g++)"

# Set the environment variables for the spack environment creation script. These should be consistent with the modules you loaded above.
export COMPILER_PACKAGE_NAME="gcc"
export COMPILER_VERSION="12.4.0"
#export COMPILER_VERSION=${GNU_VERSION}
export MPI_PACKAGE_NAME="cray-mpich"
#export MPI_VERSION=${CRAY_MPICH_VERSION}

###############################################################################
# Create the Spack Environment
###############################################################################

unset SPACK_ENVIRONMENT_NAME

. ${turbo_mini_app_root}/create_spack_environment.sh

if [ -z "$SPACK_ENVIRONMENT_NAME" ]; then
  echo "Error: SPACK_ENVIRONMENT_NAME is not set."
  exit 1
fi

###############################################################################
# Build and run turbo amrex mini-app
###############################################################################

spack env activate "$SPACK_ENVIRONMENT_NAME"

${turbo_mini_app_root}/build_and_run.sh