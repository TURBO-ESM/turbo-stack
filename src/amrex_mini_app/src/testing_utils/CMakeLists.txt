add_library(testing_utils INTERFACE)
target_include_directories(testing_utils INTERFACE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(testing_utils INTERFACE AMReX::amrex_3d)
