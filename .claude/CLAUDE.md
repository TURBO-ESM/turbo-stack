# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TURBO Stack** is the central software hub for the TURBO project. It integrates MOM6, FMS , MARBL, and TIM (new AMReX-based infrastructure backend) into a unified build environment.

## Build Commands

Scripts self-locate `TURBO_STACK_ROOT` from their own location — you build the checkout you run from (`SPACK_ROOT` is needed for the spack flavor). To build against a local dev tree of a co-developed dependency, set its submodule override (`MOM6_ROOT` / `FMS_ROOT` / `TIM_ROOT`). See [`scripts/README.md`](scripts/README.md) for the full reference, including the **dependency tier contract** (`docs/dependency_tiers.png`).

### Two-stage pipeline

```
Stage 1 — environment setup (machine-specific):  toolchain [Tier 1]  +  turbo_build_* deps [AMReX/pFUnit = Tier 1.5, FMS/TIM = Tier 2]
Stage 2 — build turbo-stack (uniform):           build_turbo_stack.sh  →  Tier 3 (turbo-stack, MOM6, MARBL)
```

The dependency *tiers* (1 / 1.5 / 2 / 3) are a classification; the pipeline is what a machine actually runs (contrast `docs/dependency_tiers.png` with `docs/build_test_orchestration.png`). Only Stage 1 differs between machines — the toolchain provider, and which upstream deps come prebuilt vs are built from the submodule (e.g. spack supplies AMReX/pFUnit, Derecho builds them). Stage 2 is always the same. The `setup_environment/` recipes are **toolchain-only** — they build no dependencies; the upstream deps are built explicitly via `turbo_build_*`. The single-backend builders run both stages; the end-to-end test drivers run a builder once per backend over the shared core in `scripts/lib/common.sh`.

### Local test, both backends (end-to-end)

```bash
./test_turbo_stack_locally.sh                      # spack; builds + ctests FMS2 and TIM
./test_turbo_stack_locally.sh --only TIM --clean   # one backend, from scratch
```

Mirrors `test_turbo_stack_on_derecho.sh` (the Derecho driver); each runs the real single-backend builder once per backend and prints a per-backend matrix/verdict. `test_turbo_stack_with_system_toolchain.sh` is the same for a bring-your-own toolchain already on `PATH` (no spack).

### Local build (spack flavor, one command)

```bash
scripts/build_local_with_spack_env.sh                              # build (default backend infra TIM, Release)
scripts/build_local_with_spack_env.sh --debug                      # Debug build
scripts/build_local_with_spack_env.sh --clean                      # Clean rebuild from scratch (deps + turbo-stack)
scripts/build_local_with_spack_env.sh --tests                      # also build + run the pFUnit unit tests
scripts/build_local_with_spack_env.sh --infra FMS2                 # FMS2 backend instead of the default TIM
scripts/build_local_with_spack_env.sh --recreate-spack-env --clean # nuke + recreate the spack env, then clean rebuild
```

`build_local_with_spack_env.sh` options: `--debug`, `--clean`, `--ninja`, `--build_dir DIR`, `--infra FMS2|TIM`, `--tests`, `--parallel N`, `--recreate-spack-env`.

### Local build (from source, one command)

The closest replacement for the old `build.sh` on a laptop/workstation: bring your own toolchain (compilers, MPI, NetCDF, CMake already on `PATH` — system packages, Homebrew, an OS module system, or an already-activated Spack/Conda env) and turbo-stack builds **all** upstream submodule deps from source (pFUnit/AMReX + FMS/TIM), then builds turbo-stack. No spack, no modules; nothing is fetched — everything comes from `submodules/`.

```bash
scripts/build_local_with_system_toolchain.sh                    # build (default backend infra TIM, Release)
scripts/build_local_with_system_toolchain.sh --tests            # also build + run the pFUnit unit tests
scripts/build_local_with_system_toolchain.sh --infra FMS2       # FMS2 backend instead of the default TIM
scripts/build_local_with_system_toolchain.sh --clean            # clean rebuild from scratch (deps + turbo-stack)
```

`build_local_with_system_toolchain.sh` options: `--debug`, `--clean`, `--ninja`, `--build_dir DIR`, `--infra FMS2|TIM`, `--tests`, `--parallel N`. It sources `setup_environment/local_toolchain_on_path.sh` (verifies the toolchain is on `PATH`; builds nothing) — the same shape as `build_on_derecho.sh` minus the Lmod step.

### Explicit, iterative (any flavor; faster iteration)

```bash
source scripts/lib/common.sh                                 # turbo_build_* + helpers
source scripts/setup_environment/spack_local_environment.sh  # Stage 1: toolchain (spack); builds nothing → Tier 1
deps="$TURBO_STACK_ROOT/deps/default"
turbo_build_fms "$deps/build" "$deps/install"                # Stage 1: build FMS (Tier 2); spack supplies pFUnit/AMReX (Tier 1.5)
scripts/build_turbo_stack.sh --infra FMS2                    # Stage 2: build turbo-stack (Tier 3); use --infra TIM after turbo_build_tim,
                                                             # add --tests to also build + run ctest
```

The `setup_environment/` recipes only set up the toolchain — build the upstream deps (Tier 1.5 + Tier 2) explicitly via the `turbo_build_*` wrappers (canonical flags live in `scripts/lib/common.sh`).

### Script structure

| Script | Role | How invoked |
|---|---|---|
| `scripts/lib/common.sh` | Shared core — root resolution, arg parsing, `turbo_build_*` (Tier 1.5 + Tier 2 dep-build flags), the single-backend builder core (`turbo_run_backend_builder`), matrix/verdict | sourced |
| `test_turbo_stack_locally.sh`, `test_turbo_stack_on_derecho.sh` (repo root) | End-to-end drivers — run a single-backend builder per backend (shared core) | exec'd |
| `scripts/build_local_with_spack_env.sh`, `build_local_with_system_toolchain.sh`, `build_on_derecho.sh` | Single-backend orchestrators (spack / from-source local / modules) | exec'd |
| `scripts/setup_environment/<flavor>.sh` | Stage 1 (env setup) — toolchain ONLY (no dep builds) | sourced |
| `scripts/lib/build_dep.sh` | Library — defines `build_dep <name> ... -- [cmake args]` | sourced |
| `scripts/build_turbo_stack.sh` | Stage 2 — cmake configure + build + ctest. No spack or infra knowledge. | exec'd |

`build_turbo_stack.sh` options: `--debug`, `--clean`, `--ninja`, `--build_dir DIR`, `--infra FMS2|TIM`, `--tests`, `--parallel N`.

Unit tests are **opt-in**: pass `--tests` to any orchestrator (or `build_turbo_stack.sh`) to build pFUnit + the suite and run `ctest`; a plain build produces just the executable. The end-to-end `test_turbo_stack_*.sh` drivers always force them on.

### Where dep builds + installs land

The orchestrators derive deps location from `--build_dir`: `<build_dir>/deps/{build,install}/`. With no `--build_dir`, deps land at `$TURBO_STACK_ROOT/deps/default/`; the end-to-end test drivers build each backend under `$TURBO_BUILD_SYSTEM_TEST_DIR/turbo-stack-with-<backend>/` (deps in its `deps/` subdir). In the explicit flow you pass the build/install roots straight to the `turbo_build_*` wrappers.

### Parallel build jobs

`--parallel N` on the orchestrators exports `CMAKE_BUILD_PARALLEL_LEVEL=N` once; every downstream `cmake --build` (deps + turbo-stack) reads it natively. You can also set `CMAKE_BUILD_PARALLEL_LEVEL` in your shell profile to skip the CLI flag. When neither is set, cmake's own default applies (Make=1, Ninja=nproc).

### Source-tree overrides

`build_dep` resolves each dep's source via (first match wins): `$<NAME>_ROOT` env var, or the corresponding submodule. So overriding any single dep with a local dev tree is:

```bash
export MOM6_ROOT=$HOME/projects/MOM6
export FMS_ROOT=$HOME/projects/FMS
./test_turbo_stack_locally.sh    # matrix shows each component as (override) vs (submodule)
```

### Building a MOM6 branch instead of the pinned commit

Two ways, neither needing a flag. Move the submodule onto the branch and leave
`MOM6_ROOT` unset:

```bash
git -C submodules/MOM6 checkout dev/turbo-debug
./test_turbo_stack_locally.sh
git -C submodules/MOM6 checkout -
```

Or clone it elsewhere and point `MOM6_ROOT` there, which leaves the submodule
untouched. MOM6's own submodules must be initialized either way.

CI does the latter — `actions/checkout` puts the branch in a sibling directory
and sets `MOM6_ROOT`. There is no turbo-stack-specific machinery for this: the
build scripts only ever know about `MOM6_ROOT`.

### Spack environment

Defined in `spack/spack.yaml`. Default env name: `turbo_stack`. Provides cmake, gmake, ninja, MPI (OpenMPI), NetCDF, pFUnit, AMReX. FMS and TIM are intentionally not in spack: `build_local_with_spack_env.sh` builds the selected backend via `turbo_build_fms`/`turbo_build_tim` (in `scripts/lib/common.sh`) from the local source tree (`$FMS_ROOT`/`$TIM_ROOT` or the submodule fallback). Turbo-stack tracks features ahead of the released FMS package, so linking against spack's FMS would risk quietly using a stale version.

**AMReX mini-app tests** are built with CMake separately (see `src/amrex_mini_app/CMakeLists.txt`). They use GoogleTest (C++) and require HDF5.

## Architecture

### Component Relationships

```
Single-backend builders — thin wrappers.  Each defines turbo_flavor_setup_toolchain
and calls turbo_run_backend_builder (lib/common.sh), differing only in the toolchain
recipe and the lowest dependency TIER it must build from submodule (the first the
toolchain does NOT provide prebuilt — see docs/dependency_tiers.png):

  build_local_with_spack_env.sh          toolchain = spack env     (provides Tier 1 + 1.5) → build from Tier 2
  build_local_with_system_toolchain.sh   toolchain = your PATH     (provides Tier 1)       → build from Tier 1.5
  build_on_derecho.sh                    toolchain = Lmod modules  (provides Tier 1)       → build from Tier 1.5
      │
      └─→ turbo_run_backend_builder (lib/common.sh) — the shared Stage-1+Stage-2 body:
            ├─→ turbo_flavor_setup_toolchain          Stage 1: source the toolchain recipe (builds nothing)
            ├─→ turbo_build_{pfunit,amrex,fms,tim}    Stage 1: build the submodule dep tiers not provided
            └─→ build_turbo_stack.sh                  Stage 2: configure + build + ctest (exec'd)
                  ├─→ cmake configure (Unix Makefiles by default; --ninja for Ninja)
                  ├─→ cmake build
                  └─→ ctest

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

- **TIM** — TURBO Infrastructure for MOM; AMReX-backed layer. The **default** backend (orchestrators use it when `--infra` is unset).
- **FMS2** — traditional Flexible Modeling System; the reference backend, selected with `--infra FMS2`.

### Language Split

- **Fortran** — MOM6, FMS, MARBL, unit tests under `tests/`
- **C++20** — AMReX mini-app (`src/amrex_mini_app/`), GoogleTest-based tests there
- **Bash** — build orchestration under `scripts/` (see [`scripts/README.md`](scripts/README.md))

## CI/CD

GitHub Actions workflows (`.github/workflows/`) cover the two build systems in
separate lanes, in different containers:

| Lane | Build system | Container |
|---|---|---|
| `build-tests*.yaml`, `unit-tests.yaml`, `matrix-compiler-smoketest.yaml`, `code-coverage-reports.yaml` | legacy mkmf `./build.sh` | `ncarcisl/cisldev-x86_64-almalinux9-[compiler]-[mpi]`, activated via `/container/config_env.sh` |
| `turbo-cmake-container-tests.yaml` | **CMake** (`scripts/build_local_with_spack_env.sh`, spack flavor) | `ghcr.io/turbo-esm/turbo-stack/turbo-ci:gcc-openmpi`, built by `build-turbo-ci-container.yaml` from `docker/Dockerfile.turbo-ci` |

The legacy lane runs a matrix of compilers (oneapi, gcc14, nvhpc, clang) and MPI
libraries (MPICH, OpenMPI) across `ubuntu-latest` and the custom
`gha-runner-turbo` runner. The CMake lane is currently gcc + OpenMPI on
`ubuntu-latest` only, over 4 cells arranged as **two groups of two**:
`turbo-cmake-container-tests.yaml` calls the reusable `cmake-build.yaml` once per
MOM6 source, and each call fans out over the infra backends (TIM, FMS2).

| Group | MOM6 source | Character |
|---|---|---|
| `MOM6 pinned` | the submodule commit | deterministic gate |
| `MOM6 dev/turbo-debug` | tip of that branch, via `MOM6_ROOT` | tracks a moving external branch |

Two jobs rather than a second matrix axis because they mean different things: a
red box then names which MOM6 source broke, and either group can be given a
different trigger or failure policy without touching the other. The
`dev/turbo-debug` group exists because TURBO development happens on that branch,
so the pFUnit suite has to run against it too — possible at all only because
MOM6's CMake build system now lives on both branches, the same CMakeLists tree
having been ported to `dev/turbo-debug`.

The `turbo-ci` image bakes the repo's `spack/spack.yaml` environment
(`turbo_stack`) so CI does not rebuild dependencies each run. It is **private**,
and a `spack.yaml` change does not reach CI until the producer workflow is
re-run manually (`gh workflow run build-turbo-ci-container.yaml`) — see
[`docker/README.md`](../docker/README.md).

Branches that trigger CI: `main` for the CMake lane; `main` plus the legacy
`ci-tests` / `container-ci` branches for the mkmf lane. Any workflow can also be
run against an arbitrary branch with `gh workflow run <file> --ref <branch>`.

Clang-format (Google style, C++20, 120-char limit) is enforced on PRs and auto-applied on pushes to `main`.

## Code Style

C++ files must pass `clang-format` (config in `.clang-format`): Google style base, C++20, 120-char line limit, Allman braces.

## Verification discipline for mechanical multi-site edits

A Fortran identifier (a dummy argument, a derived-type field, a struct
being restructured) is often encoded in more than one place that doesn't
look alike textually — a subroutine's header argument list vs. its
separate declaration line, several near-identical mirrored subroutines
(zonal/meridional pairs), or several call sites with slightly different
surrounding comments. A targeted edit or find/replace reporting success
only means the specific text it matched changed, not that every
occurrence of the identifier did. After any rename or multi-site
mechanical edit, before considering it done: grep the full scope of the
change (the whole subroutine, or the whole file) for the old identifier,
zero tolerance for hits outside comments — don't rely on re-reading only
the lines you intended to touch. Same discipline applies to inserting a
new executable statement into an existing subroutine: re-scan the rest of
that subroutine's declaration section first, since Fortran requires every
declaration before every executable statement and a misplaced insertion
produces a cascade of unrelated-looking parse errors below it rather than
an error at the actual mistake. Applies to any Fortran editing in this
repo or its submodules, not only MOM6's array-container conversion skill
family (`submodules/MOM6/.claude/skills/array_container_lessons/SKILL.md`
§11 has the fuller writeup and worked examples).
