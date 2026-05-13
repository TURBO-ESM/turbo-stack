# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TURBO Stack** is the central software hub for the TURBO (Towards Understanding the Representation of the Biological Ocean) Earth System Modeling project. It integrates MOM6 (ocean circulation), FMS (infrastructure), MARBL (marine biogeochemistry), and TIM (new AMReX-based infrastructure backend) into a unified build environment.

## Build Commands

Requires `TURBO_STACK_ROOT` (and, for the spack flavor, `SPACK_ROOT`) to be set in your shell profile. See [`scripts/README.md`](scripts/README.md) for the full reference; the design rationale lives in [`setup_env_separation_plan.md`](setup_env_separation_plan.md).

### 3-step pipeline

```
setup environment  →  build dependencies from source  →  build turbo-stack
```

Different flavors fill in steps 1 and 2 differently; step 3 is always the same.

### Local build (spack flavor, one command)

```bash
scripts/build_with_spack.sh                              # incremental build
scripts/build_with_spack.sh --debug                      # full clean rebuild
scripts/build_with_spack.sh --infra TIM                  # FMS2 default; --infra TIM also builds TIM from source
scripts/build_with_spack.sh --recreate-spack-env --debug # nuke + recreate the spack env, then clean rebuild
```

### Explicit two-step (any flavor; faster iteration)

```bash
# spack flavor
source scripts/setup_environment/with_spack.sh
scripts/build_turbo_stack.sh
# (for --infra TIM, also `source scripts/build_dependencies_from_source.sh --only tim` first)

# module flavor (laptop emulation of Derecho — temp until env/derecho.sh exists)
source scripts/setup_environment/derecho_modules_emulation_with_spack.sh
scripts/build_turbo_stack.sh
```

### Script structure

| Script | Role | How invoked |
|---|---|---|
| `scripts/build_with_spack.sh` | Orchestrator: runs the full pipeline for the spack flavor | exec'd |
| `scripts/setup_environment/<flavor>.sh` | Step 1 — toolchain + (for module flavors) builds deps | sourced |
| `scripts/build_dependencies_from_source.sh` | Step 2 — cmake-builds FMS/pFUnit/AMReX/TIM into a per-tag prefix; per-dep `--no-X` / `--only LIST` toggles | sourced |
| `scripts/build_turbo_stack.sh` | Step 3 — cmake configure + build + ctest. No spack or infra knowledge. | exec'd |

`build_turbo_stack.sh` options: `--debug`, `--ninja`, `--build_dir DIR`, `--infra FMS2|TIM`.

### Source-tree overrides

`build_dependencies_from_source.sh` reads `MOM6_ROOT` / `FMS_ROOT` / `TIM_ROOT` / `PFUNIT_ROOT` / `AMREX_ROOT`. If set, those paths are used; otherwise the corresponding submodule is used. Useful for iterating against local dev trees:

```bash
export MOM6_ROOT=$HOME/projects/MOM6
source scripts/setup_environment/derecho_modules_emulation_with_spack.sh
scripts/build_turbo_stack.sh
```

### Spack environment

Defined in `spack/spack.yaml`. Default env name: `turbo_stack`. Provides cmake, gmake, ninja, MPI (OpenMPI), NetCDF, FMS, pFUnit, AMReX. The spack flavor only needs to build TIM from source (`--only tim`) since spack does not package TIM.

A second spack env defined in `spack/derecho_modules_emulation_with_spack.yaml` provides *just* the toolchain (cmake, MPI, NetCDF) — used by the temporary emulation driver to exercise the from-source path on a laptop until Derecho access is back.

**AMReX mini-app tests** are built with CMake separately (see `src/amrex_mini_app/CMakeLists.txt`). They use GoogleTest (C++) and require HDF5.

## Architecture

### Component Relationships

```
build_with_spack.sh                                        ─── orchestrator (spack flavor)
  └─→ setup_environment/with_spack.sh                          step 1 (sourced)
  └─→ build_dependencies_from_source.sh --only tim             step 2, only when --infra TIM (sourced)
  └─→ build_turbo_stack.sh                                     step 3 (exec'd)
        ├─→ cmake configure (Unix Makefiles by default; --ninja for Ninja)
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
- **Bash** — build orchestration under `scripts/` (see [`scripts/README.md`](scripts/README.md))

## CI/CD

GitHub Actions workflows (`.github/workflows/`) test against a matrix of compilers (oneapi, gcc14, nvhpc, clang) and MPI libraries (MPICH, OpenMPI) on both `ubuntu-latest` and the custom `gha-runner-turbo` runner.

Containers used: `ncarcisl/cisldev-x86_64-almalinux9-[compiler]-[mpi]`; activated via `/container/config_env.sh`.

Clang-format (Google style, C++20, 120-char limit) is enforced on PRs and auto-applied on pushes to `main`.

## Code Style

C++ files must pass `clang-format` (config in `.clang-format`): Google style base, C++20, 120-char line limit, Allman braces.
