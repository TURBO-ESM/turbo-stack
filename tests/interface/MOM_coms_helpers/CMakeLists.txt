
set(MOM_COMS_HELPERS_TESTS
  test_set_pelist_to_single_then_reset.pf
  test_set_pelist_split.pf
  test_get_pelist_all_ranks.pf
  test_num_pes.pf
  test_root_pe.pf
  test_pe_here.pf
)

add_mom_tests(${MOM_COMS_HELPERS_TESTS})


# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
