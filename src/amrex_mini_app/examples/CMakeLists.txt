###############################################################################
# Example from AMReX Developers 
###############################################################################

set(AMREX_EXAMPLE_SOURCES
    example_from_amrex_developers.cpp
)

add_executable(amrex_example_main ${AMREX_EXAMPLE_SOURCES})

target_sources(amrex_example_main PRIVATE ${AMREX_EXAMPLE_SOURCES})

target_link_libraries(amrex_example_main PUBLIC AMReX::amrex_3d)


###############################################################################
# Tripolar Grid Example
###############################################################################

add_executable(tripolar_grid tripolar_grid_example.cpp)
target_link_libraries(tripolar_grid PRIVATE tripolar_grid_lib AMReX::amrex_3d)