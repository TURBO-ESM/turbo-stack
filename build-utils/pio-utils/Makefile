include $(TEMPLATE)

# Build ParallelIO (PIO2) from a pinned source tarball -- the container /
# non-NCAR fallback when no parallelio module or PIO_INSTALL_PATH is
# available. Mirrors build-utils/amrex-utils/Makefile, except the source is
# downloaded rather than a submodule: the same pinned tag TIM's CMake
# fallback (cmake/FindOrFetchPIO.cmake) fetches, so both build systems share
# one source of truth. Note: the pio2_6_8 tag self-reports 2.6.6 (upstream
# version-string lag, not a wrong pin).
#
# Only the C library (libpioc) is built: TIM's C++ I/O layer consumes just the
# PIOc_* C API, so the Fortran library and GPTL timing are disabled to keep
# the fallback build lean. NetCDF is discovered via nc-config; PnetCDF is not
# required (PIO uses the netCDF backend).

PIO_TAG = pio2_6_8
PIO_TARBALL_URL = https://github.com/NCAR/ParallelIO/archive/refs/tags/$(PIO_TAG).tar.gz
PIO_SRC_DIR = $(PIO_SRC_PATH)/ParallelIO-$(PIO_TAG)

build_pio:
	test -f $(PIO_SRC_DIR)/CMakeLists.txt || \
		( mkdir -p $(PIO_SRC_PATH) && \
		  curl -fsSL $(PIO_TARBALL_URL) | tar xz -C $(PIO_SRC_PATH) )
	cmake -S $(PIO_SRC_DIR) -B ${PIO_BLD_PATH}           \
		--install-prefix ${PIO_INSTALL_PATH}             \
		-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}           \
		-DPIO_ENABLE_FORTRAN=OFF                         \
		-DPIO_ENABLE_TIMING=OFF                          \
		-DPIO_ENABLE_EXAMPLES=OFF                        \
		-DPIO_ENABLE_LOGGING=OFF                         \
		-DWITH_PNETCDF=OFF                               \
		-DNetCDF_C_PATH=$(shell nc-config --prefix)      \
		-DCMAKE_C_COMPILER=$(shell which $(CC))       && \
	cmake --build ${PIO_BLD_PATH} -j ${JOBS}          && \
	cmake --install ${PIO_BLD_PATH}
