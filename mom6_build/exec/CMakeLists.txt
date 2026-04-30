set(MOM6_DRIVER_DIR ${MOM6_DIR}/config_src/drivers/solo_driver)

add_executable(MOM6
    ${MOM6_DRIVER_DIR}/MOM_driver.F90
    ${MOM6_DRIVER_DIR}/MOM_surface_forcing.F90
    ${MOM6_DRIVER_DIR}/MESO_surface_forcing.F90
    ${MOM6_DRIVER_DIR}/atmos_ocean_fluxes.F90
    ${MOM6_DRIVER_DIR}/user_surface_forcing.F90
)

target_include_directories(MOM6
    PRIVATE ${MOM6_DIR}/config_src/memory/${TURBO_MEMORY_MODE}
)

target_link_libraries(MOM6
    PRIVATE MOM6::ocean
)
