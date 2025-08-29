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
# Tripolar Grid Main Application
###############################################################################

set(TRIPOLAR_GRID_SOURCES
    main.cpp
)

add_executable(tripolar_grid ${TRIPOLAR_GRID_SOURCES})

target_sources(tripolar_grid PRIVATE ${TRIPOLAR_GRID_SOURCES})

target_link_libraries(tripolar_grid PUBLIC AMReX::amrex_3d)

###############################################################################
# Tripolar Grid Tests
###############################################################################

set(TRIPOLAR_GRID_TEST_SOURCES
    tripolar_grid_test.cpp
    tripolar_grid.cpp
)

add_executable(tripolar_grid_test ${TRIPOLAR_GRID_TEST_SOURCES})

target_include_directories(tripolar_grid_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# Link against the AMReX library
target_sources(tripolar_grid_test PRIVATE ${TRIPOLAR_GRID_TEST_SOURCES})
target_link_libraries(tripolar_grid_test AMReX::amrex_3d)

# Google Test setup
target_link_libraries(tripolar_grid_test GTest::gtest_main)
gtest_discover_tests(tripolar_grid_test)

# Link against HDF5
target_link_libraries(tripolar_grid_test HDF5::HDF5)