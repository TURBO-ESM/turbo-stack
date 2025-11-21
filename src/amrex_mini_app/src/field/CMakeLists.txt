# Field Library
add_library(field STATIC field.cpp field_container.cpp)
target_include_directories(field PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(field PUBLIC geometry grid AMReX::amrex_3d HDF5::HDF5)

# Field Tests
add_gtest(field_test.cpp geometry grid field AMReX::amrex_3d HDF5::HDF5)

# Field Container Tests
add_gtest(field_container_test.cpp geometry grid field)