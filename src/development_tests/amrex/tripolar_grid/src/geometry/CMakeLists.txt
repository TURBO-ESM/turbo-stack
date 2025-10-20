# Geometry library
add_library(geometry INTERFACE)
target_include_directories(geometry INTERFACE ${CMAKE_CURRENT_SOURCE_DIR})

# Geometry Tests
add_executable(geometry_test geometry_test.cpp)
target_link_libraries(geometry_test geometry GTest::gtest_main)
gtest_discover_tests(geometry_test)