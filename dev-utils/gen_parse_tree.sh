#!/bin/bash -e

# Save various paths to use as shortcuts
ROOTDIR=`pwd -P`/..
MKMF_ROOT=${ROOTDIR}/build-utils/mkmf
TEMPLATE_DIR=${ROOTDIR}/build-utils/makefile-templates
MOM_ROOT=${ROOTDIR}/src/MOM6
FMS_ROOT=${ROOTDIR}/src/FMS
SHR_ROOT=${ROOTDIR}/src/CESM_share

# Default values for CLI arguments
COMPILER="flang_ptree"
MACHINE="ncar"
MEMORY_MODE="dynamic_symmetric"
DEBUG=0 # False

echo "Starting parse dump at `date`"
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

BLD_PATH=${ROOTDIR}/bin/${COMPILER}

# Create build directory if it does not exist
if [ ! -d ${BLD_PATH} ]; then
  mkdir -p ${BLD_PATH}
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
${MKMF_ROOT}/mkmf --gen-ptree -t ${TEMPLATE} -p libfms.a path_names
make -j${JOBS} DEBUG=${DEBUG} libfms.a

# 2) Build MOM6
cd ${BLD_PATH}
mkdir -p MOM6
cd MOM6
expanded=$(eval echo ${MOM6_src_files})
${MKMF_ROOT}/list_paths -l ${expanded}
${MKMF_ROOT}/mkmf --gen-ptree -t ${TEMPLATE} -o '-I../FMS' -p MOM6 -l '-L../FMS -lfms' path_names
make -j${JOBS} DEBUG=${DEBUG} MOM6

echo "Finished build at `date`"