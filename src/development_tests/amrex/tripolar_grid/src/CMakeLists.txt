add_subdirectory(geometry)
add_subdirectory(grid)

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