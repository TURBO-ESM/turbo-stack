include(add_mom_test)

# Path to the pFUnit base test case used by all tests.
file(REAL_PATH MOM_test_case.F90 BASE_MOM_PFUNIT_INFRA)

# Path to config files (input.nml etc.) used by tests at runtime.
file(REAL_PATH config CONFIG_FILES)

add_subdirectory(interface)
