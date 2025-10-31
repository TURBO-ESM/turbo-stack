# Geometry library
add_library(geometry INTERFACE)
target_include_directories(geometry INTERFACE ${CMAKE_CURRENT_SOURCE_DIR})

# Geometry Tests
add_gtest(geometry_test.cpp geometry)