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

# You can set the DOXYGEN environment variable to 1 to build the doxygen documentation. You will need the doxygen executable installed and in your path to do this.
if [[ "${DOXYGEN:-0}" == "1" ]]; then
    echo "Will generate Doxygen documentation."
fi

compiler_list="gcc llvm intel-oneapi-compilers"

mpi_list="openmpi mpich"

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
# Spack Environment Setup
###############################################################################

for compiler in $compiler_list; do
    for mpi in $mpi_list; do
        COMPILER=$compiler
        MPI=$mpi

        case "$COMPILER" in
            gcc)
                export COMPILER_PACKAGE_NAME=gcc
                export COMPILER_VERSION=15.2.0
                ;;
            llvm)
                export COMPILER_PACKAGE_NAME=llvm
                export COMPILER_VERSION=20.1.8
                ;;
            intel-oneapi-compilers)
                export COMPILER_PACKAGE_NAME=intel-oneapi-compilers
                export COMPILER_VERSION=2025.2.1
                ;;
            *)
                echo "Error: Unsupported compiler '$COMPILER'. Supported: gcc, llvm, intel-oneapi-compilers."
                exit 1
                ;;
        esac
    
        case $MPI in
            openmpi)
                export MPI_PACKAGE_NAME=openmpi
                export MPI_VERSION=5.0.8
                ;;
            mpich)
                export MPI_PACKAGE_NAME=mpich
                export MPI_VERSION=4.3.2
                ;;
            *)
                echo "Error: Unsupported MPI '$MPI'. Supported: openmpi, mpich."
                exit 1
                ;;
        esac

        # Check that spack knows about the compiler that we are going to try to use
        spack_compiler_list=$(spack compiler list)
        if echo "$spack_compiler_list" | grep -q "${COMPILER_PACKAGE_NAME}@${COMPILER_VERSION}"; then
            echo "Going to use compiler: $COMPILER@$COMPILER_VERSION"
            echo "Going to use MPI: $MPI@$MPI_VERSION"
        else
            echo "$COMPILER@$COMPILER_VERSION is NOT available"
            echo "Please install $COMPILER@$COMPILER_VERSION using Spack before proceeding."
            exit 1
        fi

        unset SPACK_ENVIRONMENT_NAME

        . ${turbo_mini_app_root}/create_spack_environment.sh

        if [ -z "$SPACK_ENVIRONMENT_NAME" ]; then
          echo "Error: SPACK_ENVIRONMENT_NAME is not set."
          exit 1
        fi

        spack env activate "$SPACK_ENVIRONMENT_NAME"

        ${turbo_mini_app_root}/build_and_run.sh

    done
done
