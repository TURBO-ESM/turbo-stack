set(MOM6_ODA_DIR ${MOM6_DIR}/src/ocean_data_assim)

target_sources(mom6_ocean PRIVATE
    ${MOM6_ODA_DIR}/MOM_oda_driver.F90
    ${MOM6_ODA_DIR}/MOM_oda_incupd.F90
)
