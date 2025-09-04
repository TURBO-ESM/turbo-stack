# Tripolar Grid using AMReX Development Test

A minimal working example implementing the communication pattern needed for tripolar grids in AMReX.

## Prerequisites

- The environment variable `TURBO_STACK_ROOT` should point to the directory where you cloned the [turbo-stack repository](https://github.com/TURBO-ESM/turbo-stack/).
- [spack](https://spack.io/)

## Build, Run, and Test
If you have spack installed on your system then the script build_and_run.sh should be all you need to get started. That script:
- installs all other dependencies (cmake, amrex, etc...) in a spack environment 
- activates that spack environmet
- builds the tripolar grid amrex library and examples using cmake
- tests the code
- runs the tripolar grid example
