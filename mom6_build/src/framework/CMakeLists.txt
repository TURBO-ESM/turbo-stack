set(MOM6_FRAMEWORK_DIR ${MOM6_DIR}/src/framework)

# -----------------------------------------------------------------------------
# Why two framework libraries?
#
# MOM6's src/framework/ contains two kinds of files:
#
#   - "Base" utilities: pure Fortran with no dependencies on anything in this
#     project (only iso_fortran_env and similar intrinsics). These are leaf
#     nodes in the dependency graph.
#
#   - "Framework proper": higher-level modules (error handling, I/O, domains,
#     etc.) that depend on the infrastructure layer (config_src/infra/).
#
# If all of src/framework/ were one library, and mom6_infra also linked
# mom6_framework, we would create a circular dependency:
#
#   mom6_infra → mom6_framework → mom6_infra   ← CYCLE, CMake rejects this
#
# The fix is to split framework into two layers:
#
#   mom6_framework_base  (no infra deps)  ← linked by mom6_infra
#   mom6_framework       (depends on infra + framework_base)
#
# Dependency order:
#   mom6_framework_base  →  (nothing in this project)
#   mom6_infra           →  mom6_framework_base
#   mom6_framework       →  mom6_infra + mom6_framework_base
# -----------------------------------------------------------------------------

# Layer 1: pure utility files — no dependencies on anything in this project.
add_library(mom6_framework_base STATIC
    ${MOM6_FRAMEWORK_DIR}/MOM_string_functions.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_array_transform.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_intrinsic_functions.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_murmur_hash.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_safe_alloc.F90
    ${MOM6_FRAMEWORK_DIR}/posix.F90
    ${MOM6_FRAMEWORK_DIR}/numerical_testing_type.F90
)
add_library(MOM6::framework_base ALIAS mom6_framework_base)

set_target_properties(mom6_framework_base PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod/base
)

target_include_directories(mom6_framework_base
    INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod/base>
)

# Layer 3: higher-level framework modules that depend on mom6_infra.
# Populated incrementally as more of src/framework/ is wired in.
# MOM_error_handler depends on: MOM_coms_infra, MOM_error_infra (both in infra)
add_library(mom6_framework STATIC
    ${MOM6_FRAMEWORK_DIR}/MOM_error_handler.F90
)
add_library(MOM6::framework ALIAS mom6_framework)

set_target_properties(mom6_framework PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod/framework
)

target_include_directories(mom6_framework
    INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod/framework>
)

target_link_libraries(mom6_framework
    PUBLIC  MOM6::infra MOM6::framework_base
)
