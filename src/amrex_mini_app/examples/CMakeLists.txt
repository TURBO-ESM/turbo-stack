###############################################################################
# Example from AMReX Developers
###############################################################################
add_executable(example_from_amrex_developers example_from_amrex_developers.cpp)
target_link_libraries(example_from_amrex_developers PRIVATE AMReX::amrex_3d)

###############################################################################
# Domain Example
###############################################################################
add_executable(domain_example domain_example.cpp)
target_link_libraries(domain_example PRIVATE geometry grid field domain AMReX::amrex_3d)