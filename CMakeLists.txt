cmake_minimum_required(VERSION 3.24)
project(TurboStack LANGUAGES Fortran C CXX)

include(cmake/TurboOptions.cmake)

# FMS — provides FMS::fms_r8; transitively finds MPI and NetCDF
find_package(FMS REQUIRED COMPONENTS R8)

# FMS ships its own FindNetCDF.cmake; add it to the module path so the
# explicit find_package(NetCDF) below can locate it.
list(APPEND CMAKE_MODULE_PATH "${FMS_INSTALL_PREFIX}/lib/cmake/fms")

# MPI and NetCDF are found transitively by FMS but declared here explicitly
# so our own targets can link against them directly.
find_package(MPI REQUIRED COMPONENTS Fortran)
find_package(NetCDF REQUIRED COMPONENTS C Fortran)

# pFUnit — unit testing framework
find_package(PFUNIT REQUIRED)
