# What to build
option(TURBO_BUILD_UNIT_TESTS "Build pFUnit unit tests" ON)

# Compiler-specific features (guarded in TurboCompilerFlags.cmake)
option(TURBO_CODECOV  "Enable code coverage instrumentation (GNU only)" OFF)
