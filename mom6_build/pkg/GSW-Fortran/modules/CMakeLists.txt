set(GSW_DIR ${MOM6_DIR}/pkg/GSW-Fortran/modules)

add_library(mom6_gsw STATIC
    ${GSW_DIR}/gsw_mod_kinds.f90
    ${GSW_DIR}/gsw_mod_baltic_data.f90
    ${GSW_DIR}/gsw_mod_error_functions.f90
    ${GSW_DIR}/gsw_mod_freezing_poly_coefficients.f90
    ${GSW_DIR}/gsw_mod_gibbs_ice_coefficients.f90
    ${GSW_DIR}/gsw_mod_saar_data.f90
    ${GSW_DIR}/gsw_mod_sp_coefficients.f90
    ${GSW_DIR}/gsw_mod_specvol_coefficients.f90
    ${GSW_DIR}/gsw_mod_teos10_constants.f90
    ${GSW_DIR}/gsw_mod_netcdf.f90
    ${GSW_DIR}/gsw_mod_toolbox.f90
)
add_library(MOM6::GSW ALIAS mom6_gsw)

set_target_properties(mom6_gsw PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod
)

target_include_directories(mom6_gsw
    INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>
)

# gsw_mod_netcdf.f90 uses the netcdf Fortran module; NetCDF_C is also needed because
# NetCDF::NetCDF_Fortran's link flags from nf-config don't include the C library path.
target_link_libraries(mom6_gsw
    PRIVATE NetCDF::NetCDF_Fortran NetCDF::NetCDF_C
)
