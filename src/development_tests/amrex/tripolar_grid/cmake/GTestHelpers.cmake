function(add_gtest source_file)

  get_filename_component(target_name "${source_file}" NAME_WE)
  # For now enforce that target name ends with _test. Could be relaxed later.
  if(NOT target_name MATCHES "_test$")
    message(FATAL_ERROR "Test executable name must end with '_test'")
  endif() 

  add_executable(${target_name} ${source_file})
  # Assumes that any additional libraries to link are passed after the source file... hence ${ARGN}.
  # This could be improved later to use named arguments if we need to pass in other things that are not libraries to link against.
  target_link_libraries(${target_name} PRIVATE GTest::gtest_main ${ARGN})
  gtest_discover_tests(${target_name})

endfunction()