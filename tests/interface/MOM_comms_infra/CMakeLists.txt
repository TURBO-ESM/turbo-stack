
set(MOM_COMS_INFRA_TESTS
  test_num_pes.pf
  test_broadcast_int1D.pf
  test_broadcast_int320D.pf
  test_broadcast_int640D.pf
  test_broadcast_char.pf
  test_broadcast_real0D.pf
  test_broadcast_real1D.pf
  test_broadcast_real2D.pf
  test_broadcast_real3D.pf
)

add_mom_tests(${MOM_COMS_INFRA_TESTS})

add_mom_test(test_pelistA PFUNIT_FILE test_pelistA.pf)
add_mom_test(test_pelistB PFUNIT_FILE test_pelistB.pf)
add_mom_test(test_pelistC PFUNIT_FILE test_pelistC.pf)

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
