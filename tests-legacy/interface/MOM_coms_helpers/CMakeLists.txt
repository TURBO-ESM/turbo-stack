set(SRC ${LEGACY_TESTS_DIR}/interface/MOM_coms_helpers)

set(MOM_COMS_HELPERS_TESTS
  ${SRC}/test_set_pelist_to_single_then_reset.pf
  ${SRC}/test_set_pelist_split.pf
  ${SRC}/test_get_pelist_all_ranks.pf
  ${SRC}/test_num_pes.pf
  ${SRC}/test_root_pe.pf
  ${SRC}/test_pe_here.pf
)

add_mom_tests(${MOM_COMS_HELPERS_TESTS})

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
