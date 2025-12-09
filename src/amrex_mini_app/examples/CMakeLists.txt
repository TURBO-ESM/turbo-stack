###############################################################################
# Example from AMReX Developers
###############################################################################
add_executable(example_from_amrex_developers example_from_amrex_developers.cpp)
target_link_libraries(example_from_amrex_developers PRIVATE AMReX::amrex_3d)


###############################################################################
# Mini-App Example
###############################################################################
add_executable(mini_app mini_app.cpp)
target_link_libraries(mini_app PRIVATE geometry grid field AMReX::amrex_3d)

###############################################################################
# Initialization mini-App Example
###############################################################################
add_executable(initialization_mini_app initialization_mini_app.cpp)
target_link_libraries(initialization_mini_app PRIVATE geometry grid field AMReX::amrex_3d hdf5::hdf5)

###############################################################################
# Domain Example
###############################################################################

add_executable(domain_example domain_example.cpp)
target_link_libraries(domain_example PRIVATE geometry grid field domain AMReX::amrex_3d)