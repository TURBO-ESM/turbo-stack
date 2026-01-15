include $(TEMPLATE)

build_amrex:
	cmake -S ${AMREX_ROOT} -B ${BLD_PATH} -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} -DCMAKE_Fortran_FLAGS="$(FFLAGS)" -DAMReX_FORTRAN_INTERFACES=YES -DAMReX_FORTRAN=YES -DCMAKE_INSTALL_PREFIX=${AMREX_INSTALL_PATH} -DCMAKE_Fortran_COMPILER=$(shell which $(FC)) -DCMAKE_CXX_COMPILER=$(shell which $(CXX)) -DCMAKE_C_COMPILER=$(shell which $(CC)); \
	cd ${BLD_PATH}; \
	make -j${JOBS}; \
	make install
