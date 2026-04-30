set(MOM6_CORE_DIR ${MOM6_DIR}/src/core)

# Remaining core files (MOM_grid and MOM_verticalGrid are in mom6_grid above).
target_sources(mom6_ocean PRIVATE
    ${MOM6_CORE_DIR}/MOM.F90
    ${MOM6_CORE_DIR}/MOM_CoriolisAdv.F90
    ${MOM6_CORE_DIR}/MOM_PressureForce.F90
    ${MOM6_CORE_DIR}/MOM_PressureForce_FV.F90
    ${MOM6_CORE_DIR}/MOM_PressureForce_Montgomery.F90
    ${MOM6_CORE_DIR}/MOM_barotropic.F90
    ${MOM6_CORE_DIR}/MOM_boundary_update.F90
    ${MOM6_CORE_DIR}/MOM_check_scaling.F90
    ${MOM6_CORE_DIR}/MOM_checksum_packages.F90
    ${MOM6_CORE_DIR}/MOM_continuity.F90
    ${MOM6_CORE_DIR}/MOM_continuity_PPM.F90
    ${MOM6_CORE_DIR}/MOM_density_integrals.F90
    ${MOM6_CORE_DIR}/MOM_dynamics_split_RK2.F90
    ${MOM6_CORE_DIR}/MOM_dynamics_split_RK2b.F90
    ${MOM6_CORE_DIR}/MOM_dynamics_unsplit.F90
    ${MOM6_CORE_DIR}/MOM_dynamics_unsplit_RK2.F90
    ${MOM6_CORE_DIR}/MOM_forcing_type.F90
    ${MOM6_CORE_DIR}/MOM_interface_heights.F90
    ${MOM6_CORE_DIR}/MOM_isopycnal_slopes.F90
    ${MOM6_CORE_DIR}/MOM_open_boundary.F90
    ${MOM6_CORE_DIR}/MOM_porous_barriers.F90
    ${MOM6_CORE_DIR}/MOM_stoch_eos.F90
    ${MOM6_CORE_DIR}/MOM_transcribe_grid.F90
    ${MOM6_CORE_DIR}/MOM_unit_tests.F90
    ${MOM6_CORE_DIR}/MOM_variables.F90
)

# Layer 4 (mom6_grid): MOM_grid and MOM_verticalGrid.
# These are the minimal src/core/ files needed to complete the framework layer.
# MOM_io (Layer 5, in src/framework/) needs them; they in turn only need
# mom6_framework (Layer 3), so they sit between framework and io.
#
# All deps are already in mom6_framework:
#   MOM_grid         needs MOM_domains, MOM_error_handler, MOM_file_parser,
#                    MOM_hor_index, MOM_unit_scaling
#   MOM_verticalGrid needs MOM_domains, MOM_error_handler, MOM_file_parser,
#                    MOM_hor_index, MOM_unit_scaling
add_library(mom6_grid STATIC
    ${MOM6_CORE_DIR}/MOM_grid.F90
    ${MOM6_CORE_DIR}/MOM_verticalGrid.F90
)
add_library(MOM6::grid ALIAS mom6_grid)

set_target_properties(mom6_grid PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod
)

target_include_directories(mom6_grid
    INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>
)

target_include_directories(mom6_grid
    PRIVATE ${MOM6_DIR}/config_src/memory/${TURBO_MEMORY_MODE}
)

target_link_libraries(mom6_grid
    PUBLIC MOM6::framework
)
