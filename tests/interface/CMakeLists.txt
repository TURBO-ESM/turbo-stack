add_pfunit_ctest(infra_tests
  TEST_SOURCES mom_init.pf
  LINK_LIBRARIES NetCDF_Fortran NetCDF FMS_Infra FMS ${AMREX_LIB}
)
# Temporary fix to force cmake to use the Fortran linker
set_property(TARGET infra_tests PROPERTY LINKER_LANGUAGE Fortran)

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
