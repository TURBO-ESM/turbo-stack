cmake_minimum_required(VERSION 3.15)

project(TURBOUnitTests LANGUAGES Fortran)

enable_language(CXX C)

find_package(PFUNIT REQUIRED)

# Required variables needed to be set by user.
set(INFRA "" CACHE STRING "High level name of infrastructure library to use for linking.")
set(PATH_TO_BACKEND_LIB "" CACHE STRING "Path to MOM6 backend library that conatins lib${INFRA}.a and needed *.mod files")
set(PATH_TO_LIBINFRA "" CACHE STRING "Path to MOM6 infra library that contains libinfra-${INFRA}.a and needed *.mod files")

# Check if required variables are set.
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

# Offload finding of external dependencies to generate MOM::* targets
include(cmake/find_mom_dependencies.cmake)
find_mom_dependencies(INFRA_TYPE ${INFRA}
                      BACKEND_PATH ${PATH_TO_BACKEND_LIB}
                      INFRA_PATH ${PATH_TO_LIBINFRA})

# Store template pFUnit test as BASE_MOM_PFUNIT_INFRA
file(REAL_PATH MOM_test_case.F90 BASE_MOM_PFUNIT_INFRA)

# Add path variable to config directory for use by tests in relative directories.
file(REAL_PATH config CONFIG_FILES)

enable_testing()
include(cmake/add_mom_test.cmake)
add_subdirectory(interface)
