#!/bin/bash

###############################################################################
# User Input
###############################################################################

# Set the where the build directory will be created. You can change this to any location you prefer.
build_dir=~/turbo_amrex_mini_app_build

# You can set the DEBUG environment variable to 1 to enable debugging features in this script.
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x  # Print each command before executing it
fi

# You can set the DOXYGEN environment variable to 1 to build the doxygen documentation. You will need the doxygen executable installed and in your path to do this.
if [[ "${DOXYGEN:-0}" == "1" ]]; then
    echo "Will generate Doxygen documentation."
fi

###############################################################################
# Error Checking Pre-requisites... Should be true for all environments
###############################################################################

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat expanding empty variables as an error

if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
    echo "Error: TURBO_STACK_ROOT environment variable is not set. It should point to where you cloned the turbo-stack repository." >&2
    exit 1
fi
if [[ ! -d "$TURBO_STACK_ROOT" ]]; then
    echo "Error: TURBO_STACK_ROOT environment variable does not point to a valid directory. It should point to where you cloned the turbo-stack repository." >&2
    exit 1
fi

# Make sure the assumed location of our mini-app within the turbo-stack repo exists. This path might change later.
mini_app_root="$TURBO_STACK_ROOT"/src/amrex_mini_app
if [[ ! -d "$mini_app_root" ]]; then
    echo "Error: mini_app_root does not point to a valid directory. It should point to the directory with the top level cmake file for the mini-app." >&2
    exit 1
fi

if [[ -z "${CC:-}" ]]; then
    echo "Error: CC environment variable is not set or is empty." >&2
    exit 1
fi
if [[ ! -x "$(command -v $CC)" ]]; then
    echo "Error: C compiler at path '$CC' is not executable." >&2
    exit 1
fi

if [[ -z "${CXX:-}" ]]; then
    echo "Error: CXX environment variable is not set or is empty." >&2
    exit 1
fi
if [[ ! -x "$(command -v $CXX)" ]]; then
    echo "Error: CXX compiler at path '$CXX' is not executable." >&2
    exit 1
fi

# Maybe also check for mpi compiler wrappers MPICC and MPICXX?

if [[ "${DEBUG:-0}" == "1" ]]; then
    echo "TURBO_STACK_ROOT is set to $TURBO_STACK_ROOT"
    echo "C compiler path is CC=$CC"
    echo "CXX compiler path is CXX=$CXX"
fi

###############################################################################
# Build, Test, and Run the Code
###############################################################################

cmake_options=()
cmake_options+=("-DCMAKE_C_COMPILER=$CC")
cmake_options+=("-DCMAKE_CXX_COMPILER=$CXX")
if [[ "${DEBUG:-0}" == "1" ]]; then
    cmake_options+=("-DCMAKE_BUILD_TYPE=Debug")
    cmake_options+=("--fresh")
fi

# Generate the build directory. 
cmake "${cmake_options[@]}" -S "$mini_app_root" -B "$build_dir"

# Build the code. 
cmake --build "$build_dir"

# Run the unit tests. 
ctest --test-dir "$build_dir"

# Run the examples. 
cd "$build_dir/examples"
if [[ -x "./tripolar_grid" ]]; then
    ./tripolar_grid
    #python "$mini_app_root/postprocessing/plot_hdf5.py" tripolar_grid.h5
else
    echo "Error: tripolar_grid binary not found or not executable in $build_dir/examples." >&2
    exit 1
fi

###############################################################################
# Build the Doxygen Documentation
###############################################################################

if [[ "${DOXYGEN:-0}" == "1" ]]; then
    # Check if doxygen is installed
    if ! command -v doxygen &> /dev/null; then
        echo "Error: doxygen is not installed or not in the PATH." >&2
        exit 1
    fi
    echo "Building Doxygen documentation..."
    cd "$mini_app_root/doc"
    doxygen Doxyfile
fi