set(MOM6_TRACER_DIR ${MOM6_DIR}/src/tracer)

target_sources(mom6_ocean PRIVATE
    ${MOM6_TRACER_DIR}/DOME_tracer.F90
    ${MOM6_TRACER_DIR}/ISOMIP_tracer.F90
    ${MOM6_TRACER_DIR}/MARBL_forcing_mod.F90
    ${MOM6_TRACER_DIR}/MARBL_tracers.F90
    ${MOM6_TRACER_DIR}/MOM_CFC_cap.F90
    ${MOM6_TRACER_DIR}/MOM_OCMIP2_CFC.F90
    ${MOM6_TRACER_DIR}/MOM_hor_bnd_diffusion.F90
    ${MOM6_TRACER_DIR}/MOM_neutral_diffusion.F90
    ${MOM6_TRACER_DIR}/MOM_offline_aux.F90
    ${MOM6_TRACER_DIR}/MOM_offline_main.F90
    ${MOM6_TRACER_DIR}/MOM_tracer_Z_init.F90
    ${MOM6_TRACER_DIR}/MOM_tracer_advect.F90
    ${MOM6_TRACER_DIR}/MOM_tracer_advect_schemes.F90
    ${MOM6_TRACER_DIR}/MOM_tracer_diabatic.F90
    ${MOM6_TRACER_DIR}/MOM_tracer_flow_control.F90
    ${MOM6_TRACER_DIR}/MOM_tracer_hor_diff.F90
    ${MOM6_TRACER_DIR}/MOM_tracer_registry.F90
    ${MOM6_TRACER_DIR}/MOM_tracer_types.F90
    ${MOM6_TRACER_DIR}/RGC_tracer.F90
    ${MOM6_TRACER_DIR}/advection_test_tracer.F90
    ${MOM6_TRACER_DIR}/boundary_impulse_tracer.F90
    ${MOM6_TRACER_DIR}/dye_example.F90
    ${MOM6_TRACER_DIR}/dyed_obc_tracer.F90
    ${MOM6_TRACER_DIR}/ideal_age_example.F90
    ${MOM6_TRACER_DIR}/nw2_tracers.F90
    ${MOM6_TRACER_DIR}/oil_tracer.F90
    ${MOM6_TRACER_DIR}/pseudo_salt_tracer.F90
    ${MOM6_TRACER_DIR}/tracer_example.F90
)
