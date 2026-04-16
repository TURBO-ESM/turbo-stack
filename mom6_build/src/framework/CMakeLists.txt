set(MOM6_FRAMEWORK_DIR ${MOM6_DIR}/src/framework)

add_library(mom6_framework STATIC
    ${MOM6_FRAMEWORK_DIR}/MOM_string_functions.F90
)
add_library(MOM6::framework ALIAS mom6_framework)

set_target_properties(mom6_framework PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod
)

target_include_directories(mom6_framework
    INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>
)
