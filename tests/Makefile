include $(TEMPLATE)

# make does not allow cyclical variables so need to create temporary copies
# make does not allow VAR=VAL cmake ...
# (thinks VR=VAL is the command and results in a command not found exception)
build_unit_tests: export Fortran_REAL_FLAG=$(FC_AUTO_R8)

build_unit_tests:
	cmake -S . -B ${TEST_BUILD_DIR}                      \
		-DINFRA=${LIB_INFRA}                             \
		-DPATH_TO_BACKEND_LIB="${PATH_TO_BACKEND_LIB}"   \
		-DPATH_TO_LIBINFRA="${PATH_TO_LIBINFRA}"         \
		-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}           \
		-DCMAKE_PREFIX_PATH="${AMREX_INSTALL_PATH};${PFUNIT_INSTALL_PATH};${NetCDF_C_PREFIX_PATH};${NetCDF_Fortran_PREFIX_PATH}" \
		-DCMAKE_Fortran_COMPILER=$(shell which $(FC))    \
		-DCMAKE_CXX_COMPILER=$(shell which $(CXX))       \
		-DCMAKE_C_COMPILER=$(shell which $(CC))       && \
	cmake --build ${TEST_BUILD_DIR} -j ${JOBS}        && \
	ctest --test-dir ${TEST_BUILD_DIR}                   \
		--output-on-failure -VV                          \
		--no-tests=error                                 \
		--output-log ${TEST_BUILD_DIR}/ctest.log
