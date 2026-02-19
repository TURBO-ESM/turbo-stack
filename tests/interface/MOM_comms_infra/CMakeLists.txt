
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
  test_set_pelist_to_single_then_reset.pf
  test_set_pelist_split.pf
  test_get_pelist_all_ranks.pf
)

add_mom_tests(${MOM_COMS_INFRA_TESTS})

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
