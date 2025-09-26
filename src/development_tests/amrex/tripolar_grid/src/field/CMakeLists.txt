# Field Library
add_library(field STATIC field.h field.cpp)
target_include_directories(field PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(field PUBLIC geometry grid AMReX::amrex_3d HDF5::HDF5)

# Field Tests
add_executable(field_test field_test.cpp)
target_link_libraries(field_test PRIVATE geometry grid field AMReX::amrex_3d HDF5::HDF5 GTest::gtest_main)
gtest_discover_tests(field_test)