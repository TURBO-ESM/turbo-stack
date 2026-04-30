set(MOM6_SRC ${MOM6_DIR}/src)
set(MOM6_EXT ${MOM6_DIR}/config_src/external)

# mom6_ocean: all MOM6 src/ files not already in the framework/grid/io/infra targets,
# plus config_src/external/ stubs (MARBL excluded — provided by MOM6::MARBL).
add_library(mom6_ocean STATIC)
add_library(MOM6::ocean ALIAS mom6_ocean)

set_target_properties(mom6_ocean PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod
)
target_include_directories(mom6_ocean
    INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>
    PRIVATE   ${MOM6_DIR}/config_src/memory/${TURBO_MEMORY_MODE}
)
target_link_libraries(mom6_ocean
    PUBLIC MOM6::io MOM6::grid MOM6::CVMix MOM6::GSW MOM6::MARBL
)

# 3 framework files deferred from Phase 3; they need EOS/core deps now in mom6_ocean.
target_sources(mom6_ocean PRIVATE
    ${MOM6_SRC}/framework/MOM_diag_mediator.F90
    ${MOM6_SRC}/framework/MOM_diag_remap.F90
    ${MOM6_SRC}/framework/MOM_horizontal_regridding.F90
)

# External stubs (MARBL excluded — provided by MOM6::MARBL).
target_sources(mom6_ocean PRIVATE
    ${MOM6_EXT}/GFDL_ocean_BGC/FMS_coupler_util.F90
    ${MOM6_EXT}/GFDL_ocean_BGC/MOM_generic_tracer.F90
    ${MOM6_EXT}/GFDL_ocean_BGC/generic_tracer.F90
    ${MOM6_EXT}/GFDL_ocean_BGC/generic_tracer_utils.F90
    ${MOM6_EXT}/ODA_hooks/kdtree.f90
    ${MOM6_EXT}/ODA_hooks/ocean_da_core.F90
    ${MOM6_EXT}/ODA_hooks/ocean_da_types.F90
    ${MOM6_EXT}/ODA_hooks/write_ocean_obs.F90
    ${MOM6_EXT}/database_comms/MOM_database_comms.F90
    ${MOM6_EXT}/database_comms/database_client_interface.F90
    ${MOM6_EXT}/drifters/MOM_particles.F90
    ${MOM6_EXT}/drifters/MOM_particles_types.F90
    ${MOM6_EXT}/stochastic_physics/get_stochy_pattern.F90
    ${MOM6_EXT}/stochastic_physics/stochastic_physics.F90
)

# core must come before framework so mom6_grid is defined before mom6_io.
add_subdirectory(core)
add_subdirectory(framework)
add_subdirectory(ALE)
add_subdirectory(diagnostics)
add_subdirectory(equation_of_state)
add_subdirectory(ice_shelf)
add_subdirectory(initialization)
add_subdirectory(ocean_data_assim)
add_subdirectory(parameterizations)
add_subdirectory(tracer)
add_subdirectory(user)
