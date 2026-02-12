
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
  test_field_checksum_real640d.pf
  test_field_checksum_real641d.pf
  test_field_checksum_real642d.pf
  test_field_checksum_real643d.pf
  test_field_checksum_real644d.pf
  test_sum_across_pes_int32_0d.pf
  test_sum_across_pes_int32_1d.pf
  test_sum_across_pes_int32_2d.pf
  test_sum_across_pes_int64_0d.pf
  test_sum_across_pes_int64_1d.pf
  test_sum_across_pes_int64_2d.pf
  test_sum_across_pes_real64_0d.pf
  test_sum_across_pes_real64_1d.pf
  test_sum_across_pes_real64_2d.pf
)

add_mom_tests(${MOM_COMS_INFRA_TESTS})

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
