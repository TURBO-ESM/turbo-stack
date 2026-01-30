
function(find_mom_dependencies)
  set(prefix TEMP)
  set(optionalValues "")
  set(singleValues INFRA_TYPE BACKEND_PATH INFRA_PATH)
  set(multiValues "")

  include(CMakeParseArguments)
  cmake_parse_arguments(${prefix} "${optionalValues}" "${singleValues}" "${multiValues}" ${ARGN})

  set(SUPPORTED_INFRAS "TIM" "FMS2")
  if(NOT TEMP_INFRA IN_LISTS SUPPORTED_INFRAS)
    message(FATAL_ERROR "In ${CMAKE_CURRENT_FUNCTION}, INFRA parameter given is ${TEMP_INFRA}.  Expected one of ${SUPPORTED_INFRAS}")
  endif()

  # Support NetCDF builds that don't provide cmake configs.
  message(STATUS "Detecting NetCDF install via find_package")
  find_package(NetCDF QUIET COMPONENTS C Fortran)
  if(NOT NetCDF_FOUND)
    message(STATUS "Unable to detect NetCDF install via find_package.  Re-trying with pkg-config.")
    find_package(PkgConfig REQUIRED)

    # Most older installs of NetCDF usually have a pkgconfig directory with .pc files
    # Scans the same prefix directories as find_package().
    pkg_search_module(NetCDF_C REQUIRED IMPORTED_TARGET netcdf)
    message(STATUS "Found NetCDF_C via pkg-config")
    # Add an alias to match the official NetCDF CMake target.  This allows for linking
    # against the same target without changing the source code.
    add_library(NetCDF::NetCDF_C ALIAS PkgConfig::NetCDF_C)

    pkg_search_module(NetCDF_Fortran REQUIRED IMPORTED_TARGET netcdf-fortran)
    message(STATUS "Found NetCDF_Fortran via pkg-config")
    add_library(NetCDF::NetCDF_Fortran ALIAS PkgConfig::NetCDF_Fortran)
  endif()

  # Only set AMREX_LIB if needed; else keep undefined
  if("${INFRA}" STREQUAL "TIM")
    # Even if AMReX is installed, need to explicitly require Fortran API installed.
    find_package(AMReX REQUIRED COMPONENTS FORTRAN)
    set(AMREX_LIB AMReX::amrex)
  endif()

  # Load and configure external dependencies not provided by cmake modules.
  add_library(MOM::Impl STATIC IMPORTED)
  set_target_properties(MOM::Impl PROPERTIES
    IMPORTED_LOCATION ${TEMP_BACKEND_PATH}/lib${TEMP_INFRA_TYPE}.a
    LINKER_LANGUAGE Fortran # Need to force the linker language due to intel thinking this
                            # is a C library from linking against NetCDF_C and tries to
                            # link with the incorrect linker.
  )
  target_include_directories(MOM::Impl INTERFACE ${TEMP_BACKEND_PATH})
  target_link_libraries(MOM::Impl INTERFACE NetCDF::NetCDF_Fortran NetCDF::NetCDF_C ${AMREX_LIB})

  add_library(MOM::Interface STATIC IMPORTED)
  set_target_properties(MOM::Interface PROPERTIES
    IMPORTED_LOCATION ${TEMP_INFRA_PATH}/libinfra-${TEMP_INFRA_TYPE}.a
    LINKER_LANGUAGE Fortran
  )
  target_include_directories(MOM::Interface INTERFACE ${TEMP_INFRA_PATH})
  target_link_libraries(MOM::Interface INTERFACE MOM::Impl)
endfunction()