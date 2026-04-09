
set(ARRAY_MOD_TESTS
  test_duplicate.pf
  test_copy2array.pf
  test_copy2fortran.pf
)

add_mom_tests(${ARRAY_MOD_TESTS})


# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
