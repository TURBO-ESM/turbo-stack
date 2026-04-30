# Fortran compiler flags for all TurboStack targets.
# Requires TurboOptions.cmake to be included first.
#
# Flags are applied via add_compile_options() scoped to Fortran only.
# All targets in this project inherit them from the top-level scope.

if(NOT CMAKE_Fortran_COMPILER_ID)
    message(FATAL_ERROR "No Fortran compiler detected. Ensure FC is set before invoking CMake.")
endif()

# --- Compiler-specific flags ---
if(CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
    set(_turbo_fortran_flags
        -fdefault-real-8 -fdefault-double-8
        -fconvert=big-endian
        -fcray-pointer -ffree-line-length-none -fno-range-check -fallow-argument-mismatch
    )

elseif(CMAKE_Fortran_COMPILER_ID MATCHES "IntelLLVM|Intel")
    set(_turbo_fortran_flags
        -r8
        -convert big_endian -assume byterecl
        -ftz -traceback -fp-model source -no-fma
        -fpp -Wp,-w
    )

elseif(CMAKE_Fortran_COMPILER_ID MATCHES "NVHPC|PGI")
    set(_turbo_fortran_flags
        -r8
        -Mnofma -i4 -Mextend -byteswapio -Mflushz -Kieee
    )

elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Clang")
    set(_turbo_fortran_flags
        -fdefault-real-8 -fdefault-double-8
        -fconvert=big-endian
    )

else()
    message(FATAL_ERROR
        "Unrecognized Fortran compiler '${CMAKE_Fortran_COMPILER_ID}'. "
        "No project-specific flags applied.")
    set(_turbo_fortran_flags "")
endif()

# --- Code coverage (GNU only) ---
if(TURBO_CODECOV)
    if(NOT CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
        message(FATAL_ERROR
            "TURBO_CODECOV requires a GNU Fortran compiler "
            "(got ${CMAKE_Fortran_COMPILER_ID}).")
    endif()
    list(APPEND _turbo_fortran_flags -fprofile-arcs -ftest-coverage)
    # Coverage requires unoptimized code
    set(CMAKE_Fortran_FLAGS_RELEASE "-O0" CACHE STRING "Fortran release flags (overridden for coverage)" FORCE)
endif()

# --- Apply ---
foreach(_flag IN LISTS _turbo_fortran_flags)
    add_compile_options("$<$<COMPILE_LANGUAGE:Fortran>:${_flag}>")
endforeach()

message(STATUS "Fortran compiler: ${CMAKE_Fortran_COMPILER_ID} ${CMAKE_Fortran_COMPILER_VERSION}")
message(STATUS "Fortran flags: ${_turbo_fortran_flags}")
