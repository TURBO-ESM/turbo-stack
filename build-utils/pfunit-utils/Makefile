include $(TEMPLATE)

build_pfunit:
	cmake -S ${PFUNIT_ROOT} -B ${BLD_PATH} -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} -DCMAKE_INSTALL_PREFIX=${PFUNIT_INSTALL_PATH} -DCMAKE_Fortran_COMPILER=$(shell which $(FC)) -DCMAKE_C_COMPILER=$(shell which $(CC)); \
	cd ${BLD_PATH}; \
	make -j${JOBS}; \
	make install
