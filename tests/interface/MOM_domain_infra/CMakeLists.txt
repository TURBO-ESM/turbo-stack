
set(MOM_DOMAIN_INFRA_TESTS
  test_compute_extent.pf
  test_create_mom_domain.pf
)

add_mom_tests(${MOM_DOMAIN_INFRA_TESTS})


# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)