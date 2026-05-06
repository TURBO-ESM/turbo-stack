cmake_minimum_required(VERSION 3.24)
project(TurboStack LANGUAGES Fortran C CXX)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")

include(TurboOptions)
include(TurboCompilerFlags)

# Infrastructure backend — FMS2 (Spack-installed) or TIM (in-tree build).
# Both paths end with FMS::fms_r8 defined; nothing downstream needs to change.
if(TURBO_INFRA STREQUAL "FMS2")
    find_package(FMS REQUIRED COMPONENTS R8)
    # FMS ships its own FindNetCDF.cmake; expose it for the explicit find below.
    list(APPEND CMAKE_MODULE_PATH "${FMS_INSTALL_PREFIX}/lib/cmake/fms")
elseif(TURBO_INFRA STREQUAL "TIM")
    # TIM_SOURCE_DIR: prefer -DTIM_SOURCE_DIR=, fall back to $TIM_ROOT env var.
    if(NOT DEFINED TIM_SOURCE_DIR)
        set(TIM_SOURCE_DIR "$ENV{TIM_ROOT}" CACHE PATH "Path to TIM source directory")
    endif()
    if(NOT TIM_SOURCE_DIR)
        message(FATAL_ERROR
            "TURBO_INFRA=TIM requires TIM_ROOT to be set in the environment "
            "(or pass -DTIM_SOURCE_DIR=/path/to/TIM)")
    endif()
    list(PREPEND CMAKE_MODULE_PATH "${TIM_SOURCE_DIR}/cmake")
    set(32BIT OFF CACHE BOOL "" FORCE)
    set(64BIT ON  CACHE BOOL "" FORCE)
    add_subdirectory("${TIM_SOURCE_DIR}" tim_build)
    # TIM exports TIM::tim_r8; alias it so downstream targets are infra-agnostic.
    add_library(FMS::fms_r8 ALIAS tim_r8)
else()
    message(FATAL_ERROR "Unknown TURBO_INFRA='${TURBO_INFRA}'. Valid values: FMS2, TIM")
endif()

# MPI and NetCDF are found transitively by FMS/TIM but declared explicitly
# so our own targets can link against them directly.
find_package(MPI REQUIRED COMPONENTS Fortran)
find_package(NetCDF REQUIRED COMPONENTS C Fortran)

# MOM6_SOURCE_DIR: path to a standalone MOM6 source checkout.
# Reads $MOM6_ROOT env var; fails loudly at configure time if unset.
if(NOT DEFINED MOM6_SOURCE_DIR)
    set(MOM6_SOURCE_DIR "$ENV{MOM6_ROOT}" CACHE PATH "Path to MOM6 source directory")
endif()
if(NOT MOM6_SOURCE_DIR)
    message(FATAL_ERROR
        "TurboStack requires MOM6_ROOT to be set in the environment "
        "(or pass -DMOM6_SOURCE_DIR=/path/to/MOM6)")
endif()

# MARBL must be configured before MOM6 so that MOM6::MARBL is already defined
# when the MOM6 subdirectory processes its target_link_libraries calls.
add_subdirectory(marbl_build)
add_subdirectory("${MOM6_SOURCE_DIR}" mom6_build)

if(TURBO_BUILD_UNIT_TESTS)
    find_package(PFUNIT REQUIRED)
    enable_testing()
    add_subdirectory(tests)
endif()
