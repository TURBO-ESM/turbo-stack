
set(MOM_COMS_INFRA_TESTS
  test_broadcast_int1D.pf
  test_broadcast_int320D.pf
  test_broadcast_int640D.pf
  test_broadcast_char.pf
  test_broadcast_real0D.pf
  test_broadcast_real1D.pf
  test_broadcast_real2D.pf
  test_broadcast_real3D.pf
  test_broadcast_IntArray.pf
  test_broadcast_RealArray.pf
  test_set_pelist_to_single_then_reset.pf
  test_set_pelist_split.pf
  test_get_pelist_all_ranks.pf
  test_field_checksum_real_0d.pf
  test_field_checksum_real_1d.pf
  test_field_checksum_real_2d.pf
  test_field_checksum_real_3d.pf
  test_field_checksum_real_4d.pf
  test_sum_across_pes_int32_0d.pf
  test_sum_across_pes_int32_1d.pf
  test_sum_across_pes_int32_2d.pf
  test_sum_across_pes_int64_0d.pf
  test_sum_across_pes_int64_1d.pf
  test_sum_across_pes_int64_2d.pf
  test_sum_across_pes_real64_0d.pf
  test_sum_across_pes_real64_1d.pf
  test_sum_across_pes_real64_2d.pf
  test_min_across_pes_int_0d.pf
  test_min_across_pes_real64_0d.pf
  test_min_across_pes_real64_1d.pf
  test_max_across_pes_int_0d.pf
  test_max_across_pes_real64_0d.pf
  test_max_across_pes_real64_1d.pf
  test_any_across_pes.pf
  test_all_across_pes.pf
  test_num_pes.pf
  test_root_pe.pf
  test_pe_here.pf
)

add_mom_tests(
    TEST_FILES ${MOM_COMS_INFRA_TESTS}
    LINK_LIBRARIES MOM6::infra
)

copy_dummy_fms_input_nml()
