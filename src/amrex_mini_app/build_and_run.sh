#!/bin/bash

###############################################################################
# User Input
###############################################################################

# You can set the BUILD_DIR environment variable to specify a custom build directory. Assumes a default location if not set.
if [[ -z "${BUILD_DIR:-}" ]]; then
    build_dir="${HOME}/turbo_amrex_mini_app_build"
    echo "BUILD_DIR environment variable is not set. Using default build directory location: $build_dir"
else
    build_dir="$BUILD_DIR"
    echo "Using build directory from BUILD_DIR environment variable: $build_dir"
fi

# You can set the DEBUG environment variable to 1 to enable debugging features in this script.
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x  # Print each command before executing it
fi

# You can set the CODE_COVERAGE environment variable to 1 to enable generating code coverage reports. You will need gcov and lcov installed and in your path to do this.
if [[ "${CODE_COVERAGE:-0}" == "1" ]]; then
    echo "Will generate code coverage report."
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

if [[ "${DEBUG:-0}" == "1" ]]; then
    echo "TURBO_STACK_ROOT is set to $TURBO_STACK_ROOT"
    echo "C compiler path is CC=$CC"
    echo "CXX compiler path is CXX=$CXX"
fi


###############################################################################
# Build, Test, and Run the Code
###############################################################################

cmake_generate_options=()
cmake_generate_options+=("-DCMAKE_C_COMPILER=$CC")
cmake_generate_options+=("-DCMAKE_CXX_COMPILER=$CXX")
if [[ "${DEBUG:-0}" == "1" ]]; then
    cmake_generate_options+=("-DCMAKE_BUILD_TYPE=Debug")
    cmake_generate_options+=("--fresh")
fi
if [[ "${CODE_COVERAGE:-0}" == "1" ]]; then
    cmake_generate_options+=("-DCODE_COVERAGE=ON")
fi

# Generate the build directory. 
cmake "${cmake_generate_options[@]}" -S "$mini_app_root" -B "$build_dir"

# Build the code. 
cmake_build_options=()
if [[ "${DEBUG:-0}" == "1" ]]; then
    cmake_build_options+=("--clean-first")
else
    cmake_build_options+=("--parallel $(nproc)")
fi
cmake --build "$build_dir" "${cmake_build_options[@]}"

# Run the unit tests. 
ctest --test-dir "$build_dir"

# Run the examples. 
#cd "$build_dir/examples"
#examples_to_run=("domain_example")
#for example in "${examples_to_run[@]}"; do
#    if [[ -x "./$example" ]]; then
#        echo "Running example: $example"
#        #./"$example"
#        mpiexec -n 4 ./"$example"
#        #python "$mini_app_root/postprocessing/plot_hdf5.py" "${example}.h5"
#    else
#        echo "Error: $example binary not found or not executable in $build_dir/examples." >&2
#        exit 1
#    fi
#done

#spack env deactivate
#python3 "$mini_app_root/postprocessing/plot_hdf5.py" initialization_mini_app.h5


###############################################################################
# Generate the code coverage report
###############################################################################
if [[ "${CODE_COVERAGE:-0}" == "1" ]]; then
    echo "Generating code coverage report..."

    if ! command -v lcov &> /dev/null; then
        echo "Error: lcov command not found. You need to have lcov installed and in your path to generate code coverage reports." >&2
        exit 1
    fi

    # Generate the full coverage file
    full_coverage_file="$build_dir/coverage.info"
    lcov --capture --directory "$build_dir" --output-file "$full_coverage_file" --ignore-errors mismatch,unexecuted_blocks

    # Only keep coverage for files in the mini_app_root directory
    filtered_coverage_file="$build_dir/coverage.filtered.info"
    lcov --extract "$full_coverage_file" "$mini_app_root/*" --output-file "$filtered_coverage_file"

    # Generate the HTML report for the mini-app only
    if ! command -v genhtml &> /dev/null; then
        echo "Error: genhtml command not found. You need to have genhtml installed and in your path to generate code coverage HTML reports." >&2
        exit 1
    fi

    genhtml "$filtered_coverage_file" --output-directory "$build_dir/coverage"
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
