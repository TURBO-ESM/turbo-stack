# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TURBO Stack** is the central software hub for the TURBO project. It integrates MOM6, FMS , MARBL, and TIM (new AMReX-based infrastructure backend) into a unified build environment.

## Build Commands

Scripts self-locate `TURBO_STACK_ROOT` (set it only to override; `SPACK_ROOT` is needed for the spack flavor). See [`scripts/README.md`](scripts/README.md) for the full reference, including the **dependency tier contract** (`docs/dependency_tiers.png`).

### 3-stage pipeline

```
Tier-1 toolchain (modules/spack; builds nothing)  →  Tier-2 deps (explicit turbo_build_*)  →  build turbo-stack
```

Different machines fill in stage 1 (and which Tier-2 deps need building) differently; stage 3 is always the same. The `setup_environment/` recipes are **toolchain-only** — they build no dependencies. The single-backend builders run all three stages; the end-to-end test drivers run a builder once per backend over the shared core in `scripts/lib/common.sh`.

### Local test, both backends (end-to-end)

```bash
./test_turbo_stack_locally.sh                      # spack; builds + ctests FMS2 and TIM
./test_turbo_stack_locally.sh --only TIM --clean   # one backend, from scratch
```

Mirrors `test_turbo_stack_on_derecho.sh` (the Derecho driver); each runs the real single-backend builder once per backend and prints a per-backend matrix/verdict.

### Local build (spack flavor, one command)

```bash
scripts/build_local_with_spack_env.sh                              # build (default backend infra FMS2, Release)
scripts/build_local_with_spack_env.sh --debug                      # Debug build
scripts/build_local_with_spack_env.sh --clean                      # Clean rebuild from scratch
scripts/build_local_with_spack_env.sh --infra TIM                  # infra is FMS2 as default; --infra TIM also builds TIM from source
scripts/build_local_with_spack_env.sh --recreate-spack-env --clean # nuke + recreate the spack env, then clean rebuild
```

`build_local_with_spack_env.sh` options: `--debug`, `--clean`, `--ninja`, `--build_dir DIR`, `--infra FMS2|TIM`, `--parallel N`, `--recreate-spack-env`.

### Explicit, iterative (any flavor; faster iteration)

```bash
source scripts/lib/common.sh                                 # turbo_build_* + helpers
source scripts/setup_environment/spack_local_environment.sh  # Tier-1 (spack); builds nothing
deps="$TURBO_STACK_ROOT/deps/default"
turbo_build_fms "$deps/build" "$deps/install"                # Tier-2 (spack supplies pFUnit/AMReX)
scripts/build_turbo_stack.sh                                 # Tier-3 (FMS2); --infra TIM after turbo_build_tim
```

The `setup_environment/` recipes only set up the toolchain — build Tier-2 deps explicitly via the `turbo_build_*` wrappers (canonical flags live in `scripts/lib/common.sh`).

### Script structure

| Script | Role | How invoked |
|---|---|---|
| `scripts/lib/common.sh` | Shared core — root resolution, arg parsing, `turbo_build_*` (Tier-2 canonical flags), matrix/verdict | sourced |
| `test_turbo_stack_locally.sh`, `test_turbo_stack_on_derecho.sh` (repo root) | End-to-end drivers — run a single-backend builder per backend (shared core) | exec'd |
| `scripts/build_local_with_spack_env.sh`, `build_on_derecho.sh` | Single-backend orchestrators (spack / modules) | exec'd |
| `scripts/setup_environment/<flavor>.sh` | Stage 1 — Tier-1 toolchain ONLY (no dep builds) | sourced |
| `scripts/lib/build_dep.sh` | Library — defines `build_dep <name> ... -- [cmake args]` | sourced |
| `scripts/lib/fetch_source.sh` | Library — defines `fetch_source` for source-only-consumed deps (MOM6, MARBL) | sourced |
| `scripts/build_turbo_stack.sh` | Stage 3 — cmake configure + build + ctest. No spack or infra knowledge. | exec'd |

`build_turbo_stack.sh` options: `--debug`, `--clean`, `--ninja`, `--build_dir DIR`, `--infra FMS2|TIM`, `--parallel N`.

### Where dep builds + installs land

The orchestrators derive deps location from `--build_dir`: `<build_dir>/deps/{build,install}/`. With no `--build_dir`, deps land at `$TURBO_STACK_ROOT/deps/default/`; the end-to-end test drivers build each backend under `$TURBO_BUILD_SYSTEM_TEST_DIR/turbo-stack-with-<backend>/` (deps in its `deps/` subdir). In the explicit flow you pass the build/install roots straight to the `turbo_build_*` wrappers.

### Parallel build jobs

`--parallel N` on the orchestrators exports `CMAKE_BUILD_PARALLEL_LEVEL=N` once; every downstream `cmake --build` (deps + turbo-stack) reads it natively. You can also set `CMAKE_BUILD_PARALLEL_LEVEL` in your shell profile to skip the CLI flag. When neither is set, cmake's own default applies (Make=1, Ninja=nproc).

### Source-tree overrides

`build_dep` resolves each dep's source via (first match wins): `--source PATH`, `--clone --url ... --ref ...`, `$<NAME>_ROOT` env var, or the corresponding submodule. So overriding any single dep with a local dev tree is:

```bash
export MOM6_ROOT=$HOME/projects/MOM6
export FMS_ROOT=$HOME/projects/FMS
./test_turbo_stack_locally.sh    # matrix shows each component as (override) vs (submodule)
```

### Spack environment

Defined in `spack/spack.yaml`. Default env name: `turbo_stack`. Provides cmake, gmake, ninja, MPI (OpenMPI), NetCDF, pFUnit, AMReX. FMS and TIM are intentionally not in spack: `build_local_with_spack_env.sh` builds the selected backend via `turbo_build_fms`/`turbo_build_tim` (in `scripts/lib/common.sh`) from the local source tree (`$FMS_ROOT`/`$TIM_ROOT` or the submodule fallback). Turbo-stack tracks features ahead of the released FMS package, so linking against spack's FMS would risk quietly using a stale version.

**AMReX mini-app tests** are built with CMake separately (see `src/amrex_mini_app/CMakeLists.txt`). They use GoogleTest (C++) and require HDF5.

## Architecture

### Component Relationships

```
build_local_with_spack_env.sh                                        ─── orchestrator (spack flavor)
  └─→ setup_environment/spack_local_environment.sh           Tier 1: toolchain (sourced)
  └─→ turbo_build_fms / turbo_build_tim  (lib/common.sh)     Tier 2: selected backend
  └─→ build_turbo_stack.sh                                   Tier 3: configure+build+test (exec'd)
        ├─→ cmake configure (Unix Makefiles by default; --ninja for Ninja)
        ├─→ cmake build
        └─→ ctest

build_on_derecho.sh                                        ─── orchestrator (Derecho module flavor)
  └─→ setup_environment/derecho_cpu_gcc_openmpi.sh           Tier 1: Lmod modules only (sourced)
  └─→ turbo_build_{pfunit,fms,amrex,tim}  (lib/common.sh)    Tier 2: deps (per --infra)
  └─→ build_turbo_stack.sh                                   Tier 3 (exec'd)

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
