###############################################################################
# Example from AMReX Developers
###############################################################################
add_executable(example_from_amrex_developers example_from_amrex_developers.cpp)
target_link_libraries(example_from_amrex_developers PRIVATE AMReX::amrex_3d)

###############################################################################
# Tripolar Grid Example
###############################################################################

add_executable(tripolar_grid_example tripolar_grid_example.cpp)
target_link_libraries(tripolar_grid_example PRIVATE geometry grid field tripolar_helper AMReX::amrex_3d)

###############################################################################
# Mini-App Example
###############################################################################
add_executable(mini_app mini_app.cpp)
target_link_libraries(mini_app PRIVATE geometry grid field AMReX::amrex_3d)
