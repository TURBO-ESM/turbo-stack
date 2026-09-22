
add_mom_test(test_compute_extent.pf
    LINK_LIBRARIES MOM6::infra
)

add_mom_test(test_create_mom_domain.pf
    LINK_LIBRARIES MOM6::framework
)

copy_dummy_fms_input_nml()
