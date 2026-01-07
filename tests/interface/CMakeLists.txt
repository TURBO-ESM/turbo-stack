add_pfunit_ctest(infra_tests
  TEST_SOURCES mom_init.pf
  LINK_LIBRARIES NetCDF_Fortran NetCDF FMS_Infra FMS ${AMREX_LIB}
)

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
