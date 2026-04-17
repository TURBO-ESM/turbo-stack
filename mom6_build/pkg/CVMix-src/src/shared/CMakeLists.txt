set(CVMIX_DIR ${MOM6_DIR}/pkg/CVMix-src/src/shared)

add_library(mom6_cvmix STATIC
    ${CVMIX_DIR}/cvmix_kinds_and_types.F90
    ${CVMIX_DIR}/cvmix_background.F90
    ${CVMIX_DIR}/cvmix_convection.F90
    ${CVMIX_DIR}/cvmix_ddiff.F90
    ${CVMIX_DIR}/cvmix_kpp.F90
    ${CVMIX_DIR}/cvmix_math.F90
    ${CVMIX_DIR}/cvmix_put_get.F90
    ${CVMIX_DIR}/cvmix_shear.F90
    ${CVMIX_DIR}/cvmix_tidal.F90
    ${CVMIX_DIR}/cvmix_utils.F90
)
add_library(MOM6::CVMix ALIAS mom6_cvmix)

set_target_properties(mom6_cvmix PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod
)

target_include_directories(mom6_cvmix
    INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>
)
