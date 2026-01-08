# TURBO Unit Tests

Unit testing is implemented using [pFUnit](https://github.com/Goddard-Fortran-Ecosystem/pFUnit) tests and built using [CMake](https://cmake.org/cmake/help/latest/).

## Running tests
To run the unit tests, build TURBO following the [parent directory README](../README.md).

## Adding tests
To add unit tests, first determine if you need to add another directory or another file.

To create a new directory of tests, create a new directory in `tests` (for example, `new_interface`) and create a new `CMakeLists.txt` file in that directory.  The new `CMakeLists.txt` file should look like:

```cmake
add_pfunit_ctest(new_interface_tests
  TEST_SOURCES new_module_tests.pf
  LINK_LIBRARIES NetCDF_Fortran NetCDF FMS_Infra FMS ${AMREX_LIB}
)
set_property(TARGET new_interface_tests PROPERTY LINKER_LANGUAGE Fortran)
```

This will create a new target called `new_interface_tests`, create a test binary incorporating the tests in `new_module_tests.pf` and allow that to be runnable under ctest.

The `LINK_LIBRARIES` line might have to be changed depending on your testing needs and if you are testing multiple fortran modules, you should create a unique `*.pf` unit test file per module and have those be the values passed to the `TEST_SOURCES` list: `TEST_SOURCES module1_tests.pf module2_tests.pf ...`.

The `set_property` call is a temporary (but required for each target created with `add_pfunit_ctest`) to force cmake to use the Fortran linker instead of the C++ linker.  Once the cause of this bug is fixed, this should no longer be required.

Lastly, you will need to add the directory to the main CMakeLists.txt file in the `tests` directory: `add_subdirectory(new_interface)`.  This tells CMake to evaluate the `new_interface` directory for its own `CMakeLists.txt` file created above.

To add another unit test file, simply add the appropriate file (for example, `test_module.pf`) to the needed directory.  Then in the `CMakeLists.txt` file, find the `add_pfunit_ctest` call and add the file to the end of the `TEST_SOURCES` list:

```cmake
add_pfunit_ctest(test_target_name
  TEST SOURCES module1.pf your_new_module.pf
  ...
)
```

### Runtime file requirements
CMake provides the utility to add runtime files to the test directory.  For example, tests requiring `mpp` require a Fortran namelist file named `input.nml` residing in the same directory as the test binary.

To add a small file to the test runtime directory, add the source file needed (for example, `input.nl` ) to the `tests/config` directory.

Then in the CMakeLists.txt for that test, add the following line: `configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)`.  This will copy the file from the `config` directory to the build directory where the test resides making it available at runtime to the tests.

In this case, we are copying the file as is but CMake provides the ability to templatize source files and modify them per file as needed.  For more information, see the [CMake documentation](https://cmake.org/cmake/help/latest/command/configure_file.html#example).

## Writing tests

There is a large amount of literature on how to write effective unit tests which is out of scope of this documentation.  For examples and best practices, see [Microsofts Engineering Playbook](https://microsoft.github.io/code-with-engineering-playbook/automated-testing/unit-testing/), [Martin Fowler's thoughts on best practices](https://martinfowler.com/testing/), or even [CircleCI's comments](https://circleci.com/blog/unit-testing-vs-integration-testing/) on integration vs. unit testing.

For our use case, we will be leveraging pFUnit which has a series of built in API's to help verify program state.

To start, follow the general example from the pFUnit examples:

```fortran
! module_tests.pf
module module_tests
   use funit
   use module_under_test
   implicit none

contains

   @test
   subroutine test_module_function()
      ! Add module_under_test API calls and
      ! intermediate variables to track state data as needed here

      ! Insert @assert* statements here as needed
   end subroutine test_module_function

end module module_tests
```

This creates a new Fortran file/module called `module_tests`/`module_tests.pf` respectiveley and creates a test subroutine called `test_module_function` that will be interpreted as a test by pFUnit.

The setup of the temporary variables and the appropriate module API calls are up to the developer to determine the proper amount/depth of data needed for testing.

The proper `@assert*` calls will also depend on the functionality being verified and the data being used.  For a complete list of assert calls, see the [pFUnit source](https://github.com/Goddard-Fortran-Ecosystem/pFUnit/tree/main/src/funit/asserts) for a complete list.

For basic examples, see the [pFUnit examples repository](https://github.com/Goddard-Fortran-Ecosystem/pFUnit_demos). 
