#!/bin/bash -e

# Save various paths to use as shortcuts
ROOTDIR=$(pwd -P)
MKMF_ROOT=${ROOTDIR}/build-utils/mkmf
TEMPLATE_DIR=${ROOTDIR}/build-utils/makefile-templates
MOM_ROOT=${ROOTDIR}/submodules/MOM6
SHR_ROOT=${ROOTDIR}/submodules/CESM_share
AMREX_ROOT=${ROOTDIR}/submodules/amrex
INFRA_ROOT=${ROOTDIR}/submodules/FMS

# Default values for CLI arguments
COMPILER="intel"
MACHINE="ncar"
INFRA="FMS2"
MEMORY_MODE="dynamic_symmetric"
OFFLOAD=0 # False
DEBUG=0 # False
CODECOV=0 # False
OVERRIDE=0 # False
UNIT_TESTS_ONLY=0 # False

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 [--compiler <compiler>] [--machine <machine>] [--memory-mode <memory_mode>] [--infra <infra>] [--codecov] [--offload] [--debug][--override]"
            echo "Build script for MOM6 with FMS."
            echo "  --compiler <compiler>        Compiler to use (default: intel)"
            echo "  --machine <machine>          Machine type (default: ncar)"
            echo "  --memory-mode <memory_mode>  Memory mode (default: dynamic_symmetric)"
            echo "  --infra <infra>              Subdirectory of config_src/infra/ to build (default: FMS2)"
            echo "  --codecov                    Enable code coverage (default: disabled)"
            echo "  --debug                      Enable debug mode (default: disabled)"
            echo "  --override                   If a build already exists, clear it and rebuild (default: false)"
            echo "  --unit-tests-only            Build infrastructure unit tests rather than MOM6 executable (default: false)"
            echo "  --jobs <num_jobs>            Sets the number of jobs to use for make/cmake calls."
            echo "Examples:"
            echo "  $0 --compiler nvhpc --machine ncar"
            echo "  $0 --memory-mode dynamic_nonsymmetric"
            echo "  $0 --compiler gnu --codecov"
            exit 0 ;;
        --compiler) 
            COMPILER="$2"
            shift ;;
        --machine) 
            MACHINE="$2"
            shift ;;
        --memory-mode)
            MEMORY_MODE="$2"
            shift ;;
        --codecov)
            CODECOV=1 ;;
        --offload)
            OFFLOAD=1 ;;
        --debug)
            DEBUG=1 ;;
        --override)
            OVERRIDE=1 ;;
        --infra)
            INFRA="$2"
            if [[ "${INFRA}" == "TIM" ]]; then
              INFRA_ROOT=${ROOTDIR}/submodules/TIM
            fi
            shift ;;
        --jobs)
            JOBS="$2"
            if [[ ! "${JOBS}" =~ ^[0-9]+$ ]]; then
                echo "--jobs option ${JOBS} not a valid positive integer."
                exit 1
            fi
            if [[ ! "${JOBS}" -gt 0 ]]; then
                echo "--jobs option ${JOBS} not greater than 0."
                exit 1
            fi
            shift ;;
        --amrex)
            AMREX_INSTALL_PATH="$2"
            if [ ! -d "${AMREX_INSTALL_PATH}" ]; then
              echo "--amrex path ${AMREX_INSTALL_PATH} not valid"
              exit 1
            fi
            if [[ ! -d "${AMREX_INSTALL_PATH}/include" && ! -d "${AMREX_INSTALL_PATH}/lib" ]]; then
              echo "${AMREX_INSTALL_PATH} is valid but not built/installed (include and lib directories missing."
              echo "Please follow the AMReX instructions and re-run the TURBO build."
              exit 1
            fi
            shift ;;
        --unit-tests-only)
            UNIT_TESTS_ONLY=1 ;;
        *) 
            echo "Unknown parameter passed: $1"
            echo "Usage: $0 [--compiler <compiler>] [--machine <machine>] [--memory-mode <memory_mode>] [--codecov]  [--offload] [--debug] [--override]"
            exit 1 ;;
    esac
    shift
done

echo "Starting build at $(date)"
echo "Compiler: $COMPILER"
echo "Machine: $MACHINE"
echo "Memory mode: $MEMORY_MODE"
echo "Code coverage enabled?: $CODECOV"
echo "Offloading: $OFFLOAD"
echo "Debug mode: $DEBUG"
echo "Override existing build?: $OVERRIDE"
LIBINFRA=libinfra-${INFRA}.a
echo "Infrastructure library: $LIBINFRA"

TEMPLATE=${TEMPLATE_DIR}/${MACHINE}-${COMPILER}.mk

# Throw error if template does not exist:
if [ ! -f $TEMPLATE ]; then
  echo "ERROR: Template file $TEMPLATE does not exist."
    echo "Templates are based on the machine and compiler arguments: machine-compiler.mk. Available templates are:"
    ls ${TEMPLATE_DIR}/*.mk
    echo "Exiting."
  exit 1
fi

# Throw error if memory mode is not in [dynamic_symmetric, dynamic_nonsymmetric]
if [[ "$MEMORY_MODE" != "dynamic_symmetric" && "$MEMORY_MODE" != "dynamic_nonsymmetric" ]]; then
  echo "ERROR: Invalid memory mode '$MEMORY_MODE'. Valid options are 'dynamic_symmetric' or 'dynamic_nonsymmetric'."
  exit 1
fi

# Throw error if code coverage is enabled but compiler is not gnu or gcc
# This check can be relaxed if and when CODECOV is taken into account in other makefile templates.
# See ncar-gnu.mk as an example.
if [[ $CODECOV -eq 1 && ( "$COMPILER" != "gnu" && "$COMPILER" != "gcc" ) ]]; then
  echo "ERROR: Code coverage can only be enabled with the GNU/GCC compiler."
  exit 1
fi

# Throw error if code coverage is enabled but machine is not ncar or container
# This check can be relaxed if and when CODECOV is taken into account in other makefile templates.
# See ncar-gnu.mk as an example.
if [[ $CODECOV -eq 1 && ( "$MACHINE" != "ncar" && "$MACHINE" != "container" ) ]]; then
  echo "ERROR: Code coverage can only be enabled on the NCAR or container machine."
  exit 1
fi

# Cannot specify --codecov with --debug
if [[ $CODECOV -eq 1 && $DEBUG -eq 1 ]]; then
  echo "ERROR: Cannot specify --codecov with --debug."
  echo "Please choose one of the two options."
  exit 1
fi

if [[ $OFFLOAD -eq 1 && ( "$MACHINE" != "ncar" || "$COMPILER" != "nvhpc" ) ]]; then
  echo "ERROR: Offloading can only be enabled on NCAR machines with NVHPC compiler."
  exit 1
fi

# Check if JOBS was defined by the user, if not then set according to machine specs.
if [ -z "${JOBS}"  ]; then
    # Set -j option based on the MACHINE argument.
    case $MACHINE in
        "homebrew" )
            JOBS=2
            ;;
        "ubuntu" )
            JOBS=4
            ;;
        "ncar")
            JOBS=8
            ;;
        *)
            JOBS=4
            echo "Unknown machine type for make -j option: ${MACHINE}; defaulting to JOBS=${JOBS}"
            ;;
    esac
fi
echo "Using ${JOBS} jobs"

BLD_PATH=${ROOTDIR}/bin/${COMPILER}

# If override is set, remove existing build directory
if [ $OVERRIDE -eq 1 ]; then
  if [ -d ${BLD_PATH} ]; then
    echo "Removing existing build directory: ${BLD_PATH}"
    rm -rf ${BLD_PATH}
  fi
fi

# Create build directory if it does not exist
if [ ! -d ${BLD_PATH} ]; then
  mkdir -p ${BLD_PATH}
fi

# Load modules for NCAR machines
if [ "$MACHINE" == "ncar" ]; then
  HOST=$(hostname)
  # Load modules if on derecho
  if [ ! "${HOST:0:5}" == "crhtc" ] && [ ! "${HOST:0:6}" == "casper" ]; then
    module --force purge
    . /glade/u/apps/derecho/23.09/spack/opt/spack/lmod/8.7.24/gcc/7.5.0/c645/lmod/lmod/init/sh
    module load cesmdev/1.0 ncarenv/23.09
    case $COMPILER in
      "intel" )
        module load craype intel/2023.2.1 mkl ncarcompilers/1.0.0 cmake cray-mpich/8.1.27 netcdf-mpi/4.9.2 parallel-netcdf/1.12.3 parallelio/2.6.2 esmf/8.6.0
        ;;
      "gnu" )
        module load craype gcc/12.2.0 cray-libsci/23.02.1.1 ncarcompilers/1.0.0 cmake cray-mpich/8.1.27 netcdf-mpi/4.9.2 parallel-netcdf/1.12.3 parallelio/2.6.2-debug esmf/8.6.0-debug
        ;;
      "nvhpc" )
        if [ $OFFLOAD -eq 1 ]; then
          module load craype nvhpc/24.9 ncarcompilers/1.0.0 cmake cray-mpich/8.1.29 netcdf-mpi/4.9.2 parallel-netcdf/1.12.3 cuda/12.2.1
        else
          module load craype nvhpc/23.7 ncarcompilers/1.0.0 cmake cray-mpich/8.1.27 netcdf-mpi/4.9.2 parallel-netcdf/1.12.3
        fi
        ;;
      *)
        echo "Not loading any special modules for ${COMPILER}"
        ;;
    esac
  fi
fi

# comma-separated list of files in src/framework that are needed to build $LININFRA (for FMS2, at least)
MOM6_infra_framework_deps_list=$(cat << EOF
MOM_string_functions.F90
MOM_io.F90
MOM_array_transform.F90
MOM_domains.F90
MOM_error_handler.F90
posix.F90
MOM_file_parser.F90
MOM_coms.F90
MOM_document.F90
MOM_cpu_clock.F90
MOM_unit_scaling.F90
MOM_dyn_horgrid.F90
MOM_hor_index.F90
MOM_ensemble_manager.F90
MOM_io_file.F90
MOM_netcdf.F90
EOF
)
MOM6_infra_framework_deps=$(echo ${MOM6_infra_framework_deps_list} | tr ' ' ',')
# comma-separated list of files in src/core that are needed to build $LIBINFRA (for FMS2, at least)
MOM6_infra_core_deps=MOM_grid.F90,MOM_verticalGrid.F90
MOM6_infra_files=${MOM_ROOT}/{config_src/memory/${MEMORY_MODE},config_src/infra/${INFRA},src/framework/{$MOM6_infra_framework_deps},src/core/{$MOM6_infra_core_deps}}
MOM6_src_files=${MOM_ROOT}/{config_src/memory/${MEMORY_MODE},config_src/drivers/solo_driver,pkg/CVMix-src/src/shared,pkg/GSW-Fortran/modules,../MARBL/src,config_src/external,src/{*,*/*}}/

# 0) Build AMReX if needed
if [[ "${INFRA}" == "TIM" ]]; then
  # Check if AMREX_INSTALL_PATH was provided or if need to build from submodule first.
  if [[ -z "${AMREX_INSTALL_PATH}" ]]; then
    echo "Path to AMReX not declared.  Building AMReX through submodule."
    cd "${BLD_PATH}"
    mkdir -p amrex
    cd amrex

    AMREX_INSTALL_PATH="$(pwd)/install"

    # Redeclaring variables needed because they are not exported
    TEMPLATE=${TEMPLATE}                     \
    JOBS=${JOBS}                             \
    AMREX_ROOT=${AMREX_ROOT}                 \
    BLD_PATH=$(pwd)/build                    \
    AMREX_INSTALL_PATH=${AMREX_INSTALL_PATH} \
       make -j${JOBS} -C ${ROOTDIR}/build-utils/amrex-utils/ build_amrex
  fi
  AMREX_LINK_FLAGS="-L${AMREX_INSTALL_PATH}/lib -lamrex"
  AMREX_INCLUDE_FLAGS="-I${AMREX_INSTALL_PATH}/include"
fi

# 1) Build Underlying Infrastructure Library
if [[ "${INFRA}" == "FMS2" || "${INFRA}" == "TIM" ]]; then
  cd ${BLD_PATH}
  mkdir -p ${INFRA}
  cd ${INFRA}
  ${MKMF_ROOT}/list_paths ${INFRA_ROOT}
  # We need shr_const_mod.F90 and shr_kind_mod.F90 from ${SHR_ROOT}/src to build FMS
  echo "${SHR_ROOT}/src/shr_kind_mod.F90" >> path_names
  echo "${SHR_ROOT}/src/shr_const_mod.F90" >> path_names
  ${MKMF_ROOT}/mkmf -t ${TEMPLATE} -p lib${INFRA}.a -c "-Duse_libMPI -Duse_netCDF -DSPMD" path_names
  make -j${JOBS} DEBUG=${DEBUG} CODECOV=${CODECOV} OFFLOAD=${OFFLOAD} lib${INFRA}.a
  LINKING_FLAGS="-L../MOM6-infra -linfra-${INFRA} -L../${INFRA} -l${INFRA}"
else
  echo "ERROR: Unknown infrastructure ('${INFRA}' is not supported choice)"
  echo "       Valid options are 'FMS2' or 'TIM'"
  exit 1
fi

# 2) Build MOM6 infra
cd ${BLD_PATH}
mkdir -p MOM6-infra
cd MOM6-infra
expanded=$(eval echo ${MOM6_infra_files})
${MKMF_ROOT}/list_paths -l ${expanded}
${MKMF_ROOT}/mkmf -t ${TEMPLATE} -o "-I../${INFRA} -I../MOM6-infra" -p ${LIBINFRA} -c "-Duse_libMPI -Duse_netCDF -DSPMD" path_names
make -j${JOBS} DEBUG=${DEBUG} CODECOV=${CODECOV} OFFLOAD=${OFFLOAD} ${LIBINFRA}

# 3) Build unit tests or MOM6
if [ $UNIT_TESTS_ONLY -eq 1 ]; then
  echo "TODO: build unit tests here!"
else
  cd ${BLD_PATH}
  mkdir -p MOM6
  cd MOM6
  expanded=$(eval echo ${MOM6_src_files})
  ${MKMF_ROOT}/list_paths -l ${expanded}
  ${MKMF_ROOT}/mkmf -t ${TEMPLATE} -o "-I../${INFRA} -I../MOM6-infra" -p MOM6 -l "${LINKING_FLAGS}" -c '-Duse_libMPI -Duse_netCDF -DSPMD' path_names
  make -j${JOBS} DEBUG=${DEBUG} CODECOV=${CODECOV} OFFLOAD=${OFFLOAD} MOM6
fi

echo "Finished build at $(date)"
