#!/bin/bash

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
# Derecho Environment Setup
###############################################################################

module purge
#module load gcc cray-mpich # Works
module load gcc cmake cray-mpich # Works
#module load gcc ncarcompilers cmake cray-mpich # Does not work
module list

###############################################################################
# Spack Environment Setup
###############################################################################


spack_environment_name="tripolar_grid_amrex"
#spack_environment_config_file=$TURBO_STACK_ROOT/src/development_tests/amrex/tripolar_grid/spack.yaml
spack_environment_config_file=$TURBO_STACK_ROOT/src/development_tests/amrex/tripolar_grid/derecho_spack.yaml

if spack env list | grep --word-regexp --quiet "$spack_environment_name"; then
  if [[ "${DEBUG:-0}" == "1" ]]; then
    spack env rm -f "$spack_environment_name"
  fi
fi

#if [[ "${DEBUG:-0}" == "1" ]]; then
#  spack env rm -f "$spack_environment_name"
#fi

if ! spack env list | grep --word-regexp --quiet "$spack_environment_name"; then
    spack env create "$spack_environment_name" "$spack_environment_config_file"
fi

spack env activate $spack_environment_name 

spack concretize --force


spack install --fresh


###############################################################################
# Build and Run the Code
###############################################################################

# Generate the build directory. 
cmake -S $TURBO_STACK_ROOT/src/development_tests/amrex/tripolar_grid -B $BUILD_DIR --fresh

# Build the code. 
cmake --build $BUILD_DIR

# Test the code.
ctest --test-dir $BUILD_DIR

# Run the code. 
cd $BUILD_DIR
./tripolar_grid
