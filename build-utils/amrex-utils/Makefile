include $(TEMPLATE)

# AMReX must build with the real host compiler. Under OFFLOAD the template sets
# CXX to the MOM6 nvcc dispatch wrapper (for MOM6's own AMReX TUs); that wrapper
# must not be AMReX's compiler. offload => nvhpc/ncar, where the host C++ is CC.
ifeq ($(OFFLOAD),1)
  CXX := CC
endif

build_amrex:
	cmake -S ${AMREX_ROOT} -B ${AMREX_BLD_PATH}          \
		--install-prefix ${AMREX_INSTALL_PATH}           \
		-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}           \
		-DAMReX_FORTRAN_INTERFACES=YES                   \
		-DAMReX_FORTRAN=YES                              \
		$(AMREX_GPU_FLAGS)                               \
		-DCMAKE_Fortran_COMPILER=$(shell which $(FC))    \
		-DCMAKE_CXX_COMPILER=$(shell which $(CXX))       \
		-DCMAKE_C_COMPILER=$(shell which $(CC))          \
		-DAMReX_TINY_PROFILE=ON                       && \
	cmake --build ${AMREX_BLD_PATH} -j ${JOBS}        && \
	cmake --install ${AMREX_BLD_PATH}
