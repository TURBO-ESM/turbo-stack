cmake_minimum_required(VERSION 3.20)

project(TURBO_AMREX_DEV_TESTS CXX C)

find_package(AMReX REQUIRED)

message(STATUS "AMReX_DIR: ${AMReX_DIR}")

###################################################

set(TRIPOLAR_GRID_SOURCES
    main.cpp
)

add_executable(tripolar_grid ${TRIPOLAR_GRID_SOURCES})

target_sources(tripolar_grid PRIVATE ${TRIPOLAR_GRID_SOURCES})

target_link_libraries(tripolar_grid PUBLIC AMReX::amrex_3d)