set(MOM6_DIAG_DIR ${MOM6_DIR}/src/diagnostics)

target_sources(mom6_ocean PRIVATE
    ${MOM6_DIAG_DIR}/MOM_PointAccel.F90
    ${MOM6_DIAG_DIR}/MOM_debugging.F90
    ${MOM6_DIAG_DIR}/MOM_diagnose_KdWork.F90
    ${MOM6_DIAG_DIR}/MOM_diagnose_MLD.F90
    ${MOM6_DIAG_DIR}/MOM_diagnostics.F90
    ${MOM6_DIAG_DIR}/MOM_harmonic_analysis.F90
    ${MOM6_DIAG_DIR}/MOM_obsolete_diagnostics.F90
    ${MOM6_DIAG_DIR}/MOM_obsolete_params.F90
    ${MOM6_DIAG_DIR}/MOM_spatial_means.F90
    ${MOM6_DIAG_DIR}/MOM_sum_output.F90
    ${MOM6_DIAG_DIR}/MOM_wave_speed.F90
)
