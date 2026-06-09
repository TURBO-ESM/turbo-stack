# add_mom_tests(TEST_FILES file1.pf file2.pf ... [LINK_LIBRARIES lib1 lib2 ...])
# TEST_FILES first, then optional LINK_LIBRARIES.
# Convenience wrapper that calls add_mom_test() for each file in TEST_FILES.
# LINK_LIBRARIES are passed through to each test (see add_mom_test below).
function(add_mom_tests)
    cmake_parse_arguments(SUITE "" "" "TEST_FILES;LINK_LIBRARIES" ${ARGN})
    # Catch positional callers (`add_mom_tests(foo.pf bar.pf)`) -- those used
    # to silently register zero tests because the wrapper only looks at
    # SUITE_TEST_FILES.
    if(SUITE_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR
            "add_mom_tests: unexpected positional arguments "
            "'${SUITE_UNPARSED_ARGUMENTS}'. Pass test files via "
            "TEST_FILES ... and link libs via LINK_LIBRARIES ....")
    endif()
    # An empty SUITE_LINK_LIBRARIES expands to a bare `LINK_LIBRARIES` keyword,
    # which add_mom_test parses to an empty list -- so no need to branch on it.
    foreach(TEST_FILE IN LISTS SUITE_TEST_FILES)
        add_mom_test("${TEST_FILE}" LINK_LIBRARIES ${SUITE_LINK_LIBRARIES})
    endforeach()
endfunction()

# add_mom_test(file.pf [LINK_LIBRARIES lib1 lib2 ...])
# Creates a pFUnit CTest from a single .pf file.
# Always links TURBO::infra_r8 (provides MPI and NetCDF transitively).
# Pass additional libraries under test via LINK_LIBRARIES.
function(add_mom_test TEST_FILE)
    cmake_parse_arguments(TEST "" "" "LINK_LIBRARIES" ${ARGN})
    get_filename_component(TEST_TARGET ${TEST_FILE} NAME_WE)

    set(_pfunit_other_sources "")
    if(BASE_MOM_PFUNIT_INFRA)
        set(_pfunit_other_sources OTHER_SOURCES "${BASE_MOM_PFUNIT_INFRA}")
    endif()
    add_pfunit_ctest(${TEST_TARGET}
        TEST_SOURCES "${TEST_FILE}"
        LINK_LIBRARIES TURBO::infra_r8 ${TEST_LINK_LIBRARIES}
        ${_pfunit_other_sources}
        MAX_PES 4
    )

    # Drive the test exe link via g++ rather than gfortran. The test
    # sources are Fortran, so CMake would otherwise pick LINKER_LANGUAGE
    # Fortran -- but gfortran does not auto-link the full C++ runtime
    # (libstdc++, libgcc_s, libgcc) that AMReX needs when MOM6_INFRA=TIM
    # is pulled in transitively through TURBO::infra_r8. g++ drives the
    # link in both FMS2 and TIM configurations; CMake still appends
    # -lgfortran/-lquadmath because Fortran objects contribute to the
    # target.
    set_property(TARGET ${TEST_TARGET} PROPERTY LINKER_LANGUAGE CXX)
endfunction()

# copy_dummy_fms_input_nml()
# Copies input.nml into the current build directory so FMS can find it at runtime.
# Call once per test subdirectory that links against FMS if input.nml is not already present in the source directory.
function(copy_dummy_fms_input_nml)
    configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
endfunction()
