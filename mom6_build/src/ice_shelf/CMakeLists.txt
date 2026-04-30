set(MOM6_ICE_DIR ${MOM6_DIR}/src/ice_shelf)

target_sources(mom6_ocean PRIVATE
    ${MOM6_ICE_DIR}/MOM_ice_shelf.F90
    ${MOM6_ICE_DIR}/MOM_ice_shelf_diag_mediator.F90
    ${MOM6_ICE_DIR}/MOM_ice_shelf_dynamics.F90
    ${MOM6_ICE_DIR}/MOM_ice_shelf_initialize.F90
    ${MOM6_ICE_DIR}/MOM_ice_shelf_state.F90
    ${MOM6_ICE_DIR}/MOM_marine_ice.F90
    ${MOM6_ICE_DIR}/user_shelf_init.F90
)
