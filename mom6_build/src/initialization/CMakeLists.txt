set(MOM6_INIT_DIR ${MOM6_DIR}/src/initialization)

target_sources(mom6_ocean PRIVATE
    ${MOM6_INIT_DIR}/MOM_coord_initialization.F90
    ${MOM6_INIT_DIR}/MOM_fixed_initialization.F90
    ${MOM6_INIT_DIR}/MOM_grid_initialize.F90
    ${MOM6_INIT_DIR}/MOM_shared_initialization.F90
    ${MOM6_INIT_DIR}/MOM_state_initialization.F90
    ${MOM6_INIT_DIR}/MOM_tracer_initialization_from_Z.F90
)
