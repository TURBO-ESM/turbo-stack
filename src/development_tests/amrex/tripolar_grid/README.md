# Tripolar Grid using AMReX Development Test

A minimal working example implementing the communication pattern needed for tripolar grids in AMReX.

## Prerequisites

- The environment variable `TURBO_STACK_ROOT` should point to the directory where you cloned the [turbo-stack repository](https://github.com/TURBO-ESM/turbo-stack/).
- [spack](https://spack.io/)

## Build and Run
If you have spack installed on you system then the script build_and_run.sh should be all you need to get started. That scirpt:
- installs all other dependencies (cmake, amrex, etc...) in a spack environment 
- activates that spack environmet
- builds the tripolar grid amrex example using cmake
- runs it
