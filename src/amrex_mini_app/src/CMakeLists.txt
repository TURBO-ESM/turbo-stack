add_subdirectory(geometry)
add_subdirectory(grid)
add_subdirectory(field)
add_subdirectory(testing_utils)

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

add_gtest(tripolar_grid_test.cpp tripolar_grid_lib)