#!/bin/bash

#set -e  # Exit immediately if a command exits with a non-zero status
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
    module load gcc cmake cray-mpich hdf5 # Works
    #module load gcc ncarcompilers cmake cray-mpich # Does not work
    module list

    
elif [[ "$machine" == "ci_container" ]]; then
    # GCC compilers
    #export COMPILER_FAMILY=gcc
    #export GCC_VERSION=14.3.0
    #export gcc_bin_dir=/container/gcc/14.3.0/bin
    #export gcc_lib_dir=/container/gcc/14.3.0/lib64
    #export gcc_lib64_dir=/container/gcc/14.3.0/lib
    #export gcc_CC=/container/gcc/14.3.0/bin/gcc && export CC=${gcc_CC}
    #export gcc_CXX=/container/gcc/14.3.0/bin/g++ && export CXX=${gcc_CXX}
    #export gcc_F77=/container/gcc/14.3.0/bin/gfortran && export F77=${gcc_F77}
    #export gcc_FC=/container/gcc/14.3.0/bin/gfortran && export FC=${gcc_FC}

    if [[ -z "${COMPILER_FAMILY:-}" ]]; then
        echo "Error: COMPILER_FAMILY environment variable is not set. Expected the container to already have that set." >&2
        exit 1
    fi

    #if [[ "${COMPILER_FAMILY:-}" == "gcc" ]]; then
    #    if [[ -z "${GCC_VERSION:-}" ]]; then
    #        echo "Error: GCC_VERSION environment variable is not set. Expected the container to already have that set." >&2
    #        exit 1
    #    fi
    #    export compiler_version=${GCC_VERSION}
    #fi

    #export compiler_root=/container/${COMPILER_FAMILY}/${compiler_version}
    #if [[ ! -d "${compiler_root}" ]]; then
    #    echo "Error: ${compiler_root} does not exist. Expected that path to exist in the container." >&2
    #    exit 1
    #fi


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

    # HDF5 1.14.6
    #export HDF5_VERSION=1.14.6
    #export PATH=/container/hdf5/1.14.6/bin:${PATH}
    #export CPATH=/container/hdf5/1.14.6/include:${CPATH}
    #export LIBRARY_PATH=/container/hdf5/1.14.6/lib:${LIBRARY_PATH}

    # NETCDF libraries
    #export NETCDF=/container/netcdf
    #export NETCDF_C_VERSION=4.9.3
    #export NETCDF_FORTRAN_VERSION=4.6.2
    #export PATH=/container/netcdf/bin:${PATH}
    #export CPATH=/container/netcdf/include:${CPATH}
    #export LIBRARY_PATH=/container/netcdf/lib:/container/netcdf/lib/plugins${LIBRARY_PATH}
    #export HDF5_PLUGIN_PATH=/container/netcdf/lib/plugins


fi

###############################################################################
# Spack Environment Setup
###############################################################################

spack_environment_name="tripolar_grid_amrex"

if [[ "$machine" == "derecho" ]]; then
    spack_environment_config_file="$tripolar_dir/spack/derecho_spack.yaml"
elif [[ "$machine" == "ci_container" ]]; then

    spack_environment_config_file="$tripolar_dir/spack/ci_container_spack.yaml"

    # Spack specific stuff based on the compiler
    if [[ "${COMPILER_FAMILY:-}" == "gcc" ]]; then
        compiler_package_name="gcc"

        if [[ -z "${GCC_VERSION:-}" ]]; then
            echo "Error: GCC_VERSION environment variable is not set. Expected the container to already have that set." >&2
            exit 1
        fi
        compiler_version=${GCC_VERSION}

        compiler_root=/container/${compiler_package_name}/${compiler_version}

    elif [[ "${COMPILER_FAMILY:-}" == "clang" ]]; then
        compiler_package_name="llvm"

        if [[ -z "${LLVM_VERSION:-}" ]]; then
            echo "Error: LLVM_VERSION environment variable is not set. Expected the container to already have that set." >&2
            exit 1
        fi
        compiler_version=${LLVM_VERSION}

        compiler_root=/container/${compiler_package_name}/${compiler_version}

    elif [[ "${COMPILER_FAMILY:-}" == "oneapi" ]]; then
        compiler_package_name=" intel-oneapi-compilers"
        
        # Hardcoding for now since the oneAPI containers do not set an environment variable with the version.
        #compiler_version=2025.2

        compiler_root=/container/intel-oneapi/compiler/2025.2

    elif [[ "${COMPILER_FAMILY:-}" == "nvhpc" ]]; then
        compiler_package_name="nvhpc"

        # Hardcoding for now since the nvhpc containers do not set an environment variable with the version.
        #compiler_version=25.7

        compiler_root=/container/nvhpc/Linux_x86_64/25.7/compilers

    else
        echo "Error: Unsupported COMPILER_FAMILY=${COMPILER_FAMILY}. Supported values are: gcc" >&2
        exit 1
    fi
    
    if [[ ! -d "${compiler_root}" ]]; then
        echo "Error: ${compiler_root} does not exist. Expected that path to exist in the container." >&2
        exit 1
    fi


    # Spack specific stuff based on the MPI implementation
    if [[ "${MPI_FAMILY:-}" == "openmpi" ]]; then
        mpi_package_name="openmpi"

        #if [[ -z "${OPENMPI_VERSION:-}" ]]; then
        #    echo "Error: OPENMPI_VERSION environment variable is not set. Expected the container to already have that set." >&2
        #    exit 1
        #fi
        #mpi_version="${OPENMPI_VERSION}"
        #mpi_root="${MPI_ROOT}"
    elif [[ "${MPI_FAMILY:-}" == "mpich" ]]; then
        mpi_package_name="mpich"

        #if [[ -z "${MPICH_VERSION:-}" ]]; then
        #    echo "Error: MPICH_VERSION environment variable is not set. Expected the container to already have that set." >&2
        #    exit 1
        #fi
        #mpi_version="${MPICH_VERSION}"
        #mpi_root="${MPI_ROOT}"
    else
        echo "Error: Unsupported MPI_FAMILY=${MPI_FAMILY}. Supported values are: openmpi" >&2
        exit 1
    fi
    # Change the environment spack.yaml file to use the right MPI package as the provider of the mpi virtual package.
    sed -i "s/MPI_PROVIDER/${mpi_package_name}/g" $spack_environment_config_file

    # check that MPI_ROOT is set
    if [[ -z "${MPI_ROOT:-}" ]]; then
        echo "Error: MPI_ROOT environment variable is not set. Expected the container to already have that set." >&2
        exit 1
    fi
    # check that MPI_ROOT points to a valid directory
    if [[ ! -d "${MPI_ROOT}" ]]; then
        echo "Error: ${MPI_ROOT} does not exist. Expected that path to exist in the container." >&2
        exit 1
    fi
    # name to be consistent with spack external find command below
    mpi_root="${MPI_ROOT}"


    # Spack specific stuff based on the hdf5 implementation
    hdf5_root=/container/hdf5/${HDF5_VERSION}

    cat $spack_environment_config_file

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

if [[ "$machine" == "derecho" ]]; then
    spack external find cmake
    spack external find hdf5
    spack external find mpich
elif [[ "$machine" == "ci_container" ]]; then
    spack external find --not-buildable --path $compiler_root $compiler_package_name
    spack external find --not-buildable --path $mpi_root $mpi_package_name
    spack external find --not-buildable --path $hdf5_root hdf5
    spack external find all
    #spack external find cmake
fi

cat "$(spack config edit --print-file)"

spack install

cat /tmp/root/spack-stage/spack-stage-m4-1.4.20-blcze4kp5jc5yixg4mxmofue3iiukar2/spack-build-out.txt

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