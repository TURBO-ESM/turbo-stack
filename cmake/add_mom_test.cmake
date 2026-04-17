# add_mom_tests(TEST_FILES file1.pf file2.pf ... [LINK_LIBRARIES lib1 lib2 ...])
# TEST_FILES first, then optional LINK_LIBRARIES.
# Convenience wrapper that calls add_mom_test() for each file in TEST_FILES.
# LINK_LIBRARIES are passed through to each test (see add_mom_test below).
function(add_mom_tests)
    cmake_parse_arguments(SUITE "" "" "TEST_FILES;LINK_LIBRARIES" ${ARGN})
    foreach(TEST_FILE IN LISTS SUITE_TEST_FILES)
        add_mom_test("${TEST_FILE}" LINK_LIBRARIES ${SUITE_LINK_LIBRARIES})
    endforeach()
endfunction()

# add_mom_test(file.pf [LINK_LIBRARIES lib1 lib2 ...])
# Creates a pFUnit CTest from a single .pf file.
# Always links FMS::fms_r8 (provides MPI and NetCDF transitively).
# Pass additional libraries under test via LINK_LIBRARIES.
function(add_mom_test TEST_FILE)
    cmake_parse_arguments(TEST "" "" "LINK_LIBRARIES" ${ARGN})
    get_filename_component(TEST_TARGET ${TEST_FILE} NAME_WE)

    add_pfunit_ctest(${TEST_TARGET}
        TEST_SOURCES "${TEST_FILE}"
        LINK_LIBRARIES FMS::fms_r8 ${TEST_LINK_LIBRARIES}
        OTHER_SOURCES "${BASE_MOM_PFUNIT_INFRA}"
        MAX_PES 4
    )

    set_property(TARGET ${TEST_TARGET} PROPERTY LINKER_LANGUAGE Fortran)
endfunction()

# copy_dummy_fms_input_nml()
# Copies input.nml into the current build directory so FMS can find it at runtime.
# Call once per test subdirectory that links against FMS if input.nml is not already present in the source directory.
function(copy_dummy_fms_input_nml)
    configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
endfunction()
