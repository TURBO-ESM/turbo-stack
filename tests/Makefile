include $(TEMPLATE)

# make does not allow cyclical variables so need to create temporary copies
# make does not allow VAR=VAL cmake ...
# (thinks VR=VAL is the command and results in a command not found exception)
build_unit_tests: export BLD_PATH=$(BLD_PATH_ROOT)
build_unit_tests: export NetCDF_Fortran_DIR=$(NETCDFF_PREFIX)
build_unit_tests: export NetCDF_LIB_DIR=$(NETCDF_LIB_DIR)
build_unit_tests: export NetCDF_DIR=$(NETCDF_PREFIX)
build_unit_tests: export INFRA=$(LIBINFRA)

build_unit_tests:
	cmake -S . -B ${TEST_BUILD_DIR} -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} -DCMAKE_PREFIX_PATH="${AMREX_INSTALL_PATH};${PFUNIT_INSTALL_PATH}" -DCMAKE_Fortran_COMPILER=$(shell which $(FC)) -DCMAKE_CXX_COMPILER=$(shell which $(CXX)) -DCMAKE_C_COMPILER=$(shell which $(CC)); \
	cd ${TEST_BUILD_DIR}; \
	make -j${JOBS}; \
	ctest --output-on-failure -VV
