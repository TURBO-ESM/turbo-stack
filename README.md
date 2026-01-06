[![turbo-stack CI tests](https://github.com/TURBO-ESM/turbo-stack/actions/workflows/ci-tests.yml/badge.svg)](https://github.com/TURBO-ESM/turbo-stack/actions/workflows/ci-tests.yml)

# TURBO Stack

Welcome to the *TURBO Stack* repository, the central software hub for the TURBO project.
This repository brings together various components that make up the TURBO Stack, including:

 - [MOM6](https://github.com/TURBO-ESM/MOM6)
 - [FMS](https://github.com/TURBO-ESM/FMS)
 - [MARBL](https://github.com/marbl-ecosys/MARBL)
 - development and testing utilities
 - and future libraries and components that will be developed as part of the TURBO project.

## Getting Started

Clone the repository (along with all submodules):

```bash
git clone --recursive https://github.com/TURBO-ESM/turbo-stack.git
```


### Building the MOM6 executable on derecho:
Build the standalone MOM6 executable:

```bash 
cd turbo-stack/
./build.sh
```

On derecho, prepend the build command with `qcmd -A <project_code> --`

Optionally, you can specify a compiler other than the default `intel`, e.g.,

```bash
./build.sh --compiler gnu
```

Once the build is complete, the executable will be at `bin/[COMPILER]/MOM6/MOM6`.


### Building the MOM6 executable on other machines:

To port this repository to a new machine, create a new makefile template in the `build-utils/makefile-templates/`
directory, following the naming convention `[MACHINE_NAME]-[COMPILER].mk`. You can use the existing templates as a reference.

Once the template is created, you can build the MOM6 executable using the `build.sh` script by 
specifying the machine name and compiler, e.g., 

```bash
./build.sh --machine ubuntu --compiler gnu
```

#### Building with different infrastructure backends:

MOM6 can be built either with FMS2 or with the new Turbo Infrastructure for MOM (TIM) layer backed by AMReX.  The options to enable this are:

```bash
./build.sh ... --infra TIM
```

This will use the new TIM library and interface with MOM6 and will build AMReX as needed from source locally.

To leverage a pre-existing AMReX install, do:

```bash
./build.sh ... --infra TIM --amrex /path/to/amrex/install
```

 The AMReX path should be the top level install directory which contains `lib`, `include`, etc.  The AMReX install must be built with Fortran and Fortran interfaces activated which are currently not the default (see [the customization options here](https://amrex-codes.github.io/amrex/docs_html/BuildingAMReX.html#customization-options) for more options).

See the TURBO specific [Makefile](build-utils/amrex-utils/Makefile) that builds AMReX with the current needed options.

### Running example experiments

To run one of the lightweight examples, such as `double_gyre`, you can execute the `MOM6` executable directly:

```bash
cd examples/double_gyre/
../../bin/intel/MOM6/MOM6
```

For computationally more expensive examples, such as `benchmark`, you need to run MOM6 in parallel.

```bash
mpirun ../../bin/intel/MOM6/MOM6
```

Example job submission scripts are provided in all of the example directories. Make sure to adjust 
the project code and specify the COMPILER you used for the build in the script.

Once the run is complete, the model output files will be in the example directory.
To *archive* the output files, you can run:

```bash
make archive
```
This will create a copy of the output files in the `archive/` directory, with a timestamp indicating when the archive was created.
To clean up an example directory, i.e., to remove all untracked output files (except the archive), you can run:

```bash
make clean
```

### Running unit tests
To build and run the unit tests instead of building MOM6, you can add `--unit-tests-only` to the build command.

This will run the unit tests in the test directory and will produce output similar to:

```
Test project /path/to/turbo/unit-tests
    Start 1: infra_tests
1/1 Test #1: infra_tests ......................   Passed    0.54 sec

100% tests passed, 0 tests failed out of 1

Total Test time (real) =   0.54 sec
make: Leaving directory '/path/to/turbo/unit-tests'
Finished build at Mon Jan  1 00:00:00 PM MST 1970
```
