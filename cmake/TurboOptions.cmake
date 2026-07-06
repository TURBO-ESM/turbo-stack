# What to build.
# Unit tests are opt-in: a plain build produces a runnable executable without
# compiling pFUnit or the test suite.  The orchestrators expose --with-tests to
# flip this ON; the end-to-end test drivers always force it ON.
option(TURBO_BUILD_UNIT_TESTS "Build pFUnit unit tests" OFF)

# Compiler-specific features (guarded in TurboCompilerFlags.cmake)
option(TURBO_CODECOV  "Enable code coverage instrumentation (GNU only)" OFF)
