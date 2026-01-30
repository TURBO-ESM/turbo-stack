# PE tests
add_mom_test(test_num_pes PFUNIT_FILE test_num_pes.pf)
add_mom_test(test_root_pe PFUNIT_FILE test_root_pe.pf)
add_mom_test(test_pe_here PFUNIT_FILE test_pe_here.pf)

# Broadcast tests
add_mom_test(test_broadcast_int320D PFUNIT_FILE test_broadcast_int320D.pf)
add_mom_test(test_broadcast_int640D PFUNIT_FILE test_broadcast_int640D.pf)
add_mom_test(test_broadcast_char PFUNIT_FILE test_broadcast_char.pf)
add_mom_test(test_broadcast_real0D PFUNIT_FILE test_broadcast_real0D.pf)
add_mom_test(test_broadcast_int1D PFUNIT_FILE test_broadcast_int1D.pf)
add_mom_test(test_broadcast_real1D PFUNIT_FILE test_broadcast_real1D.pf)
add_mom_test(test_broadcast_real2D PFUNIT_FILE test_broadcast_real2D.pf)
add_mom_test(test_broadcast_real3D PFUNIT_FILE test_broadcast_real3D.pf)

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
