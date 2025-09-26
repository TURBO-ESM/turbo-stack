# Grid Library
add_library(grid INTERFACE)
target_include_directories(grid INTERFACE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(grid INTERFACE geometry HDF5::HDF5)

# Grid Tests
add_executable(grid_test grid_test.cpp)
target_link_libraries(grid_test grid GTest::gtest_main)
gtest_discover_tests(grid_test)