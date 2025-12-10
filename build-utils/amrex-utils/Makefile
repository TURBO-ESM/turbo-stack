include $(TEMPLATE)

build_amrex:
	cmake -S ${AMREX_ROOT} -B ${BLD_PATH} -DAMReX_FORTRAN_INTERFACES=YES -DAMReX_FORTRAN=YES -DCMAKE_INSTALL_PREFIX=${AMREX_PATH}; \
	cd ${BLD_PATH}; \
	make; \
	make install
