set(SRC ${LEGACY_TESTS_DIR}/interface/MOM_coms_infra)

set(MOM_COMS_INFRA_TESTS
  ${SRC}/test_broadcast_int1D.pf
  ${SRC}/test_broadcast_int320D.pf
  ${SRC}/test_broadcast_int640D.pf
  ${SRC}/test_broadcast_char.pf
  ${SRC}/test_broadcast_real0D.pf
  ${SRC}/test_broadcast_real1D.pf
  ${SRC}/test_broadcast_real2D.pf
  ${SRC}/test_broadcast_real3D.pf
  ${SRC}/test_broadcast_IntArray.pf
  ${SRC}/test_broadcast_RealArray.pf
  ${SRC}/test_field_checksum_real_0d.pf
  ${SRC}/test_field_checksum_real_1d.pf
  ${SRC}/test_field_checksum_real_2d.pf
  ${SRC}/test_field_checksum_real_3d.pf
  ${SRC}/test_field_checksum_real_4d.pf
  ${SRC}/test_sum_across_pes_int32_0d.pf
  ${SRC}/test_sum_across_pes_int32_1d.pf
  ${SRC}/test_sum_across_pes_int32_2d.pf
  ${SRC}/test_sum_across_pes_int64_0d.pf
  ${SRC}/test_sum_across_pes_int64_1d.pf
  ${SRC}/test_sum_across_pes_int64_2d.pf
  ${SRC}/test_sum_across_pes_real64_0d.pf
  ${SRC}/test_sum_across_pes_real64_1d.pf
  ${SRC}/test_sum_across_pes_real64_2d.pf
  ${SRC}/test_min_across_pes_int_0d.pf
  ${SRC}/test_min_across_pes_real64_0d.pf
  ${SRC}/test_min_across_pes_real64_1d.pf
  ${SRC}/test_max_across_pes_int_0d.pf
  ${SRC}/test_max_across_pes_real64_0d.pf
  ${SRC}/test_max_across_pes_real64_1d.pf
  ${SRC}/test_any_across_pes.pf
  ${SRC}/test_all_across_pes.pf
)

add_mom_tests(${MOM_COMS_INFRA_TESTS})

# Copy namelist file to output directory to satisfy FMS requirement
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
