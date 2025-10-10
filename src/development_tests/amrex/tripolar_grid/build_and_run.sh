#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat expanding empty variables as an error

###############################################################################
# User Input
###############################################################################

# Set the where the build directory will be created. You can change this to any location you prefer.
build_dir=~/tripolar_grid_with_amrex_build

# You can also set the DEBUG environment variable to 1 to enable debugging features.
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x  # Print each command before executing it
fi

###############################################################################
# Check Pre-requisites
###############################################################################

if [[ -z "$TURBO_STACK_ROOT" || ! -d "$TURBO_STACK_ROOT" ]]; then
    echo "Error: TURBO_STACK_ROOT environment variable is not set or does not point to a valid directory. It should point to where you cloned the turbo-stack repository." >&2
    exit 1
fi

if ! command -v spack &> /dev/null; then
    echo "Error: spack command not found. Please load Spack before running this script." >&2
    exit 1
fi

tripolar_dir="$TURBO_STACK_ROOT"/src/development_tests/amrex/tripolar_grid
if [[ ! -d "$tripolar_dir" ]]; then
    echo "Error: tripolar_dir does not point to a valid directory. It should point to where you want to build the tripolar grid." >&2
    exit 1
fi

if [[ -n "${NCAR_HOST:-}" && "${NCAR_HOST}" == "derecho" ]]; then
    echo "Running on derecho."
    machine="derecho"
elif grep -qE '(docker|containerd|kubepods)' /proc/1/cgroup 2>/dev/null || \
   [[ -f /.dockerenv ]] || \
   [[ -f /run/.containerenv ]]; then
    echo "Detected running inside of a container environment. Assuming this is a CI run and using container-specific settings."
    machine="ci_container"
else
    echo "Not running on Derecho or inside a CI container. Using generic settings."
    machine="generic"
fi

###############################################################################
# Environment Setup
###############################################################################

## Derecho Specific Environment Setup.
if [[ "$machine" == "derecho" ]]; then
    module purge
    module load gcc cmake cray-mpich # Works
    #module load gcc ncarcompilers cmake cray-mpich # Does not work
    module list
elif [[ "$machine" == "ci_container" ]]; then
    # GCC compilers
    export COMPILER_FAMILY=gcc
    export GCC_VERSION=14.3.0
    export gcc_root=/container/gcc/14.3.0
    #export gcc_bin_dir=/container/gcc/14.3.0/bin
    #export gcc_lib_dir=/container/gcc/14.3.0/lib64
    #export gcc_lib64_dir=/container/gcc/14.3.0/lib
    #export gcc_CC=/container/gcc/14.3.0/bin/gcc && export CC=${gcc_CC}
    #export gcc_CXX=/container/gcc/14.3.0/bin/g++ && export CXX=${gcc_CXX}
    #export gcc_F77=/container/gcc/14.3.0/bin/gfortran && export F77=${gcc_F77}
    #export gcc_FC=/container/gcc/14.3.0/bin/gfortran && export FC=${gcc_FC}
    echo "COMPILER_FAMILY=${COMPILER_FAMILY}"
    echo "GCC_VERSION=${GCC_VERSION}"
    echo "gcc_root=${gcc_root}"

    # OPENMPI 5.0.8
    #export MPI_FAMILY=openmpi
    #export MPI_ROOT=/container/openmpi/5.0.8
    #export OPENMPI_VERSION=5.0.8
    #export PATH=/container/openmpi/5.0.8/bin:${PATH}
    #export PRTE_ALLOW_RUN_AS_ROOT=1
    #export PRTE_ALLOW_RUN_AS_ROOT_CONFIRM=1
    #export CXX=/container/openmpi/5.0.8/bin/mpicxx
    #export CC=/container/openmpi/5.0.8/bin/mpicc
    #export FC=/container/openmpi/5.0.8/bin/mpifort
    #export F77=/container/openmpi/5.0.8/bin/mpif77
    #export MPICXX=/container/openmpi/5.0.8/bin/mpicxx
    #export MPICC=/container/openmpi/5.0.8/bin/mpicc
    #export MPIFC=/container/openmpi/5.0.8/bin/mpifort
    #export MPIF77=/container/openmpi/5.0.8/bin/mpif77
    echo "MPI_FAMILY=${MPI_FAMILY}"
    echo "OPENMPI_VERSION=${OPENMPI_VERSION}"
    echo "MPI_ROOT=${MPI_ROOT}"
fi

###############################################################################
# Spack Environment Setup
###############################################################################

spack_environment_name="tripolar_grid_amrex"

if [[ "$machine" == "derecho" ]]; then
    spack_environment_config_file="$tripolar_dir/spack/derecho_spack.yaml"
else
    spack_environment_config_file="$tripolar_dir/spack/spack.yaml"
fi

if [[ "${DEBUG:-0}" == "1" ]]; then
    if spack env list | grep --word-regexp --quiet "$spack_environment_name"; then
        spack env rm -f "$spack_environment_name" 
    fi
fi

if ! spack env list | grep --word-regexp --quiet "$spack_environment_name"; then
    spack env create "$spack_environment_name" "$spack_environment_config_file"
fi

spack env activate $spack_environment_name 

spack install

###############################################################################
# Build, Test, and Run the Code
###############################################################################

# Generate the build directory. 
if [[ "${DEBUG:-0}" == "1" ]]; then
    cmake -DCMAKE_BUILD_TYPE=Debug -S "$tripolar_dir" -B "$build_dir" --fresh
else
    cmake -S "$tripolar_dir" -B "$build_dir"
fi

# Build the code. 
cmake --build "$build_dir"

# Test the code. 
ctest --test-dir "$build_dir"

# Run the code. 
cd "$build_dir/examples"
if [[ -x "./tripolar_grid" ]]; then
    ./tripolar_grid
else
    echo "Error: tripolar_grid binary not found or not executable in $build_dir/examples." >&2
    exit 1
fi

#python "$tripolar_dir/postprocessing/plot_hdf5.py" tripolar_grid.h5