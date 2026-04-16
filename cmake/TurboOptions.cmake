# What to build
option(TURBO_BUILD_UNIT_TESTS "Build pFUnit unit tests" ON)
option(TURBO_BUILD_MOM6       "Build MOM6 executable"   OFF)

# Infrastructure backend
set(TURBO_INFRA "FMS2" CACHE STRING "Infrastructure backend: FMS2 or TIM")
set_property(CACHE TURBO_INFRA PROPERTY STRINGS FMS2 TIM)

# Memory layout
set(TURBO_MEMORY_MODE "dynamic_symmetric" CACHE STRING
    "MOM6 memory layout: dynamic_symmetric or dynamic_nonsymmetric")
set_property(CACHE TURBO_MEMORY_MODE PROPERTY STRINGS
    dynamic_symmetric dynamic_nonsymmetric)

# Compiler-specific features (guarded in TurboCompilerFlags.cmake)
option(TURBO_CODECOV  "Enable code coverage instrumentation (GNU only)" OFF)
