add_mom_test(test_num_pes PFUNIT_FILE test_num_pes.pf)
add_mom_test(test_sum_across_pes_int32_0d PFUNIT_FILE test_sum_across_pes_int32_0d.pf)
add_mom_test(test_sum_across_pes_int64_0d PFUNIT_FILE test_sum_across_pes_int64_0d.pf)

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
