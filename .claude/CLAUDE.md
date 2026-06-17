# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TURBO Stack** is the central software hub for the TURBO project. It integrates MOM6, FMS , MARBL, and TIM (new AMReX-based infrastructure backend) into a unified build environment.

## Build Commands

Requires `TURBO_STACK_ROOT` (and, for the spack flavor, `SPACK_ROOT`) to be set in your shell profile. See [`scripts/README.md`](scripts/README.md) for the full reference.

### 2-step pipeline

```
setup environment (toolchain + any from-source deps)  →  build turbo-stack
```

Different flavors fill in step 1 differently; step 2 is always the same. Per-machine env scripts under `scripts/setup_environment/` own the call list of `build_dep` invocations for that machine.

### Local build (spack flavor, one command)

```bash
scripts/build_with_spack.sh                              # incremental build
scripts/build_with_spack.sh --debug                      # full clean rebuild
scripts/build_with_spack.sh --infra TIM                  # FMS2 default; --infra TIM also builds TIM from source
scripts/build_with_spack.sh --recreate-spack-env --debug # nuke + recreate the spack env, then clean rebuild
```

`build_with_spack.sh` options: `--debug`, `--ninja`, `--build_dir DIR`, `--infra FMS2|TIM`, `--parallel N`, `--recreate-spack-env`.

### Explicit two-step (any flavor; faster iteration)

```bash
# spack flavor
source scripts/setup_environment/spack_local_environment.sh
scripts/build_turbo_stack.sh
# (for --infra TIM, also `source scripts/build_dep.sh` + a `build_dep tim ...` call first)

# module flavor (laptop emulation of Derecho — temp until derecho_cpu_gcc_openmpi.sh is fully verified)
source scripts/setup_environment/emulate_derecho_modules_locally_with_spack.sh
scripts/build_turbo_stack.sh
```

### Script structure

| Script | Role | How invoked |
|---|---|---|
| `scripts/build_with_spack.sh` | Orchestrator: runs the full pipeline for the spack flavor | exec'd |
| `scripts/setup_environment/<flavor>.sh` | Step 1 — toolchain load + per-machine `build_dep` calls | sourced |
| `scripts/build_dep.sh` | Library — defines `build_dep <name> ... -- [cmake args]` | sourced |
| `scripts/fetch_source.sh` | Library — defines `fetch_source` for source-only-consumed deps (MOM6, MARBL) | sourced |
| `scripts/build_turbo_stack.sh` | Step 2 — cmake configure + build + ctest. No spack or infra knowledge. | exec'd |

`build_turbo_stack.sh` options: `--debug`, `--ninja`, `--build_dir DIR`, `--infra FMS2|TIM`, `--parallel N`.

### Where dep builds + installs land

The orchestrators derive deps location from `--build_dir`: `<build_dir>/deps/{build,install}/`. With no `--build_dir`, deps land at `$TURBO_STACK_ROOT/deps/default/`. To override the deps location independently of the turbo-stack build dir, source the env script directly with `--deps-build-root DIR`.

### Parallel build jobs

`--parallel N` on the orchestrators exports `CMAKE_BUILD_PARALLEL_LEVEL=N` once; every downstream `cmake --build` (deps + turbo-stack) reads it natively. You can also set `CMAKE_BUILD_PARALLEL_LEVEL` in your shell profile to skip the CLI flag. When neither is set, cmake's own default applies (Make=1, Ninja=nproc).

### Source-tree overrides

`build_dep` resolves each dep's source via (first match wins): `--source PATH`, `--clone --url ... --ref ...`, `$<NAME>_ROOT` env var, or the corresponding submodule. So overriding any single dep with a local dev tree is:

```bash
export MOM6_ROOT=$HOME/projects/MOM6
export FMS_ROOT=$HOME/projects/FMS
source scripts/setup_environment/emulate_derecho_modules_locally_with_spack.sh
scripts/build_turbo_stack.sh
```

### Spack environment

Defined in `spack/spack.yaml`. Default env name: `turbo_stack`. Provides cmake, gmake, ninja, MPI (OpenMPI), NetCDF, pFUnit, AMReX. FMS and TIM are intentionally not in spack: `build_with_spack.sh` always calls `build_dep fms` (and `build_dep tim` when `--infra TIM`) so the build uses the local source tree (`$FMS_ROOT`/`$TIM_ROOT` or the submodule fallback). Turbo-stack tracks features ahead of the released FMS package, so linking against spack's FMS would risk quietly using a stale version.

A second spack env defined in `spack/derecho_modules_emulation_with_spack.yaml` provides *just* the toolchain (cmake, MPI, NetCDF) — used by the temporary emulation driver to exercise the from-source path on a laptop until Derecho access is back.

**AMReX mini-app tests** are built with CMake separately (see `src/amrex_mini_app/CMakeLists.txt`). They use GoogleTest (C++) and require HDF5.

## Architecture

### Component Relationships

```
build_with_spack.sh                                        ─── orchestrator (spack flavor)
  └─→ setup_environment/spack_local_environment.sh           step 1: toolchain (sourced)
  └─→ build_dep.sh + `build_dep tim ...`                     only when --infra TIM (sourced)
  └─→ build_turbo_stack.sh                                   step 2: configure+build+test (exec'd)
        ├─→ cmake configure (Unix Makefiles by default; --ninja for Ninja)
        ├─→ cmake build
        └─→ ctest

build_on_derecho.sh                                        ─── orchestrator (Derecho module flavor)
  └─→ setup_environment/derecho_cpu_gcc_openmpi.sh           step 1: modules + build_dep × 4 (sourced)
  └─→ build_turbo_stack.sh                                   step 2 (exec'd)

CMakeLists.txt (repo root)
  ├─→ TURBO::infra_r8  (interface lib wrapping the backend: FMS::fms_r8 or TIM::tim_r8)
  ├─→ marbl_build/  (MARBL::marbl, from submodules/MARBL)
  ├─→ mom6_build/  (MOM6 libraries, consumed from $MOM6_ROOT)
  │     ├─→ MOM6::ocean                 (top-level ocean model)
  │     ├─→ MOM6::framework, MOM6::infra
  │     └─→ MOM6::CVMix, MOM6::GSW      (pkg/ subdir)
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
