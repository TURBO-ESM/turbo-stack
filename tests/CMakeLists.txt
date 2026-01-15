cmake_minimum_required(VERSION 3.15)

project(TURBOUnitTests LANGUAGES Fortran)

enable_language(CXX C)

find_package(PFUNIT REQUIRED)
find_package(MPI REQUIRED)

# Only set AMREX_LIB if needed; else keep undefined
if("$ENV{INFRA}" STREQUAL "TIM")
  find_package(AMReX REQUIRED)
  set(AMREX_LIB AMReX::amrex)
endif()

include(cmake/add_mom_test.cmake)

enable_testing()

# Load external dependencies not provided by modules.
add_library(BACKEND_lib STATIC IMPORTED)
set_target_properties(BACKEND_lib PROPERTIES
  IMPORTED_LOCATION $ENV{BLD_PATH}/FMS/libfms.a
  INTERFACE_INCLUDE_DIRECTORIES $ENV{BLD_PATH}/FMS
)
add_library(BACKEND_Infra STATIC IMPORTED)
set_target_properties(BACKEND_Infra PROPERTIES
  IMPORTED_LOCATION $ENV{BLD_PATH}/MOM6-infra/libinfra-$ENV{INFRA}.a
  INTERFACE_INCLUDE_DIRECTORIES $ENV{BLD_PATH}/MOM6-infra
)

# Load NetCDF/NetCDF_Fortran libraries due to variable dropped from being
# called from makefile
add_library(NetCDF SHARED IMPORTED)
set_target_properties(NetCDF PROPERTIES
  IMPORTED_LOCATION $ENV{NetCDF_LIB_DIR}/libnetcdf.so
  INTERFACE_INCLUDE_DIRECTORIES $ENV{NetCDF_DIR}/include
)
add_library(NetCDF_Fortran SHARED IMPORTED)
set_target_properties(NetCDF_Fortran PROPERTIES
  IMPORTED_LOCATION $ENV{NetCDF_Fortran_DIR}/lib/libnetcdff.so
  INTERFACE_INCLUDE_DIRECTORIES $ENV{NetCDF_Fortran_DIR}/include
)

# Store template pFUnit test as BASE_MOM_PFUNIT_INFRA
file(REAL_PATH MOM_test_case.F90 BASE_MOM_PFUNIT_INFRA)

# Add path variable to config directory for use by tests in relative directories.
file(REAL_PATH config CONFIG_FILES)

add_subdirectory(interface)
