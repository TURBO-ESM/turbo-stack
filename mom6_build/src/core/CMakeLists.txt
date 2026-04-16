set(MOM6_CORE_DIR ${MOM6_DIR}/src/core)

# Layer 4 (mom6_grid): MOM_grid and MOM_verticalGrid.
# These are the minimal src/core/ files needed to complete the framework layer.
# MOM_io (Layer 5, in src/framework/) needs them; they in turn only need
# mom6_framework (Layer 3), so they sit between framework and io.
#
# All deps are already in mom6_framework:
#   MOM_grid         needs MOM_domains, MOM_error_handler, MOM_file_parser,
#                    MOM_hor_index, MOM_unit_scaling
#   MOM_verticalGrid needs MOM_domains, MOM_error_handler, MOM_file_parser,
#                    MOM_hor_index, MOM_unit_scaling
add_library(mom6_grid STATIC
    ${MOM6_CORE_DIR}/MOM_grid.F90
    ${MOM6_CORE_DIR}/MOM_verticalGrid.F90
)
add_library(MOM6::grid ALIAS mom6_grid)

set_target_properties(mom6_grid PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod
)

target_include_directories(mom6_grid
    INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>
)

target_include_directories(mom6_grid
    PRIVATE ${MOM6_DIR}/config_src/memory/${TURBO_MEMORY_MODE}
)

target_link_libraries(mom6_grid
    PUBLIC MOM6::framework
)
