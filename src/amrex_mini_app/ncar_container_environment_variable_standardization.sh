#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat expanding empty variables as an error

###############################################################################
# Error Checking Pre-requisites for Container Environment
###############################################################################

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

# Check that HDF5_VERSION is set
if [[ -z "${HDF5_VERSION:-}" ]]; then
    echo "Error: HDF5_VERSION environment variable is not set. Expected the container environment to already have that set." >&2
    exit 1
fi

###############################################################################
# Translate the environment variables in the NCAR container environment to the variables used in this script.
###############################################################################

if [[ "${COMPILER_FAMILY}" == "gcc" ]]; then
    export COMPILER_PACKAGE_NAME="gcc"
    export COMPILER_VERSION=${GCC_VERSION}
    export COMPILER_ROOT=/container/${COMPILER_PACKAGE_NAME}/${COMPILER_VERSION}
elif [[ "${COMPILER_FAMILY}" == "clang" ]]; then
    export COMPILER_PACKAGE_NAME="llvm"
    export COMPILER_VERSION=${LLVM_VERSION}
    export COMPILER_ROOT=/container/${COMPILER_PACKAGE_NAME}/${COMPILER_VERSION}
elif [[ "${COMPILER_FAMILY}" == "oneapi" ]]; then
    export COMPILER_PACKAGE_NAME="intel-oneapi-compilers"
    export COMPILER_VERSION=2025.2 # Hardcoding for now since the oneAPI containers do not set an environment variable with the version.
    export COMPILER_ROOT=/container/intel-oneapi/compiler/2025.2
elif [[ "${COMPILER_FAMILY}" == "nvhpc" ]]; then
    export COMPILER_PACKAGE_NAME="nvhpc"
    export COMPILER_VERSION=25.7  # Hardcoding for now since the nvhpc containers do not set an environment variable with the version.
    export COMPILER_ROOT=/container/nvhpc/Linux_x86_64/25.7/compilers
else
    echo "Error: Unsupported COMPILER_FAMILY=${COMPILER_FAMILY}. Supported values are: gcc" >&2
    exit 1
fi

# Spack specific stuff based on the MPI implementation
if [[ "${MPI_FAMILY}" == "openmpi" ]]; then
    export MPI_PACKAGE_NAME="openmpi"
    export MPI_VERSION="${OPENMPI_VERSION}"
    export MPI_ROOT="${MPI_ROOT}" # MPI_ROOT should already be set in the container environment
elif [[ "${MPI_FAMILY}" == "mpich" ]]; then
    export MPI_PACKAGE_NAME="mpich"
    export MPI_VERSION="${MPICH_VERSION}"
    export MPI_ROOT="${MPI_ROOT}" # MPI_ROOT should already be set in the container environment
else
    echo "Error: Unsupported MPI_FAMILY=${MPI_FAMILY}. Supported values are: openmpi, mpich" >&2
    exit 1
fi

export HDF5_VERSION=${HDF5_VERSION} # HDF5_VERSION should already be set in the container environment
export HDF5_ROOT=/container/hdf5/${HDF5_VERSION}

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