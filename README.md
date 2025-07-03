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


### Building the MOM6 executable
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
