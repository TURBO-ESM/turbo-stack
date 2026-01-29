cmake_minimum_required(VERSION 3.15)

project(TURBOUnitTests LANGUAGES Fortran)

enable_language(CXX C)

find_package(PFUNIT REQUIRED)
find_package(MPI REQUIRED)

# Required variables needed to be set by user.
set(INFRA "" CACHE STRING "High level name of infrastructure library to use for linking.")
set(PATH_TO_BACKEND_LIB "" CACHE STRING "Path to MOM6 backend library that conatins lib${INFRA}.a and needed *.mod files")
set(PATH_TO_LIBINFRA "" CACHE STRING "Path to MOM6 infra library that contains libinfra-${INFRA}.a and needed *.mod files")

# Check if required inputs are set.
if(NOT INFRA)
  message(FATAL_ERROR "INFRA not set.  Please reconfigure ${CMAKE_PROJECT_NAME} setting -DINFRA={FMS2,TIM}")
endif()
if(NOT PATH_TO_BACKEND_LIB)
  message(FATAL_ERROR "PATH_TO_BACKEND_LIB not set.  Please reconfigure ${CMAKE_PROJECT_NAME} setting -DPATH_TO_BACKEND_LIB=/path/to/backend_lib")
endif()
if(NOT PATH_TO_LIBINFRA)
  message(FATAL_ERROR "PATH_TO_LIBINFRA not set.  Please reconfigure ${CMAKE_PROJECT_NAME} setting -DPATH_TO_LIBINFRA=/path/to/libinfra")
endif()

message(STATUS "INFRA = ${INFRA}")
message(STATUS "PATH_TO_BACKEND_LIB = ${PATH_TO_BACKEND_LIB}")
message(STATUS "PATH_TO_LIBINFRA = ${PATH_TO_LIBINFRA}")

# Temporary fix to support NetCDF builds that don't support cmake.
message(STATUS "Detecting NetCDF install via find_package")
find_package(NetCDF QUIET COMPONENTS C Fortran)
if(NOT NetCDF_FOUND)
  message(STATUS "Unable to detect NetCDF install via find_package.  Re-trying with pkg-config.")
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
  IMPORTED_LOCATION ${PATH_TO_BACKEND_LIB}/lib${INFRA}.a
  INTERFACE_INCLUDE_DIRECTORIES ${PATH_TO_BACKEND_LIB}
)
add_library(BACKEND_Infra STATIC IMPORTED)
set_target_properties(BACKEND_Infra PROPERTIES
  IMPORTED_LOCATION ${PATH_TO_LIBINFRA}/libinfra-${INFRA}.a
  INTERFACE_INCLUDE_DIRECTORIES ${PATH_TO_LIBINFRA}
)

# Store template pFUnit test as BASE_MOM_PFUNIT_INFRA
file(REAL_PATH MOM_test_case.F90 BASE_MOM_PFUNIT_INFRA)

# Add path variable to config directory for use by tests in relative directories.
file(REAL_PATH config CONFIG_FILES)

add_subdirectory(interface)
