

function(add_mom_test TEST_TARGET_NAME)
  set(prefix MOM)
  set(optionalValues "")
  set(singleValues PFUNIT_FILE MAX_PES)
  set(multiValues "")

  include(CMakeParseArguments)
  cmake_parse_arguments(${prefix} "${optionalValues}" "${singleValues}" "${multiValues}" ${ARGN})

  if(NOT DEFINED MOM_PFUNIT_FILE)
    message(FATAL_ERROR "PFUNIT_FILE test file argument not passed to ${CMAKE_CURRENT_FUNCTION}.")
  endif()

  # Check if MAX_PES is valid integer, else default to 4 PEs.
  if(DEFINED MOM_MAX_PES)
    if (MOM_MAX_PES NOT MATCHES "^[1-9][0-9]*$")
      message(FATAL_ERROR "MAX_PES expected a valid positive integer; recieved ${MOM_MAX_PES}")
    endif()
  else()
    set(MOM_MAX_PES 4)
  endif()

  add_pfunit_ctest(${TEST_TARGET_NAME}
    TEST_SOURCES "${MOM_PFUNIT_FILE}"
    LINK_LIBRARIES NetCDF_Fortran NetCDF BACKEND_Infra BACKEND_lib ${AMREX_LIB}
    OTHER_SOURCES "${BASE_MOM_PFUNIT_INFRA}"
    MAX_PES ${MOM_MAX_PES}
  )

  # Temporary fix to force cmake to use the Fortran linker when using Intel OneAPI.
  set_property(TARGET ${TEST_TARGET_NAME} PROPERTY LINKER_LANGUAGE Fortran)

endfunction()
