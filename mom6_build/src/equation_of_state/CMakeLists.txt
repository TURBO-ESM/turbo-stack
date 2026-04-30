set(MOM6_EOS_DIR ${MOM6_DIR}/src/equation_of_state)

target_sources(mom6_ocean PRIVATE
    ${MOM6_EOS_DIR}/MOM_EOS.F90
    ${MOM6_EOS_DIR}/MOM_EOS_Jackett06.F90
    ${MOM6_EOS_DIR}/MOM_EOS_Roquet_SpV.F90
    ${MOM6_EOS_DIR}/MOM_EOS_Roquet_rho.F90
    ${MOM6_EOS_DIR}/MOM_EOS_TEOS10.F90
    ${MOM6_EOS_DIR}/MOM_EOS_UNESCO.F90
    ${MOM6_EOS_DIR}/MOM_EOS_Wright.F90
    ${MOM6_EOS_DIR}/MOM_EOS_Wright_full.F90
    ${MOM6_EOS_DIR}/MOM_EOS_Wright_red.F90
    ${MOM6_EOS_DIR}/MOM_EOS_base_type.F90
    ${MOM6_EOS_DIR}/MOM_EOS_linear.F90
    ${MOM6_EOS_DIR}/MOM_TFreeze.F90
    ${MOM6_EOS_DIR}/MOM_temperature_convert.F90
)
