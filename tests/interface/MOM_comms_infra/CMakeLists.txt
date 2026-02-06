add_mom_test(test_num_pes PFUNIT_FILE test_num_pes.pf)
add_mom_test(test_broadcast_int320D PFUNIT_FILE test_broadcast_int320D.pf)
add_mom_test(test_broadcast_int640D PFUNIT_FILE test_broadcast_int640D.pf)
add_mom_test(test_broadcast_char PFUNIT_FILE test_broadcast_char.pf)
add_mom_test(test_broadcast_real0D PFUNIT_FILE test_broadcast_real0D.pf)
add_mom_test(test_broadcast_int1D PFUNIT_FILE test_broadcast_int1D.pf)
add_mom_test(test_broadcast_real1D PFUNIT_FILE test_broadcast_real1D.pf)
add_mom_test(test_broadcast_real2D PFUNIT_FILE test_broadcast_real2D.pf)
add_mom_test(test_broadcast_real3D PFUNIT_FILE test_broadcast_real3D.pf)

add_mom_test(test_pelistA PFUNIT_FILE test_pelistA.pf)
add_mom_test(test_pelistB PFUNIT_FILE test_pelistB.pf)
add_mom_test(test_pelistC PFUNIT_FILE test_pelistC.pf)

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
