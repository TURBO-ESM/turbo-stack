cmake_minimum_required(VERSION 3.20)

project(TURBO_AMREX_DEV_TESTS CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)        # Disable compiler-specific extensions

###################################################
# Global CMake Setup
###################################################
find_package(AMReX REQUIRED)
#message(STATUS "AMReX_DIR: ${AMReX_DIR}")

find_package(GTest REQUIRED)
enable_testing()

find_package(HDF5 REQUIRED COMPONENTS C)

###############################################################################
# Example from AMReX Developers 
###############################################################################

set(AMREX_EXAMPLE_SOURCES
    main.cpp
)

add_executable(amrex_example_main ${AMREX_EXAMPLE_SOURCES})

target_sources(amrex_example_main PRIVATE ${AMREX_EXAMPLE_SOURCES})

target_link_libraries(amrex_example_main PUBLIC AMReX::amrex_3d)

###############################################################################
# Tripolar Grid Library
###############################################################################

add_library(tripolar_grid_lib STATIC
    tripolar_grid.cpp
    tripolar_grid.h
)

target_include_directories(tripolar_grid_lib PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(tripolar_grid_lib PUBLIC AMReX::amrex_3d HDF5::HDF5)

###############################################################################
# Tripolar Grid Tests
###############################################################################

add_executable(tripolar_grid_test tripolar_grid_test.cpp)
target_link_libraries(tripolar_grid_test PRIVATE tripolar_grid_lib GTest::gtest_main)
gtest_discover_tests(tripolar_grid_test)

###############################################################################
# Tripolar Grid Example
###############################################################################

add_executable(tripolar_grid example.cpp)
target_link_libraries(tripolar_grid PRIVATE tripolar_grid_lib)
