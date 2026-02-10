#!/bin/bash

###############################################################################
# User Input
###############################################################################

# You can set the DEBUG environment variable to 1 to enable debugging features in this script.
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x  # Print each command before executing it
    echo "Running this script in debug mode."
fi

# You can set the DOXYGEN environment variable to 1 to add doxygen in your spack environment.
if [[ "${DOXYGEN:-0}" == "1" ]]; then
   echo "Doxygen will be included in the spack environment."
fi

# You can set the CODE_COVERAGE environment variable to 1 to add code coverage tools in your spack environment.
# We are only supporting code coverage with gcc and llvm compilers. 
#   when using gcc compilers we will add lcov to our spack environment.   
#   llvm comes with its own code coverage tools so we don't need to add any additional packages to the spack environment.

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
# Error Checking Pre-requisites... Machine Dependent Checks
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

    if [[ -n "${COMPILER_PACKAGE_NAME:-}" ]]; then
        compiler_package_name="${COMPILER_PACKAGE_NAME}"
        echo "You explicitly asked for compiler: $compiler_package_name"
        compiler_spec="${compiler_package_name}"

        if [[ -n "${COMPILER_VERSION:-}" ]]; then
            compiler_version="${COMPILER_VERSION}"
            echo "You explicitly asked for compiler version: $compiler_version"
            compiler_spec="${compiler_package_name}@${compiler_version}"
        fi
    else
        # If compiler_package_name is not explicitly set, just use the first compiler that spack knows about.
        compiler_package_name=$(spack compiler list | awk '/^--/ {print $2; exit}')
        echo "You did not explicitly ask for a specific compiler. Using compiler using the first compiler found by spack: $compiler_package_name."
        compiler_spec="${compiler_package_name}"
    fi

    if [[ -n "${MPI_PACKAGE_NAME:-}" ]]; then
        mpi_package_name="${MPI_PACKAGE_NAME}"
        echo "You explicitly asked for mpi package: $mpi_package_name"
        mpi_spec="${mpi_package_name}"
        if [[ -n "${MPI_VERSION:-}" ]]; then
            mpi_version="${MPI_VERSION}"
            echo "You explicitly asked for mpi version: $mpi_version"
            mpi_spec="${mpi_package_name}@${mpi_version}"
        fi
    else
        mpi_package_name="openmpi"
        mpi_spec="${mpi_package_name}" # Just let spack pick whatever version it wants by not specifying a version in the spec.
        echo "You did not explicitly ask for a specific mpi implementation. Just going to use $mpi_spec as the default option."
    fi

elif [[ "$machine" == "derecho" ]]; then

    for var in COMPILER_PACKAGE_NAME COMPILER_VERSION COMPILER_ROOT MPI_PACKAGE_NAME MPI_VERSION MPI_ROOT NCAR_ROOT_HDF5 NCAR_ROOT_CMAKE; do
      if [[ -z "${!var:-}" ]]; then
        echo "Error: $var environment variable is not set." >&2
        exit 1
      fi
    done
    
    for path in COMPILER_ROOT MPI_ROOT NCAR_ROOT_HDF5 NCAR_ROOT_CMAKE; do
        if [[ ! -d "${!path}" ]]; then
            echo "Error: ${!path} does not exist. Expected that path to exist in the container." >&2
            exit 1
        fi
    done

    compiler_package_name=${COMPILER_PACKAGE_NAME}
    compiler_version=${COMPILER_VERSION}
    compiler_root=${COMPILER_ROOT}

    compiler_spec="${compiler_package_name}@${compiler_version}"

    mpi_package_name=${MPI_PACKAGE_NAME}
    mpi_version=${MPI_VERSION}
    mpi_root=${MPI_ROOT}

    mpi_spec="${mpi_package_name}@${mpi_version}"

elif [[ "$machine" == "ci_container" ]]; then

    for var in COMPILER_PACKAGE_NAME COMPILER_VERSION COMPILER_ROOT MPI_PACKAGE_NAME MPI_VERSION MPI_ROOT HDF5_VERSION HDF5_ROOT; do
      if [[ -z "${!var:-}" ]]; then
        echo "Error: $var environment variable is not set." >&2
        exit 1
      fi
    done
    
    for path in COMPILER_ROOT MPI_ROOT HDF5_ROOT; do
        if [[ ! -d "${!path}" ]]; then
            echo "Error: ${!path} does not exist. Expected that path to exist in the container." >&2
            exit 1
        fi
    done

    compiler_package_name=${COMPILER_PACKAGE_NAME}
    compiler_version=${COMPILER_VERSION}
    compiler_root=${COMPILER_ROOT}

    compiler_spec="${compiler_package_name}@${compiler_version}"

    mpi_package_name=${MPI_PACKAGE_NAME}
    mpi_version=${MPI_VERSION}
    mpi_root=${MPI_ROOT}

    mpi_spec="${mpi_package_name}@${mpi_version}"

fi

# Check the machine dependent environment stuff that we expect to be set above.
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

if [[ "${DOXYGEN:-0}" == "1" ]]; then
    # Build doxygen with gcc when since generating our developer documentation is not performance critical and it may not build easily with other compilers.
    spack add doxygen %gcc
fi

if [[ "${CODE_COVERAGE:-0}" == "1" && "${compiler_package_name}" == "gcc" ]]; then
   spack add lcov
fi

if [[ "$machine" == "generic" ]]; then

    spack config add packages:mpi:require:${mpi_spec}

    spack config add packages:all:prefer:[\"%c=${compiler_spec}\"]
    spack config add packages:all:prefer:[\"%cxx=${compiler_spec}\"]
    spack config add packages:all:prefer:[\"%fortran=${compiler_spec}\"]

elif [[ "$machine" == "derecho" ]]; then

    spack external find --not-buildable --path $compiler_root $compiler_package_name
    spack external find --not-buildable --path $mpi_root $mpi_package_name
    spack external find --not-buildable --path $NCAR_ROOT_HDF5 hdf5
    spack external find --not-buildable --path $NCAR_ROOT_CMAKE cmake

    # Using older version of spack on derecho so this syntax to specifiy compiler and mpi
    spack config add packages:all:compiler:[${compiler_spec}]
    spack config add packages:all:providers:mpi:[${mpi_spec}]

elif [[ "$machine" == "ci_container" ]]; then

    spack external find --not-buildable --path $compiler_root $compiler_package_name
    spack external find --not-buildable --path $mpi_root $mpi_package_name
    spack external find --not-buildable --path $HDF5_ROOT hdf5

    spack config add packages:mpi:require:${mpi_spec}
    spack config add packages:all:prefer:[\"%c=${compiler_spec}\"]
    spack config add packages:all:prefer:[\"%cxx=${compiler_spec}\"]
    spack config add packages:all:prefer:[\"%fortran=${compiler_spec}\"]

    if [[ ${compiler_spec} == *"llvm"* ]]; then
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
        spack install --fresh --no-check-signature 
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

export SPACK_ENVIRONMENT_NAME=${spack_environment_name}

###############################################################################
# Error Checking Post-requirements
###############################################################################

if [[ -z "${SPACK_ENVIRONMENT_NAME:-}" ]]; then
  echo "Error: SPACK_ENVIRONMENT_NAME is not set." >&2
  exit 1
fi
