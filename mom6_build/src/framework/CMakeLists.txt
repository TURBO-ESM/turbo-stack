set(MOM6_FRAMEWORK_DIR ${MOM6_DIR}/src/framework)

# -----------------------------------------------------------------------------
# Why multiple framework libraries?
#
# MOM6's src/framework/ contains files at several dependency levels. Splitting
# into layers avoids circular dependencies between libraries:
#
#   mom6_framework needs mom6_grid needs mom6_framework   (CYCLE if one library)
#
# Layer 1 (this file): mom6_framework_base -- leaf utilities, no project deps.
# Layer 2 (config_src/infra/CMakeLists.txt): mom6_infra -- FMS2/TIM infra wrapper.
# Layer 3 (this file): mom6_framework -- framework core, needs Layers 1 and 2.
# Layer 4 (src/core/CMakeLists.txt): mom6_grid -- MOM_grid and MOM_verticalGrid,
#          needs Layer 3.
# Layer 5 (this file): mom6_io -- I/O modules that need mom6_grid, needs Layer 4.
#
# Dependency order:
#   mom6_framework_base  needs nothing in this project
#   mom6_infra           needs mom6_framework_base
#   mom6_framework       needs mom6_infra and mom6_framework_base
#   mom6_grid            needs mom6_framework
#   mom6_io              needs mom6_grid (and transitively all lower layers)
# -----------------------------------------------------------------------------

# Layer 1 (mom6_framework_base): pure utility files, no dependencies on anything in this project.
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
              $<BUILD_INTERFACE:${MOM6_FRAMEWORK_DIR}>
)

# Layer 3 (mom6_framework): higher-level framework modules that depend on mom6_infra.
# Files are added in dependency order via target_sources(), one block per tier.

# Tier A -- depend only on infra + framework_base
#   MOM_error_handler  needs MOM_coms_infra, MOM_error_infra, posix
#   MOM_cpu_clock      needs MOM_cpu_clock_infra
#   MOM_document       needs MOM_error_handler, MOM_time_manager
#   MOM_unique_scales  needs MOM_error_handler
#   MOM_coms           needs MOM_coms_infra, MOM_error_handler
#   MOM_coupler_types  needs MOM_array_transform, MOM_couplertype_infra,
#                      MOM_domain_infra, MOM_time_manager
#   MOM_data_override  needs MOM_data_override_infra
#   MOM_ensemble_manager needs MOM_ensemble_manager_infra
#   MOM_unit_testing   needs MOM_coms, MOM_error_handler, posix
add_library(mom6_framework STATIC
    ${MOM6_FRAMEWORK_DIR}/MOM_error_handler.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_cpu_clock.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_document.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_unique_scales.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_coms.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_coupler_types.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_data_override.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_ensemble_manager.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_unit_testing.F90
)

# Tier B -- depends on Tier A
#   MOM_file_parser    needs MOM_coms, MOM_document, MOM_error_handler,
#                      MOM_string_functions, MOM_time_manager
target_sources(mom6_framework PRIVATE
    ${MOM6_FRAMEWORK_DIR}/MOM_file_parser.F90
)

# Tier C -- depends on Tier B
#   MOM_unit_scaling   needs MOM_error_handler, MOM_file_parser
#   MOM_domains        needs MOM_coms_infra, MOM_cpu_clock, MOM_domain_infra,
#                      MOM_error_handler, MOM_file_parser, MOM_io_infra,
#                      MOM_string_functions, MOM_unit_scaling
target_sources(mom6_framework PRIVATE
    ${MOM6_FRAMEWORK_DIR}/MOM_unit_scaling.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_domains.F90
)

# Tier D -- depends on Tier C
#   MOM_hor_index      needs MOM_domains, MOM_error_handler, MOM_file_parser
target_sources(mom6_framework PRIVATE
    ${MOM6_FRAMEWORK_DIR}/MOM_hor_index.F90
)

# Tier E -- depends on Tier D
#   MOM_dyn_horgrid    needs MOM_array_transform, MOM_domains, MOM_error_handler,
#                      MOM_hor_index, MOM_unit_scaling
#   MOM_random         needs MOM_hor_index, MOM_time_manager
#   MOM_checksums      needs MOM_array_transform, MOM_coms, MOM_error_handler,
#                      MOM_file_parser, MOM_hor_index, MOM_murmur_hash
#   MOM_netcdf         needs MOM_error_handler, MOM_io_infra, netcdf
#   MOM_io_file        needs MOM_domains, MOM_error_handler, MOM_hor_index,
#                      MOM_io_infra, MOM_netcdf
target_sources(mom6_framework PRIVATE
    ${MOM6_FRAMEWORK_DIR}/MOM_dyn_horgrid.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_random.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_checksums.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_netcdf.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_io_file.F90
)

# Three src/framework/ files are compiled as part of mom6_ocean (mom6_build/src/CMakeLists.txt)
# because they depend on modules outside src/framework/ and src/core/:
#   MOM_diag_mediator       needs MOM_EOS, MOM_interface_heights, MOM_variables
#   MOM_diag_remap          needs MOM_EOS, MOM_regridding, MOM_remapping, coord_* modules
#   MOM_horizontal_regridding needs MOM_debugging (src/diagnostics/)

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

# Layer 5 (mom6_io): I/O modules that need mom6_grid (Layer 4).
# mom6_grid is defined in src/core/CMakeLists.txt, which is processed before
# this file because core/ is listed first in src/CMakeLists.txt.
# Sources come from both src/framework/ and config_src/infra/${TURBO_INFRA}/.

# Tier A -- depends only on mom6_grid + lower layers
#   MOM_io             needs MOM_array_transform, MOM_domains, MOM_dyn_horgrid,
#                      MOM_ensemble_manager, MOM_error_handler, MOM_file_parser,
#                      MOM_grid, MOM_io_file, MOM_io_infra, MOM_string_functions,
#                      MOM_verticalGrid, netcdf
add_library(mom6_io STATIC
    ${MOM6_FRAMEWORK_DIR}/MOM_io.F90
)

# Tier B -- depends on Tier A (MOM_io)
#   MOM_interp_infra   needs MOM_io plus FMS modules (horiz_interp_mod, etc.)
#                      Source lives in config_src/infra/ but placed here because
#                      it depends on MOM_io which is above the infra layer.
#   MOM_get_input      needs MOM_error_handler, MOM_file_parser, MOM_io, posix
#   MOM_write_cputime  needs MOM_coms, MOM_error_handler, MOM_file_parser,
#                      MOM_io, MOM_time_manager
target_sources(mom6_io PRIVATE
    ${MOM6_DIR}/config_src/infra/${TURBO_INFRA}/MOM_interp_infra.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_get_input.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_write_cputime.F90
)

# Tier C -- depends on Tier B
#   MOM_interpolate    needs MOM_array_transform, MOM_error_handler,
#                      MOM_interp_infra, MOM_time_manager
#   MOM_restart        needs MOM_array_transform, MOM_checksums, MOM_domains,
#                      MOM_error_handler, MOM_file_parser, MOM_grid, MOM_io,
#                      MOM_string_functions, MOM_time_manager, MOM_verticalGrid
target_sources(mom6_io PRIVATE
    ${MOM6_FRAMEWORK_DIR}/MOM_interpolate.F90
    ${MOM6_FRAMEWORK_DIR}/MOM_restart.F90
)

add_library(MOM6::io ALIAS mom6_io)

set_target_properties(mom6_io PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod/io
)

target_include_directories(mom6_io
    INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod/io>
)

target_link_libraries(mom6_io
    PUBLIC MOM6::grid
)
