include $(TEMPLATE)

# Need -DSKIP_OPENMP=YES to support clang compiler bug
# not being able to find OpenMP through CMake when calling find_package(PFUNIT)
build_pfunit:
	cmake -S ${PFUNIT_ROOT} -B ${PFUNIT_BLD_PATH}     \
	    --install-prefix ${PFUNIT_INSTALL_PATH}       \
		-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}        \
		-DCMAKE_Fortran_COMPILER=$(shell which $(FC)) \
		-DCMAKE_C_COMPILER=$(shell which $(CC))       \
		-DSKIP_OPENMP=YES                          && \
	cmake --build ${PFUNIT_BLD_PATH} -j ${JOBS}    && \
	cmake --install ${PFUNIT_BLD_PATH};
