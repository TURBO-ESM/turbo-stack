# TURBO Unit Tests

Unit testing is implemented using [pFUnit](https://github.com/Goddard-Fortran-Ecosystem/pFUnit) tests and built using [CMake](https://cmake.org/cmake/help/latest/).

## Running tests
To run the unit tests, build TURBO following the [parent directory README](../README.md).

## Adding tests
To add unit tests, first determine if you need to add another directory or another file.

To create a new directory of tests, create a new directory in `tests` (for example, `new_interface`) and create a new `CMakeLists.txt` file in that directory. 

Once you have your test file (`test_subroutine.pf` for example), add the following line to the `CMakeLists.txt`:

```cmake
add_mom_test(test_module PFUNIT_FILE test_module.pf)
```

This creates a cmake target called test_module and adds the pfunit file `test_module.pf` to the target binary.

Lastly, you will need to add the directory to the main CMakeLists.txt file in the `tests` directory: `add_subdirectory(new_interface)`.  This tells CMake to evaluate the `new_interface` directory for its own `CMakeLists.txt` file created above.

To add another unit test file, simply add the appropriate file (for example, `test_module.pf`) to the needed directory.  Then in the `CMakeLists.txt` file, add the following line below the other `add_mom_test` calls:

```cmake
add_mom_test(test_module PFUNIT_FILE test_module.pf)
```

### Runtime file requirements
CMake provides the utility to add runtime files to the test directory.  For example, tests requiring `mpp` require a Fortran namelist file named `input.nml` residing in the same directory as the test binary.

To add a small file to the test runtime directory, add the source file needed (for example, `input.nl` ) to the `tests/config` directory.

Then in the CMakeLists.txt for that test, add the following line:
```cmake
configure_file(${CONFIG_FILES}/input.nml input.nml COPYONLY)
```

This will copy the file from the `config` directory to the build directory where the test resides making it available at runtime to the tests.

> [!NOTE]
> While transitioning to AMReX, the backend **REQUIRES** an `input.nml` in the same directory as the target binary.
> So for new test directories, this will be required otherwise the test will fail.

In this case, we are copying the file as is but CMake provides the ability to templatize source files and modify them per file as needed.  For more information, see the [CMake documentation](https://cmake.org/cmake/help/latest/command/configure_file.html#example).

## Writing tests

There is a large amount of literature on how to write effective unit tests which is out of scope of this documentation.  For examples and best practices, see [Microsofts Engineering Playbook](https://microsoft.github.io/code-with-engineering-playbook/automated-testing/unit-testing/), [Martin Fowler's thoughts on best practices](https://martinfowler.com/testing/), or even [CircleCI's comments](https://circleci.com/blog/unit-testing-vs-integration-testing/) on integration vs. unit testing.

For our use case, we will be leveraging pFUnit which has a series of built in API's to help verify program state.

To start, follow the general example from the pFUnit examples:

```fortran
! module_tests.pf
module module_tests
  use pfunit
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

### MPI based tests

As most of the testing for MOM will require MPI, there will need to be a few changes in your pfunit test file:

```fortran
module subroutine_tests
  use pfunit
  use MOM_coms_infra
  use MOM_test_case
  implicit none

  @testCase()
  type, extends(MOM_MPI_test_case) :: module_under_test_case
  end type module_under_test

contains
...
```
This tells pfunit to extend the base `MOM_MPI_test_case` module which includes helper functions which setup and tear down the environment to run MPI driven tests

Your test will also need to be modified as well:

```fortran
...
contains

  @test(npes=[4])
  subroutine test_functionality(this)
    class (MOM_comms_infra_test_case), intent(inout) :: this
    ! module level parameters for test and calls to appropiate module APIs.

    ! @assert* calls
  end subroutine test_functionality
end module subroutine_tests
```

The additional components are:

1) `@test(npes=[4])` tells pfunit to run the test on different levels of PEs.  This parameter can be a list of PE's as well (`@test(npes=[1,2,4,8])`) and pfunit will run the test for each configuration of PEs so long as they are less than or equal to the `MAX_PES` parameter provided to the cmake target from above.

> [!WARNING]
> There is a bug in MOM infra where we are not deallocating data on finalize preventing reuse of test cases with multiple PEs and multiple test methods within a single pfunit module:
> 
> ```
> Fortran runtime error: Attempting to allocate already allocated variable 'nonblock_data'
> 
> Error termination. Backtrace:
> At line 82 of file /glade/u/home/mwaxmonsky/source/turbo-mwaxmonsky-temp/submodules/FMS/mpp/include/mpp_domains_misc.inc
> ...
> ```
> 
> So it is not possible at this time to have more than one test or multiple PEs tested within the same file.
> So for the time being, each test must have its own file and cmake target until this cen be mitigated.

2) The subroutine signature changes to `subroutine test_functionality(this)` and a variable declaration `class (module_under_test_case), intent(inout) :: this` are needed to satisfy pfunit and to allow the developer to access MPI intrinsics from within the test case (see the [pfunit MPI test case class](https://github.com/Goddard-Fortran-Ecosystem/pFUnit/blob/main/src/pfunit/core/MpiTestParameter.F90) for more functions.)
