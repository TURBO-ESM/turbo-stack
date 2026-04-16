set(MOM6_INFRA_DIR ${MOM6_DIR}/config_src/infra/${TURBO_INFRA})

# MOM_interp_infra.F90 is excluded — it depends on MOM_io from src/,
# which requires much of the MOM6 framework to be built first.
add_library(mom6_infra STATIC
    ${MOM6_INFRA_DIR}/MOM_error_infra.F90
    ${MOM6_INFRA_DIR}/MOM_constants.F90
    ${MOM6_INFRA_DIR}/MOM_time_manager.F90
    ${MOM6_INFRA_DIR}/MOM_cpu_clock_infra.F90
    ${MOM6_INFRA_DIR}/MOM_ensemble_manager_infra.F90
    ${MOM6_INFRA_DIR}/array_mod.F90
    ${MOM6_INFRA_DIR}/MOM_coms_infra.F90
    ${MOM6_INFRA_DIR}/MOM_domain_infra.F90
    ${MOM6_INFRA_DIR}/MOM_data_override_infra.F90
    ${MOM6_INFRA_DIR}/MOM_diag_manager_infra.F90
    ${MOM6_INFRA_DIR}/MOM_couplertype_infra.F90
    ${MOM6_INFRA_DIR}/MOM_io_infra.F90
)
add_library(MOM6::infra ALIAS mom6_infra)

set_target_properties(mom6_infra PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod
)

target_include_directories(mom6_infra
    INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>
)

target_link_libraries(mom6_infra
    PUBLIC  FMS::fms_r8 MPI::MPI_Fortran NetCDF::NetCDF_Fortran
    # framework_base (not framework) — see mom6_build/src/framework/CMakeLists.txt
    # for why this must be framework_base to avoid a circular dependency.
    PRIVATE MOM6::framework_base
)
