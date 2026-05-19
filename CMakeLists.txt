cmake_minimum_required(VERSION 3.24)
project(TurboStack LANGUAGES Fortran C CXX)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")

# fms-config.cmake / tim-config.cmake both call find_dependency(NetCDF). Most
# NetCDF installs (incl. the Derecho spack module) ship no NetCDFConfig.cmake —
# only nc-config — so a FindNetCDF.cmake must be on CMAKE_MODULE_PATH *before*
# find_package(FMS|TIM). The FMS submodule ships one; use it as the canonical
# source (TIM ships an identical copy).
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/submodules/infra/FMS2/cmake")

# MOM6_SOURCE_DIR must be resolved before including MOM6Options (which sets
# TURBO_INFRA and TURBO_MEMORY_MODE — the canonical definitions for both repos).
if(NOT DEFINED MOM6_SOURCE_DIR)
    set(MOM6_SOURCE_DIR "$ENV{MOM6_ROOT}" CACHE PATH "Path to MOM6 source directory")
endif()
if(NOT MOM6_SOURCE_DIR)
    message(FATAL_ERROR
        "TurboStack requires MOM6_ROOT to be set in the environment "
        "(or pass -DMOM6_SOURCE_DIR=/path/to/MOM6)")
endif()

include(TurboOptions)
include("${MOM6_SOURCE_DIR}/cmake/MOM6Options.cmake")
include(TurboCompilerFlags)

# Infrastructure backend — FMS2 or TIM.  Both come from CMAKE_PREFIX_PATH
# (populated either by spack env activate or by build_dependencies_from_source.sh).
# Both paths define TURBO::infra_r8; nothing downstream needs to know which backend.
if(TURBO_INFRA STREQUAL "FMS2")
    find_package(FMS REQUIRED COMPONENTS R8)
    add_library(turbo_infra_r8 INTERFACE)
    add_library(TURBO::infra_r8 ALIAS turbo_infra_r8)
    target_link_libraries(turbo_infra_r8 INTERFACE FMS::fms_r8)
elseif(TURBO_INFRA STREQUAL "TIM")
    # TIM is built+installed by scripts/build_dependencies_from_source.sh into
    # deps/<tag>/install (or by spack, in principle, though spack does not
    # currently package TIM). find_package(TIM) resolves via CMAKE_PREFIX_PATH.
    find_package(TIM REQUIRED COMPONENTS R8)
    add_library(turbo_infra_r8 INTERFACE)
    add_library(TURBO::infra_r8 ALIAS turbo_infra_r8)
    target_link_libraries(turbo_infra_r8 INTERFACE TIM::tim_r8)
else()
    message(FATAL_ERROR "Unknown TURBO_INFRA='${TURBO_INFRA}'. Valid values: FMS2, TIM")
endif()

# MPI and NetCDF are found transitively by FMS/TIM but declared explicitly
# so our own targets can link against them directly.
find_package(MPI REQUIRED COMPONENTS Fortran)
find_package(NetCDF REQUIRED COMPONENTS C Fortran)

# Attach NetCDF::NetCDF_C to the infra wrapper so its absolute libnetcdf.so
# path lands on every link line that uses TURBO::infra_r8. FMS::fms_r8 only
# carries NetCDF::NetCDF_Fortran in its INTERFACE_LINK_LIBRARIES, plus bare
# `-lnetcdf` flags from nf-config --flibs; on NetCDF installs with split
# lib/lib64 layouts (e.g. NCAR's Derecho module) the bare flag fails to
# resolve at link time. Explicit attachment makes the dependency truthful
# regardless of upstream FMS / infra layout choices.
target_link_libraries(turbo_infra_r8 INTERFACE NetCDF::NetCDF_C)

# MARBL must be configured before MOM6 so that MARBL::marbl is already defined
# when the MOM6 subdirectory processes its target_link_libraries calls.
add_subdirectory(marbl_build)
add_subdirectory("${MOM6_SOURCE_DIR}" mom6_build)

if(TURBO_BUILD_UNIT_TESTS)
    find_package(PFUNIT REQUIRED)
    enable_testing()
    add_subdirectory(tests)
endif()
