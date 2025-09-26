###############################################################################
# Example from AMReX Developers
###############################################################################
add_executable(example_from_amrex_developers example_from_amrex_developers.cpp)
target_link_libraries(example_from_amrex_developers PUBLIC AMReX::amrex_3d)


###############################################################################
# Tripolar Grid Helper Example
###############################################################################
add_executable(tripolar_grid_helper tripolar_grid_example.cpp)
target_link_libraries(tripolar_grid_helper PRIVATE geometry grid tripolar_helper AMReX::amrex_3d)

###############################################################################
# Mini-App Example
###############################################################################
add_executable(mini_app mini_app.cpp)
target_link_libraries(mini_app PRIVATE geometry grid field AMReX::amrex_3d)