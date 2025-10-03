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


###############################################################################
# Spack Environment Setup
###############################################################################

spack_environment_name="tripolar_grid_amrex"
spack_environment_config_file="$tripolar_dir/spack/spack.yaml"

## Derecho Specific Environment Setup.
if [[ -n "${NCAR_HOST:-}" && "${NCAR_HOST}" == "derecho" ]]; then

    echo "Detected host: derecho. Running derecho-specific setup..."
    module purge
    #module load gcc cray-mpich # Works
    module load gcc cmake cray-mpich # Works
    #module load gcc ncarcompilers cmake cray-mpich # Does not work
    module list
    spack_environment_config_file="$tripolar_dir/spack/derecho_spack.yaml"
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

# Run the examples. 
cd "$build_dir/examples"
if [[ -x "./tripolar_grid" ]]; then
    ./tripolar_grid
else
    echo "Error: tripolar_grid binary not found or not executable in $build_dir/examples." >&2
    exit 1
fi

# Build the documentation.
cd "$tripolar_dir/doc"
doxygen Doxyfile

#python "$tripolar_dir/postprocessing/plot_hdf5.py" tripolar_grid.h5