cmake_minimum_required(VERSION 3.24)
project(TurboStack LANGUAGES Fortran C CXX)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")

include(TurboOptions)
include(TurboCompilerFlags)

# FMS — provides FMS::fms_r8; transitively finds MPI and NetCDF
find_package(FMS REQUIRED COMPONENTS R8)

# FMS ships its own FindNetCDF.cmake; add it to the module path so the
# explicit find_package(NetCDF) below can locate it.
list(APPEND CMAKE_MODULE_PATH "${FMS_INSTALL_PREFIX}/lib/cmake/fms")

# MPI and NetCDF are found transitively by FMS but declared here explicitly
# so our own targets can link against them directly.
find_package(MPI REQUIRED COMPONENTS Fortran)
find_package(NetCDF REQUIRED COMPONENTS C Fortran)

add_subdirectory(mom6_build)
add_subdirectory(marbl_build)

if(TURBO_BUILD_UNIT_TESTS)
    find_package(PFUNIT REQUIRED)
    enable_testing()
    add_subdirectory(tests)
endif()
