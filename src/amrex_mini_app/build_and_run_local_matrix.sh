#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat expanding empty variables as an error

###############################################################################
# User Input
###############################################################################

export DEBUG=1

export DOXYGEN=1

#compiler_list="gcc"
compiler_list="gcc llvm intel-oneapi-compilers"

#mpi_list="openmpi"
mpi_list="openmpi mpich"

###############################################################################
# Check Pre-requisites
###############################################################################

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

        . ./create_spack_environment.sh

        spack env activate $SPACK_ENVIRONMENT_NAME
    
        ./build_and_run.sh

    done
done