set(SRC ${LEGACY_TESTS_DIR}/interface/MOM_domain_infra)

set(MOM_DOMAIN_INFRA_TESTS
  ${SRC}/test_compute_extent.pf
  ${SRC}/test_create_mom_domain.pf
)

add_mom_tests(${MOM_DOMAIN_INFRA_TESTS})

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
