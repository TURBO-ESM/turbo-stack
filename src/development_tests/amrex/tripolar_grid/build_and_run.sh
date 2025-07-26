#!/bin/bash

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


###############################################################################
# User Input
###############################################################################

# Set the where the build directory will be created. You can change this to any location you prefer.
export BUILD_DIR=~/tripolar_grid_with_amrex_build

# You can also set the DEBUG environment variable to 1 to enable debugging features.
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -e  # Exit immediately if a command exits with a non-zero status
    set -u  # Treat expanding empty variables as an error
    set -x  # Print each command before executing it
fi


###############################################################################
# Spack Environment Setup
###############################################################################

spack_environment_name="tripolar_grid_amrex"
spack_environment_config_file=$TURBO_STACK_ROOT/src/development_tests/amrex/tripolar_grid/spack.yaml

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
    cmake -DCMAKE_BUILD_TYPE=Debug -S $TURBO_STACK_ROOT/src/development_tests/amrex/tripolar_grid -B $BUILD_DIR --fresh
else
    cmake -S $TURBO_STACK_ROOT/src/development_tests/amrex/tripolar_grid -B $BUILD_DIR
fi

# Build the code. 
cmake --build $BUILD_DIR

# Test the code. 
ctest --test-dir $BUILD_DIR

# Run the code. 
$BUILD_DIR/tripolar_grid