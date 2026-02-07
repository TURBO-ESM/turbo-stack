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

# Enable code coverage flags if requested
option(CODE_COVERAGE "Enable code coverage flags" OFF)
if(CODE_COVERAGE)
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
        message(STATUS "Code coverage for GNU compiler enabled")
        add_compile_options(--coverage)
        add_link_options(--coverage)
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        message(STATUS "Code coverage for Clang compiler enabled")
        add_compile_options(-fprofile-instr-generate -fcoverage-mapping)
        add_link_options(-fprofile-instr-generate -fcoverage-mapping)
    else()
        message(WARNING "Code coverage only supported for GCC and Clang, not ${CMAKE_CXX_COMPILER_ID}.")
    endif()
endif()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
include(GTestHelpers)

add_subdirectory(src)
add_subdirectory(examples)

