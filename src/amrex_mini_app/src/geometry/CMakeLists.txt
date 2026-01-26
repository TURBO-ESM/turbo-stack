# Geometry library
add_library(geometry STATIC geometry.h cartesian_geometry.h cartesian_geometry.cpp)
target_include_directories(geometry PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

# Geometry Tests
add_gtest(cartesian_geometry_test.cpp geometry)
