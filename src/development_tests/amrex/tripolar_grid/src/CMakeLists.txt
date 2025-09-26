###############################################################################
# Geometry Tests
###############################################################################

add_executable(geometry_test geometry_test.cpp geometry.h)
target_link_libraries(geometry_test GTest::gtest_main)

gtest_discover_tests(geometry_test)

###############################################################################
# Grid Library
###############################################################################

add_library(grid_lib INTERFACE)
target_include_directories(grid_lib INTERFACE ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(grid_lib INTERFACE HDF5::HDF5)

###############################################################################
# Grid Tests
###############################################################################
add_executable(grid_test grid_test.cpp geometry.h grid.h)
target_link_libraries(grid_test PRIVATE grid_lib GTest::gtest_main)

gtest_discover_tests(grid_test)

###############################################################################
# Field Library
###############################################################################

add_library(field_lib STATIC
    field.cpp
    field.h
    grid.h
)

target_include_directories(field_lib PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(field_lib PUBLIC AMReX::amrex_3d HDF5::HDF5)

###############################################################################
# Field Tests
###############################################################################

add_executable(field_test field_test.cpp field.h field.cpp geometry.h grid.h)
target_link_libraries(field_test PRIVATE GTest::gtest_main)
target_link_libraries(field_test PUBLIC AMReX::amrex_3d HDF5::HDF5)

gtest_discover_tests(field_test)

###############################################################################
# Tripolar Grid Library
###############################################################################

add_library(tripolar_grid_lib STATIC
    tripolar_grid.cpp
    tripolar_grid.h
    field.cpp
    field.h
)

target_include_directories(tripolar_grid_lib PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(tripolar_grid_lib PUBLIC AMReX::amrex_3d HDF5::HDF5)


###############################################################################
# Tripolar Grid Tests
###############################################################################

add_executable(tripolar_grid_test tripolar_grid_test.cpp)
target_link_libraries(tripolar_grid_test PRIVATE tripolar_grid_lib GTest::gtest_main)

gtest_discover_tests(tripolar_grid_test)