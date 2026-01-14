include $(TEMPLATE)

build_pfunit:
	cmake -S ${PFUNIT_ROOT} -B ${BLD_PATH} -DCMAKE_INSTALL_PREFIX=${PFUNIT_INSTALL_PATH} -DCMAKE_Fortran_COMPILER=$(FC) -DCMAKE_C_COMPILER=$(CC); \
	cd ${BLD_PATH}; \
	make -j${JOBS}; \
	make install
