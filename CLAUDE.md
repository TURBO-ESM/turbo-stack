# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TURBO Stack** is the central software hub for the TURBO (Towards Understanding the Representation of the Biological Ocean) Earth System Modeling project. It integrates MOM6 (ocean circulation), FMS (infrastructure), MARBL (marine biogeochemistry), and TIM (new AMReX-based infrastructure backend) into a unified build environment.

## Build Commands

Requires `SPACK_ROOT` and `TURBO_STACK_ROOT` to be set (add to your shell profile).

### Local build (configure + build + test)
```bash
scripts/build.sh              # incremental build
scripts/build.sh --debug      # full clean rebuild (--fresh + --clean-first)
scripts/build.sh --recreate-spack-env --debug  # also recreate spack env
```

### Script structure

| Script | Purpose |
|--------|---------|
| `scripts/build.sh` | Top-level entry point: spack env setup + activation, then calls `build_turbo_stack.sh` |
| `scripts/build_turbo_stack.sh` | CMake configure → build → ctest. Safe to call directly if spack env is already active. |

### build.sh options
- `--debug` — full clean rebuild (passed through to `build_turbo_stack.sh`)
- `--create-spack-env` — create the spack environment if it does not exist
- `--recreate-spack-env` — delete and recreate the spack environment from scratch

### build_turbo_stack.sh options
- `--debug` — adds `--fresh` to cmake configure and `--clean-first` to cmake build
- `--build_dir DIR` — override build directory (default: `$TURBO_STACK_ROOT/build/default`)

### Spack environment
Defined in `spack/spack.yaml`. Default environment name: `turbo_stack`. Includes ninja (default CMake generator), MPI (OpenMPI), NetCDF, FMS, and pFUnit.

**AMReX mini-app tests** are built with CMake separately (see `src/amrex_mini_app/CMakeLists.txt`). They use GoogleTest (C++) and require HDF5.

## Architecture

### Component Relationships

```
build.sh (spack setup + activation)
  └─→ build_turbo_stack.sh (CMake orchestrator)
        ├─→ cmake configure (Ninja, finds FMS/MPI/NetCDF/pFUnit via spack)
        ├─→ cmake build
        └─→ ctest

CMakeLists.txt (repo root)
  ├─→ mom6_build/  (MOM6 framework + infra wrapper targets)
  │     ├─→ MOM6::framework_base, MOM6::infra, MOM6::framework
  │     ├─→ MOM6::grid, MOM6::io
  │     └─→ MOM6::CVMix, MOM6::GSW  (pkg/ subdir)
  └─→ tests/  (pFUnit unit tests, 40 tests, MPI-aware)

src/amrex_mini_app/ (C++ / CMake — separate build)
  └─→ AMReX tripolar grid development sandbox
```

### Key Directories

| Path | Purpose |
|------|---------|
| `submodules/` | All external dependencies (MOM6, FMS, MARBL, amrex, TIM, pFUnit, CESM_share) |
| `build-utils/makefile-templates/` | Legacy compiler × machine makefile fragments (mkmf era — being retired) |
| `build-utils/mkmf/` | Legacy GFDL makefile generator (being retired in favour of CMake) |
| `tests/` | Fortran unit tests (pFUnit, MPI-aware via `@test(npes=[1,2,4])`) |
| `src/amrex_mini_app/` | C++ development sandbox for AMReX-based tripolar grid |
| `examples/` | Reference simulation configurations (double_gyre, benchmark, cesm grids) |
| `dev-utils/gcovlens/` | Code coverage aggregation tooling |

### Infrastructure Backends

- **FMS2** — traditional Flexible Modeling System; the stable default path
- **TIM** — TURBO Infrastructure for MOM; new AMReX-backed layer under active development (CMake integration in progress)

### Language Split

- **Fortran** — MOM6, FMS, MARBL, unit tests under `tests/`
- **C++20** — AMReX mini-app (`src/amrex_mini_app/`), GoogleTest-based tests there
- **Bash** — `scripts/build.sh`, `scripts/build_turbo_stack.sh` build orchestration

## CI/CD

GitHub Actions workflows (`.github/workflows/`) test against a matrix of compilers (oneapi, gcc14, nvhpc, clang) and MPI libraries (MPICH, OpenMPI) on both `ubuntu-latest` and the custom `gha-runner-turbo` runner.

Containers used: `ncarcisl/cisldev-x86_64-almalinux9-[compiler]-[mpi]`; activated via `/container/config_env.sh`.

Clang-format (Google style, C++20, 120-char limit) is enforced on PRs and auto-applied on pushes to `main`.

## Code Style

C++ files must pass `clang-format` (config in `.clang-format`): Google style base, C++20, 120-char line limit, Allman braces.
