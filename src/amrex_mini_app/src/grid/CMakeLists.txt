# Grid Library (for now just one that contains the base grid class and the specific cartesian grid implementation)

add_library(grid STATIC cartesian_grid.cpp)
target_include_directories(grid PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(grid PUBLIC geometry HDF5::HDF5)

# Grid Tests
add_gtest(cartesian_grid_test.cpp geometry grid)