add_pfunit_ctest(infra_tests
  TEST_SOURCES MOM_comms_infra_test.pf MOM_test_case.pf
  LINK_LIBRARIES NetCDF_Fortran NetCDF FMS_Infra FMS ${AMREX_LIB}
  MAX_PES 4
)
# Temporary fix to force cmake to use the Fortran linker
set_property(TARGET infra_tests PROPERTY LINKER_LANGUAGE Fortran)

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
