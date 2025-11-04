#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat expanding empty variables as an error

###############################################################################
# User Input
###############################################################################

export DEBUG=1

compiler_list="gcc llvm intel-oneapi-compilers"

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
                #export COMPILER_ROOT=/path/to/gcc
                ;;
            llvm)
                export COMPILER_PACKAGE_NAME=llvm
                export COMPILER_VERSION=20.1.8
                #export COMPILER_ROOT=/path/to/llvm
                ;;
            intel-oneapi-compilers)
                export COMPILER_PACKAGE_NAME=intel-oneapi-compilers
                export COMPILER_VERSION=2025.2.1
                #export COMPILER_ROOT=/path/to/intel-oneapi-compilers
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
                #export MPI_ROOT=/path/to/openmpi
                ;;
            mpich)
                export MPI_PACKAGE_NAME=mpich
                export MPI_VERSION=4.3.2
                #export MPI_ROOT=/path/to/mpich
                ;;
            *)
                echo "Error: Unsupported MPI '$MPI'. Supported: openmpi, mpich."
                exit 1
                ;;
        esac
    
        ./build_and_run.sh

    done
done