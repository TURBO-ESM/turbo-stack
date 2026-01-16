#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat expanding empty variables as an error

###############################################################################
# User Input
###############################################################################

# You can set the DEBUG environment variable to 1 to enable debugging features in this script.
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x  # Print each command before executing it
fi

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
module swap ncarenv/24.12
module load gcc cray-mpich hdf5 cmake
# Looks like the gcc module on derecho does not set CXX... so set it manually here.
export CXX="$(which g++)"

module list

# Set environment variables based on the modules you loaded 
export COMPILER_PACKAGE_NAME="gcc"
export COMPILER_VERSION=${GNU_VERSION}
export COMPILER_ROOT=${NCAR_ROOT_COMPILER}

export MPI_PACKAGE_NAME="cray-mpich"
export MPI_VERSION=${CRAY_MPICH_VERSION}
export MPI_ROOT=${NCAR_ROOT_MPI}

if [[ -z "${NCAR_ROOT_HDF5:-}" ]]; then
    echo "Error: NCAR_ROOT_HDF5 environment variable is not set. It should have been set when you loaded the hdf5 module." >&2
    exit 1
fi

if [[ -z "${NCAR_ROOT_CMAKE:-}" ]]; then
    echo "Error: NCAR_ROOT_CMAKE environment variable is not set. It should have been set when you loaded the cmake module." >&2
    exit 1
fi

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

. ${turbo_mini_app_root}/build_and_run.sh
