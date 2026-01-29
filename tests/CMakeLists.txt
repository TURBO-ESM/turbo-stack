cmake_minimum_required(VERSION 3.15)

project(TURBOUnitTests LANGUAGES Fortran)

enable_language(CXX C)

find_package(PFUNIT REQUIRED)
find_package(MPI REQUIRED)

# Temporary fix to support NetCDF builds that don't support cmake.
find_package(NetCDF COMPONENTS C Fortran)
if(NOT NetCDF_FOUND)
  find_package(PkgConfig REQUIRED)

  ## Most older installs of NetCDF usually have a pkgconfig directory with .pc files
  pkg_search_module(NetCDF_C REQUIRED IMPORTED_TARGET netcdf)
  # Add an alias to match the official NetCDF CMake target.  This allows for linking
  # against the same target without changing the source code.
  add_library(NetCDF::NetCDF_C ALIAS PkgConfig::NetCDF_C)

  pkg_search_module(NetCDF_Fortran REQUIRED IMPORTED_TARGET netcdf-fortran)
  add_library(NetCDF::NetCDF_Fortran ALIAS PkgConfig::NetCDF_Fortran)
endif()

# Only set AMREX_LIB if needed; else keep undefined
if("$ENV{INFRA}" STREQUAL "TIM")
  find_package(AMReX REQUIRED)
  set(AMREX_LIB AMReX::amrex)
endif()

include(cmake/add_mom_test.cmake)

enable_testing()

# Load external dependencies not provided by cmake modules.
add_library(BACKEND_lib STATIC IMPORTED)
set_target_properties(BACKEND_lib PROPERTIES
  IMPORTED_LOCATION $ENV{BLD_PATH}/$ENV{INFRA}/lib$ENV{INFRA}.a
  INTERFACE_INCLUDE_DIRECTORIES $ENV{BLD_PATH}/FMS
)
add_library(BACKEND_Infra STATIC IMPORTED)
set_target_properties(BACKEND_Infra PROPERTIES
  IMPORTED_LOCATION $ENV{BLD_PATH}/MOM6-infra/libinfra-$ENV{INFRA}.a
  INTERFACE_INCLUDE_DIRECTORIES $ENV{BLD_PATH}/MOM6-infra
)

# Store template pFUnit test as BASE_MOM_PFUNIT_INFRA
file(REAL_PATH MOM_test_case.F90 BASE_MOM_PFUNIT_INFRA)

# Add path variable to config directory for use by tests in relative directories.
file(REAL_PATH config CONFIG_FILES)

add_subdirectory(interface)
