add_subdirectory(CVMix-src)
add_subdirectory(GSW-Fortran)

# Validation target — confirms both libraries link and expose correct .mod files.
# Build with: cmake --build <builddir> --target dep_link_test
add_executable(cvmix_gsw_link_test cvmix_gsw_link_test.F90)
target_link_libraries(cvmix_gsw_link_test PRIVATE MOM6::CVMix MOM6::GSW)
