add_mom_test(test_num_pes PFUNIT_FILE test_num_pes.pf)

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
