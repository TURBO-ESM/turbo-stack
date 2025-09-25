cmake_minimum_required(VERSION 3.20)

project(TURBO_AMREX_DEV_TESTS CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(AMReX REQUIRED)
#message(STATUS "AMReX_DIR: ${AMReX_DIR}")

find_package(GTest REQUIRED)
enable_testing()

find_package(HDF5 REQUIRED COMPONENTS C)

add_subdirectory(src)
add_subdirectory(examples)

