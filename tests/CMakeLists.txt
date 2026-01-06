cmake_minimum_required(VERSION 3.15)

project(TIMUnitTests LANGUAGES Fortran CXX C)

find_package(AMReX REQUIRED)
find_package(PFUNIT REQUIRED)
find_package(MPI REQUIRED)

enable_testing()

# Load external dependencies not provided by modules.
add_library(FMS STATIC IMPORTED)
set_target_properties(FMS PROPERTIES
  IMPORTED_LOCATION $ENV{BLD_PATH}/FMS/libfms.a
  INTERFACE_INCLUDE_DIRECTORIES $ENV{BLD_PATH}/FMS
)
add_library(FMS_Infra STATIC IMPORTED)
set_target_properties(FMS_Infra PROPERTIES
  IMPORTED_LOCATION $ENV{BLD_PATH}/MOM6-infra/libinfra-TIM.a
  INTERFACE_INCLUDE_DIRECTORIES $ENV{BLD_PATH}/MOM6-infra
)

# Load NetCDF/NetCDF_Fortran libraries due to variable dropped from being
# called from makefile
add_library(NetCDF SHARED IMPORTED)
set_target_properties(NetCDF PROPERTIES
  IMPORTED_LOCATION $ENV{NetCDF_DIR}/lib/libnetcdf.so
  INTERFACE_INCLUDE_DIRECTORIES $ENV{NetCDF_DIR}/include
)
add_library(NetCDF_Fortran SHARED IMPORTED)
set_target_properties(NetCDF_Fortran PROPERTIES
  IMPORTED_LOCATION $ENV{NetCDF_Fortran_DIR}/lib/libnetcdff.so
  INTERFACE_INCLUDE_DIRECTORIES $ENV{NetCDF_Fortran_DIR}/include
)

add_pfunit_ctest(infra_tests
  TEST_SOURCES mom_init.pf
  LINK_LIBRARIES NetCDF_Fortran NetCDF FMS_Infra FMS AMReX::amrex
)

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(config/input.nml input.nml COPYONLY)
