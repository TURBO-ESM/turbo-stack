set(MARBL_SRC_DIR ${MARBL_DIR}/src)

add_library(mom6_marbl STATIC
    ${MARBL_SRC_DIR}/marbl_kinds_mod.F90
    ${MARBL_SRC_DIR}/marbl_constants_mod.F90
    ${MARBL_SRC_DIR}/marbl_utils_mod.F90
    ${MARBL_SRC_DIR}/marbl_logging.F90
    ${MARBL_SRC_DIR}/marbl_debug_mod.F90
    ${MARBL_SRC_DIR}/marbl_timing_mod.F90
    ${MARBL_SRC_DIR}/marbl_interface_constants.F90
    ${MARBL_SRC_DIR}/marbl_interface_public_types.F90
    ${MARBL_SRC_DIR}/marbl_interface_private_types.F90
    ${MARBL_SRC_DIR}/marbl_diagnostics_share_mod.F90
    ${MARBL_SRC_DIR}/marbl_interior_tendency_share_mod.F90
    ${MARBL_SRC_DIR}/marbl_surface_flux_share_mod.F90
    ${MARBL_SRC_DIR}/marbl_saved_state_mod.F90
    ${MARBL_SRC_DIR}/marbl_settings_mod.F90
    ${MARBL_SRC_DIR}/marbl_pft_mod.F90
    ${MARBL_SRC_DIR}/marbl_glo_avg_mod.F90
    ${MARBL_SRC_DIR}/marbl_oxygen.F90
    ${MARBL_SRC_DIR}/marbl_temperature.F90
    ${MARBL_SRC_DIR}/marbl_schmidt_number_mod.F90
    ${MARBL_SRC_DIR}/marbl_co2calc_mod.F90
    ${MARBL_SRC_DIR}/marbl_nhx_surface_emis_mod.F90
    ${MARBL_SRC_DIR}/marbl_diagnostics_mod.F90
    ${MARBL_SRC_DIR}/marbl_init_tracer_metadata_mod.F90
    ${MARBL_SRC_DIR}/marbl_abio_dic_diagnostics_mod.F90
    ${MARBL_SRC_DIR}/marbl_ciso_diagnostics_mod.F90
    ${MARBL_SRC_DIR}/marbl_abio_dic_interior_tendency_mod.F90
    ${MARBL_SRC_DIR}/marbl_abio_dic_surface_flux_mod.F90
    ${MARBL_SRC_DIR}/marbl_ciso_interior_tendency_mod.F90
    ${MARBL_SRC_DIR}/marbl_ciso_surface_flux_mod.F90
    ${MARBL_SRC_DIR}/marbl_interior_tendency_mod.F90
    ${MARBL_SRC_DIR}/marbl_surface_flux_mod.F90
    ${MARBL_SRC_DIR}/marbl_restore_mod.F90
    ${MARBL_SRC_DIR}/marbl_init_mod.F90
    ${MARBL_SRC_DIR}/marbl_interface.F90
)
add_library(MOM6::MARBL ALIAS mom6_marbl)

set_target_properties(mom6_marbl PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod
)

target_include_directories(mom6_marbl
    INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>
)
