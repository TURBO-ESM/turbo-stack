#!/bin/bash -e

# Save various paths to use as shortcuts
ROOTDIR=`pwd -P`
MKMF_ROOT=${ROOTDIR}/build-utils/mkmf
TEMPLATE_DIR=${ROOTDIR}/build-utils/makefile-templates
MOM_ROOT=${ROOTDIR}/src/MOM6
FMS_ROOT=${ROOTDIR}/src/FMS
SHR_ROOT=${ROOTDIR}/src/CESM_share

# Default values for CLI arguments
COMPILER="intel"
MACHINE="ncar"
MEMORY_MODE="dynamic_symmetric"
DEBUG=0 # False

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 [--compiler <compiler>] [--machine <machine>] [--memory-mode <memory_mode>]"
            echo "Default values: compiler=$COMPILER, machine=$MACHINE, memory_mode=$MEMORY_MODE"
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
        --debug)
            DEBUG=1 ;;
        *) 
            echo "Unknown parameter passed: $1"
            echo "Usage: $0 [--compiler <compiler>] [--machine <machine>] [--memory-mode <memory_mode>]"
            exit 1 ;;
    esac
    shift
done

echo "Starting build at `date`"
echo "Compiler: $COMPILER"
echo "Machine: $MACHINE"
echo "Memory mode: $MEMORY_MODE"
echo "Debug mode: $DEBUG"

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

# Set -j option based on the MACHINE argument
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


if [ "${DEBUG}" == 1 ]; then
  BLD_PATH=${ROOTDIR}/bin/${COMPILER}-debug
else
  BLD_PATH=${ROOTDIR}/bin/${COMPILER}
fi

# Create build directory if it does not exist
if [ ! -d ${BLD_PATH} ]; then
  mkdir -p ${BLD_PATH}
fi

# Load modules for NCAR machines
if [ "$MACHINE" == "ncar" ]; then
  HOST=`hostname`
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
        module load craype nvhpc/23.7 ncarcompilers/1.0.0 cmake cray-mpich/8.1.27 netcdf-mpi/4.9.2 parallel-netcdf/1.12.3 parallelio/2.6.2 esmf/8.6.0
        ;;
      *)
        echo "Not loading any special modules for ${COMPILER}"
        ;;
    esac
  fi
fi


MOM6_src_files=${MOM_ROOT}/{config_src/infra/FMS2,config_src/memory/${MEMORY_MODE},config_src/drivers/solo_driver,pkg/CVMix-src/src/shared,pkg/GSW-Fortran/modules,../MARBL/src,config_src/external,src/{*,*/*}}/

# 1) Build FMS
cd ${BLD_PATH}
mkdir -p FMS
cd FMS
${MKMF_ROOT}/list_paths ${FMS_ROOT}
# We need shr_const_mod.F90 and shr_kind_mod.F90 from ${SHR_ROOT}/src to build FMS
echo "${SHR_ROOT}/src/shr_kind_mod.F90" >> path_names
echo "${SHR_ROOT}/src/shr_const_mod.F90" >> path_names
${MKMF_ROOT}/mkmf -t ${TEMPLATE} -p libfms.a -c "-Duse_libMPI -Duse_netCDF -DSPMD" path_names
make -j${JOBS} DEBUG=${DEBUG} libfms.a

# 2) Build MOM6
cd ${BLD_PATH}
mkdir -p MOM6
cd MOM6
expanded=$(eval echo ${MOM6_src_files})
${MKMF_ROOT}/list_paths -l ${expanded}
${MKMF_ROOT}/mkmf -t ${TEMPLATE} -o '-I../FMS' -p MOM6 -l '-L../FMS -lfms' -c '-Duse_libMPI -Duse_netCDF -DSPMD' path_names
make -j${JOBS} DEBUG=${DEBUG} MOM6

echo "Finished build at `date`"
