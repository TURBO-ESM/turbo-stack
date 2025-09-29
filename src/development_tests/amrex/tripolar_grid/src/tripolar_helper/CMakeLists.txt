# Tripolar Grid Library
add_library(tripolar_helper STATIC tripolar_grid.h tripolar_grid.cpp)
target_include_directories(tripolar_helper PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(tripolar_helper PUBLIC geometry grid field AMReX::amrex_3d HDF5::HDF5)

# Tripolar Helper Tests
add_executable(tripolar_helper_test tripolar_grid_test.cpp)
target_link_libraries(tripolar_helper_test PRIVATE tripolar_helper AMReX::amrex_3d HDF5::HDF5 testing_utils GTest::gtest_main)
gtest_discover_tests(tripolar_helper_test)