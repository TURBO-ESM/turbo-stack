#!/bin/bash

###############################################################################
# User Input
###############################################################################

# Set the where the build directory will be created. You can change this to any location you prefer.
build_dir=~/tripolar_grid_with_amrex_build

# You can also set the DEBUG environment variable to 1 to enable debugging features in this script.
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x  # Print each command before executing it
fi

# You can also set the CODE_COVERAGE environment variable to 1 to enable generating code coverage reports.
if [[ -z "${CODE_COVERAGE:-}" ]]; then
    CODE_COVERAGE=0
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

if ! command -v spack &> /dev/null; then
    echo "Error: spack command not found. You need to have spack installed and in your path before running this script." >&2
    exit 1
fi

# Make sure the assumed location of our mini-app within the turbo-stack repo exists. This path might change later.
mini_app_root="$TURBO_STACK_ROOT"/src/amrex_mini_app
if [[ ! -d "$mini_app_root" ]]; then
    echo "Error: mini_app_root does not point to a valid directory. It should point to the directory with the top level cmake file for the mini-app." >&2
    exit 1
fi

###############################################################################
# Environment Specific Setup
###############################################################################

# Determine the machine we are running on... used to determine environment specific setups.
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

if [[ "$machine" == "generic" ]]; then

    # Hardcode a compiler name for testing
    #compiler_package_name="gcc"
    #compiler_version="15.2.0"
    
    #compiler_package_name="llvm"
    #compiler_version="20.1.8"

    #compiler_package_name="intel-oneapi-compilers"
    #compiler_version="2025.2.1"

    #compiler_package_name="nvhpc"
    #compiler_version="25.7"

    # Hardcode a mpi package name and version for testing
    #mpi_package_name="openmpi"
    #mpi_package_version="5.0.8"

    #mpi_package_name="mpich"
    #mpi_package_version="4.3.2"

    # If compiler_package_name is explicitly set then print it out.
    if [[ -n "${compiler_package_name:-}" ]]; then
        echo "You explicitly asked for compiler: $compiler_package_name"
        compiler_spec="${compiler_package_name}"
        if [[ -n "${compiler_version:-}" ]]; then
            echo "You explicitly asked for compiler version: $compiler_version"
            compiler_spec="${compiler_package_name}@${compiler_version}"
        fi
    else
        # If compiler_package_name is not explicitly set, just use the first compiler that spack knows about.
        compiler_package_name=$(spack compiler list | awk '/^--/ {print $2; exit}')
        echo "Using compiler: $compiler_package_name with version determined by Spack."
        compiler_spec="${compiler_package_name}"
    fi

    if [[ -n "${mpi_package_name:-}" ]]; then
        echo "You explicitly asked for mpi package: $mpi_package_name"
        mpi_spec="${mpi_package_name}"
        if [[ -n "${mpi_version:-}" ]]; then
            echo "You explicitly asked for mpi version: $mpi_version"
            mpi_spec="${mpi_package_name}@${mpi_version}"
        fi
    else
        mpi_package_name="openmpi"
        mpi_spec="${mpi_package_name}" # Just let spack pick whatever version it wants by not specifying a version in the spec.
        echo "You did not explicitly ask for a specific mpi implementation. Just going to use $mpi_spec as the default option."
    fi

    build_doxygen_documentation=1

elif [[ "$machine" == "derecho" ]]; then

    module purge
    module load gcc cmake cray-mpich hdf5 # Works
    #module load gcc ncarcompilers cmake cray-mpich # Does not work
    module list

    # Looks like the gcc module does not set CXX
    export CXX="$(which g++)"

    compiler_package_name="gcc"
    mpi_package_name="cray-mpich"

    compiler_spec="${compiler_package_name}"
    mpi_spec="${mpi_package_name}"

    build_doxygen_documentation=0

elif [[ "$machine" == "ci_container" ]]; then

    # Check that COMPILER_FAMILY is set
    if [[ -z "${COMPILER_FAMILY:-}" ]]; then
      echo "Error: COMPILER_FAMILY environment variable is not set. Expected the container environment to already have that set." >&2
      exit 1
    fi

    # Check that a environment variable for the compiler version is set.. the name depends on the compiler family.
    if [[ "${COMPILER_FAMILY}" == "gcc" ]]; then
      if [[ -z "${GCC_VERSION:-}" ]]; then
          echo "Error: GCC_VERSION environment variable is not set. Expected the container environment to already have that set." >&2
          exit 1
      fi
    elif [[ "${COMPILER_FAMILY}" == "clang" ]]; then
      if [[ -z "${LLVM_VERSION:-}" ]]; then
          echo "Error: LLVM_VERSION environment variable is not set. Expected the container environment to already have that set." >&2
          exit 1
      fi
    elif [[ "${COMPILER_FAMILY}" == "oneapi" ]]; then
        # Does not look like the oneAPI containers set an environment variable with the version.
        echo "Warning: Using hardcoded version for oneAPI compiler as the container does not provide a version environment variable. The script will continue." >&2
    elif [[ "${COMPILER_FAMILY}" == "nvhpc" ]]; then
        # Does not look like the nvhpc containers set an environment variable with the version.
        echo "Warning: Using hardcoded version for nvhpc compiler as the container does not provide a version environment variable. The script will continue." >&2
    else
        echo "Error: Unsupported COMPILER_FAMILY=${COMPILER_FAMILY}." >&2
        exit 1
    fi

    # Check that MPI_FAMILY is set
    if [[ -z "${MPI_FAMILY:-}" ]]; then
      echo "Error: MPI_FAMILY environment variable is not set. Expected the container environment to already have that set." >&2
      exit 1
    fi

    if [[ "${MPI_FAMILY}" == "openmpi" ]]; then
        if [[ -z "${OPENMPI_VERSION:-}" ]]; then
            echo "Error: OPENMPI_VERSION environment variable is not set. Expected the container environment to already have that set." >&2
            exit 1
        fi
    elif [[ "${MPI_FAMILY}" == "mpich" ]]; then
        if [[ -z "${MPICH_VERSION:-}" ]]; then
            echo "Error: MPICH_VERSION environment variable is not set. Expected the container environment to already have that set." >&2
            exit 1
        fi
    else
        echo "Error: Unsupported MPI_FAMILY=${MPI_FAMILY}. Supported values are: openmpi" >&2
        exit 1
    fi

    # check that MPI_ROOT is set
    if [[ -z "${MPI_ROOT:-}" ]]; then
        echo "Error: MPI_ROOT environment variable is not set. Expected the container environment to already have that set." >&2
        exit 1
    fi
    # check that MPI_ROOT points to a valid directory
    if [[ ! -d "${MPI_ROOT}" ]]; then
        echo "Error: ${MPI_ROOT} does not exist. Expected that path to exist in the container." >&2
        exit 1
    fi

    # Spack specific stuff based on the compiler
    if [[ "${COMPILER_FAMILY}" == "gcc" ]]; then
        compiler_package_name="gcc"
        compiler_version=${GCC_VERSION}
        compiler_root=/container/${compiler_package_name}/${compiler_version}
    elif [[ "${COMPILER_FAMILY}" == "clang" ]]; then
        compiler_package_name="llvm"
        compiler_version=${LLVM_VERSION}
        compiler_root=/container/${compiler_package_name}/${compiler_version}
    elif [[ "${COMPILER_FAMILY}" == "oneapi" ]]; then
        compiler_package_name="intel-oneapi-compilers"
        # Hardcoding for now since the oneAPI containers do not set an environment variable with the version.
        compiler_version=2025.2
        compiler_root=/container/intel-oneapi/compiler/2025.2
    elif [[ "${COMPILER_FAMILY}" == "nvhpc" ]]; then
        compiler_package_name="nvhpc"
        # Hardcoding for now since the nvhpc containers do not set an environment variable with the version.
        compiler_version=25.7
        compiler_root=/container/nvhpc/Linux_x86_64/25.7/compilers
    else
        echo "Error: Unsupported COMPILER_FAMILY=${COMPILER_FAMILY}. Supported values are: gcc" >&2
        exit 1
    fi

    compiler_spec="${compiler_package_name}@${compiler_version}"

    if [[ ! -d "${compiler_root}" ]]; then
        echo "Error: ${compiler_root} does not exist. Expected that path to exist in the container." >&2
        exit 1
    fi

    # Spack specific stuff based on the MPI implementation
    if [[ "${MPI_FAMILY}" == "openmpi" ]]; then
        mpi_package_name="openmpi"
        mpi_version="${OPENMPI_VERSION}"
        mpi_root="${MPI_ROOT}"
    elif [[ "${MPI_FAMILY}" == "mpich" ]]; then
        mpi_package_name="mpich"
        mpi_version="${MPICH_VERSION}"
        mpi_root="${MPI_ROOT}"
    else
        echo "Error: Unsupported MPI_FAMILY=${MPI_FAMILY}. Supported values are: openmpi, mpich" >&2
        exit 1
    fi

    mpi_spec="${mpi_package_name}@${mpi_version}"

    if [[ ! -d "${mpi_root}" ]]; then
        echo "Error: ${mpi_root} does not exist. Expected that path to exist in the container." >&2
        exit 1
    fi


    hdf5_root=/container/hdf5/${HDF5_VERSION}
    if [[ ! -d "${hdf5_root}" ]]; then
        echo "Error: ${hdf5_root} does not exist. Expected that path to exist in the container." >&2
        exit 1
    fi

    build_doxygen_documentation=0

fi

# Check the machine dependent environment stuff that we expect to be set above.
if [[ -z "${build_doxygen_documentation:-}" ]]; then
    echo "Error: build_doxygen_documentation variable is not set." >&2
    exit 1
fi
if [[ -z "${compiler_package_name:-}" ]]; then
    echo "Error: compiler_package_name variable is not set." >&2
    exit 1
fi
if [[ -z "${compiler_spec:-}" ]]; then
    echo "Error: compiler_spec environment variable is not set or is empty." >&2
    exit 1
fi
if [[ -z "${mpi_package_name:-}" ]]; then
    echo "Error: mpi_package_name variable is not set." >&2
    exit 1
fi
if [[ -z "${mpi_spec:-}" ]]; then
    echo "Error: mpi_spec environment variable is not set or is empty." >&2
    exit 1
fi

###############################################################################
# Spack Environment Setup
###############################################################################

# Name the Spack environment based on the compiler and mpi specs... but remove the special characters (@ and .) that are not allowed in spack environment names.
spack_environment_name="turbo_mini_app"
if [[ -n "${compiler_spec:-}" ]]; then
    spack_environment_name="${spack_environment_name}_${compiler_spec//[@.]/_}"
fi
if [[ -n "${mpi_spec:-}" ]]; then
    spack_environment_name="${spack_environment_name}_${mpi_spec//[@.]/_}"
fi

spack_environment_config_file="$mini_app_root/spack/spack.yaml"
if [[ ! -f "$spack_environment_config_file" ]]; then
    echo "Error: spack_environment_config_file does not point to a valid file. It should point to the spack.yaml file to use for this build." >&2
    exit 1
fi

if [[ "${DEBUG:-0}" == "1" ]]; then
    # Remove the existing environment if it already exists so we can start fresh.
    if spack env list | grep --word-regexp --quiet "$spack_environment_name"; then
        spack env rm -f "$spack_environment_name" 
    fi
fi

# Create the spack environment if it does not already exist.
if ! spack env list | grep --word-regexp --quiet "$spack_environment_name"; then
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "Going to use this spack environment config file as a starting point: $spack_environment_config_file"
        cat $spack_environment_config_file
    fi
    spack env create "$spack_environment_name" "$spack_environment_config_file"
fi

spack env activate $spack_environment_name 

if [[ "$build_doxygen_documentation" == "1" ]]; then
    # Build doxygen with gcc when since generating our developer documentation is not performance critical and it may not build easily with other compilers.
    spack add doxygen %gcc
fi

if [[ "$machine" == "generic" ]]; then

    spack add "$compiler_spec"

    spack config add packages:mpi:require:${mpi_spec}

    if [[ "${compiler_spec}" == *"llvm"* ]]; then
        # HDF5 complains about position-independent code when built with clang/llvm for c/c++ and gcc for fortran...  So add pic flags.
        spack add hdf5 cflags="-fPIC" cxxflags="-fPIC" fflags="-fPIC"
    fi

    spack config add packages:all:prefer:[\"%c=${compiler_spec}\"]
    spack config add packages:all:prefer:[\"%cxx=${compiler_spec}\"]
    if [[ "${compiler_spec}" == *"llvm"* ]]; then
        # Assume we dont have a Fortran compiler with llvm/clang... so use gcc to compile Fortran.
        spack config add packages:all:prefer:[\"%fortran=gcc\"]
    else
        spack config add packages:all:prefer:[\"%fortran=${compiler_spec}\"]
    fi

elif [[ "$machine" == "derecho" ]]; then
    spack external find cmake
    spack external find hdf5
    spack external find mpich

    # Hard coded to gcc and cray-mpich for now on derecho
    # Using older version of spack on derecho so use syntax that works there.
    spack config add packages:all:compiler:[gcc]
    spack config add packages:all:providers:mpi:[cray-mpich]

    # This would be more portable to newer versions of spack
    #spack config add packages:mpi:require:cray-mpich
    #spack config add packages:all:prefer:[\"%c=gcc\"]
    #spack config add packages:all:prefer:[\"%cxx=gcc\"]
    #spack config add packages:all:prefer:[\"%fortran=gcc\"]

elif [[ "$machine" == "ci_container" ]]; then

    spack external find --not-buildable --path $compiler_root $compiler_package_name
    spack external find --not-buildable --path $mpi_root $mpi_package_name
    spack external find --not-buildable --path $hdf5_root hdf5

    spack config add packages:mpi:require:${mpi_spec}
    spack config add packages:all:prefer:[\"%c=${compiler_spec}\"]
    spack config add packages:all:prefer:[\"%cxx=${compiler_spec}\"]
    spack config add packages:all:prefer:[\"%fortran=${compiler_spec}\"]

    if [[ ${compiler_spec} == *"llvm"* ]]; then
        # HDF5 complains about position-independent code when built with clang/llvm for c/c++ and gcc for fortran...  So add pic flags.
        spack add amrex+pic

        # Still use gcc for Fortran when using llvm/clang
        spack config remove packages:all:prefer:[\"%fortran=${compiler_spec}\"]
        spack config add    packages:all:prefer:[\"%fortran=gcc\"]
    fi

else
    echo "Error: Unsupported machine type '$machine'" >&2
    exit 1
fi

if [[ "${compiler_spec}" == *"nvhpc"* ]]; then  

  echo "nvhpc build is not working yet. Will update later."
  exit 1

  spack config add concretizer:unify:when_possible

  spack config remove packages:all:prefer:[\"%c=${compiler_spec}\"]
  spack config remove packages:all:prefer:[\"%cxx=${compiler_spec}\"]
  spack config remove packages:all:prefer:[\"%fortran=${compiler_spec}\"]
  spack config add packages:all:prefer:[\"%c=gcc\"]
  spack config add packages:all:prefer:[\"%cxx=gcc\"]
  spack config add packages:all:prefer:[\"%fortran=gcc\"]

  spack remove amrex
  spack remove mpi
  spack remove hdf5
  spack add amrex %${compiler_spec}
  spack add mpi %${compiler_spec}
  spack add hdf5 %${compiler_spec}

  spack config add packages:mbedtls:require:[\"%gcc\"]
  spack config add packages:diffutils:require:[\"%gcc\"]
  spack config add packages:gettext:require:[\"%gcc\"]
  spack config add packages:findutils:require:[\"%gcc\"]
  spack config add packages:m4:require:[\"%gcc\"]
  spack config add packages:flex:require:[\"%gcc\"]
  spack config add packages:mpich:require:[\"%c,cxx,fortran=gcc\"]
fi

if [[ "${DEBUG:-0}" == "1" ]]; then
    echo "Final spack configuration for this environment:"
    cat "$(spack config edit --print-file)"

    if [[ "$machine" == "derecho" ]]; then
        # Older version of spack on derecho does not support --force
        spack install --fresh
    else
        spack install --fresh --force
    fi

    echo "Number of spack packages in the environment is: $(spack find --format '{name}' | wc -l)"

    graph_file=~/spack_environment_${spack_environment_name}_build_graph.dot
    echo "Generating spack environment build graph in DOT format at: $graph_file"
    spack graph --dot --color > "$graph_file"
    if command -v dot &> /dev/null; then
        dot -O -Tpng "$graph_file"
    fi
else
    spack install
fi

if [[ "$machine" == "generic" ]]; then
    ## Load the compiler module to make sure the compiler is in the path and gcc is set
    spack load ${compiler_spec}

    # This could work if you don't added the compiler package to to the spack environment above but it is not as robust.
    #spack load --first ${compiler_spec}
fi

export SPACK_ENV_VIEW_DIR=$(spack location --env)/.spack-env/view

###############################################################################
# Build, Test, and Run the Code
###############################################################################
if [[ -z "${CC:-}" ]]; then
    echo "Error: CC environment variable is not set or is empty." >&2
    exit 1
fi
if [[ -z "${CXX:-}" ]]; then
    echo "Error: CXX environment variable is not set or is empty." >&2
    exit 1
fi
if [[ ! -x "$(command -v $CC)" ]]; then
    echo "Error: C compiler at path '$CC' is not executable." >&2
    exit 1
fi
if [[ ! -x "$(command -v $CXX)" ]]; then
    echo "Error: CXX compiler at path '$CXX' is not executable." >&2
    exit 1
fi
if [[ "${DEBUG:-0}" == "1" ]]; then
    echo "C compiler path is CC=$CC"
    echo "CXX compiler path is CXX=$CXX"
fi

# Turn off code coverage if you are not using gcc and give an error messsage.
if [[ "${compiler_package_name}" != "gcc" && "$CODE_COVERAGE" == "1" ]]; then
    echo "Warning: Code coverage is only supported when using gcc as the compiler. Disabling code coverage generation." >&2
    export CODE_COVERAGE=0
fi

# Maybe also check for mpi compiler wrappers MPICC and MPICXX?

cmake_options=()
cmake_options+=("-DCMAKE_C_COMPILER=$CC")
cmake_options+=("-DCMAKE_CXX_COMPILER=$CXX")
if [[ "${DEBUG:-0}" == "1" ]]; then
    cmake_options+=("-DCMAKE_BUILD_TYPE=Debug")
    cmake_options+=("--fresh")
fi
if [[ "$CODE_COVERAGE" == "1" ]]; then
    cmake_options+=("-DCODE_COVERAGE=ON")
fi

# Generate the build directory. 
cmake "${cmake_options[@]}" -S "$mini_app_root" -B "$build_dir"

# Build the code. 
cmake_build_options=()
if [[ "${DEBUG:-0}" == "1" ]]; then
    cmake_build_options+=("--clean-first")
else
    cmake_build_options+=("--parallel $(nproc)")
fi
cmake --build "$build_dir" "${cmake_build_options[@]}"

# Test the code. 
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

# Generate the code coverage report.
if [[ "$CODE_COVERAGE" == "1" ]]; then
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

if [[ "$build_doxygen_documentation" == "1" ]]; then
    echo "Building Doxygen documentation..."
    cd "$mini_app_root/doc"
    doxygen Doxyfile
fi
