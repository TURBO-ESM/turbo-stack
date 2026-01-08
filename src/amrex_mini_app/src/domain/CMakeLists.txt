# Domain Library
add_library(domain STATIC domain.h domain.cpp cartesian_domain.h cartesian_domain.cpp)
target_include_directories(domain PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(domain PUBLIC geometry grid field AMReX::amrex_3d HDF5::HDF5)

# Domain Tests
add_gtest(cartesian_domain_test.cpp domain geometry grid field AMReX::amrex_3d HDF5::HDF5)