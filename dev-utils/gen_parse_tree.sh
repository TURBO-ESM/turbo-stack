#!/bin/bash -e

# Save various paths to use as shortcuts
ROOTDIR=$(pwd -P)/..
MKMF_ROOT=${ROOTDIR}/build-utils/mkmf
TEMPLATE_DIR=${ROOTDIR}/build-utils/makefile-templates
MOM_ROOT=${ROOTDIR}/submodules/MOM6
SHR_ROOT=${ROOTDIR}/submodules/CESM_share

# Default values for CLI arguments
COMPILER="flang_ptree"
MACHINE="ncar"
INFRA="FMS2"
MEMORY_MODE="dynamic_symmetric"
DEBUG=0 # False
OVERRIDE=0 # False

echo "Starting parse dump at `date`"
# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 [--machine <machine>] [--memory-mode <memory_mode>] [--infra <infra>] [--debug] [--override]"
            echo "Flang parse tree generator."
            echo "  --machine <machine>          Machine type (default: ncar)"
            echo "  --memory-mode <memory_mode>  Memory mode (default: dynamic_symmetric)"
            echo "  --infra <infra>              Subdirectory of config_src/infra/ to build (default: FMS2)"
            echo "  --debug                      Enable debug mode (default: disabled)"
            echo "  --override                   If a build already exists, clear it and rebuild (default: false)"
            echo "  --jobs <num_jobs>            Sets the number of jobs to use for make/cmake calls."
            echo "Examples:"
            echo "  $0 --infra TIM --debug"
            echo "  $0 --infra FMS2"
            exit 0 ;;
        --machine) 
            MACHINE="$2"
            shift ;;
        --memory-mode)
            MEMORY_MODE="$2"
            shift ;;
        --debug)
            DEBUG=1 ;;
        --override)
            OVERRIDE=1 ;;
        --infra)
            INFRA="$2"
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
    esac
    shift
done

echo "Starting build at $(date)"
echo "Compiler: $COMPILER"
echo "Machine: $MACHINE"
echo "Memory mode: $MEMORY_MODE"
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

# 1) Build Underlying Infrastructure Library
if [[ "${INFRA}" == "FMS2" || "${INFRA}" == "TIM" ]]; then
  INFRA_ROOT=${ROOTDIR}/submodules/FMS
  if [[ "${INFRA}" == "TIM" ]]; then
    INFRA_ROOT=${ROOTDIR}/submodules/TIM
  fi
  cd ${BLD_PATH}
  mkdir -p ${INFRA}
  cd ${INFRA}
  ${MKMF_ROOT}/list_paths ${INFRA_ROOT}
  # We need shr_const_mod.F90 and shr_kind_mod.F90 from ${SHR_ROOT}/src to build FMS
  echo "${SHR_ROOT}/src/shr_kind_mod.F90" >> path_names
  echo "${SHR_ROOT}/src/shr_const_mod.F90" >> path_names
  ${MKMF_ROOT}/mkmf --gen-ptree -t ${TEMPLATE} -p lib${INFRA}.a path_names
  make -j${JOBS} DEBUG=${DEBUG} lib${INFRA}.a
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
${MKMF_ROOT}/mkmf --gen-ptree -t ${TEMPLATE} -o "-I../${INFRA} -I../MOM6-infra" -p ${LIBINFRA} path_names
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
  ${MKMF_ROOT}/mkmf --gen-ptree -t ${TEMPLATE} -o "-I../${INFRA} -I../MOM6-infra" -p MOM6 -l "${LINKING_FLAGS}" path_names
  make -j${JOBS} DEBUG=${DEBUG} CODECOV=${CODECOV} OFFLOAD=${OFFLOAD} MOM6
fi

echo "Finished build at $(date)"
