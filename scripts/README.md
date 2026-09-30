# `scripts/`

Build orchestration for turbo-stack, and the reference for its CMake build: how
the build is put together, what you have to supply for it, and what each script
does. The quick start is in the
[top-level README](../README.md#quick-start-build-the-mom6-executable).

## How the build is put together

turbo-stack holds unit tests for the infrastructure layer backends, TIM and FMS2. They are **linked** against MOM6: every test links `TURBO::infra_r8` (the backend itself) plus the MOM6 library under test — usually `MOM6::infra`, which is MOM6's own wrapper over the backend, sometimes `MOM6::framework`. So MOM6's libraries have to be built, but the MOM6 executable is not involved in running the pFUnit tests. An overview of how things are put together is shown in the figure below. Ovals represent executables, boxes are libraries we link against, the diamond represents a switch keyed on the option that selects a backend, and the colored boxes in the background show which repository the source code comes from. 

> Note MARBL is a little bit of an outlier here: we make it a library we can link against in CMake, but we do that from inside the turbo-stack repository. We will probably move the CMake build into MARBL later, so that it can be a normal "External" in the box at the bottom.

[![cmake dependency dag](../docs/cmake_dependency_dag.png)](../docs/cmake_dependency_dag.png)

Building and running the pFUnit tests in [`tests/`](../tests/) is this
repository's main job, alongside producing a standalone MOM6 executable. The
real work gets done in [`build_turbo_stack.sh`](build_turbo_stack.sh), but a
number of things (compilers, tools, libraries...) have to be set up before that
script can run. The dependency tiers below classify them, and the
[pipeline](#pipeline-environment-setup--build-turbo-stack) is how a machine sets
them up.

## Dependency contract (tiers)

turbo-stack classifies every dependency by **its build policy**, shown below
(`docs/dependency_tiers_prompt.md` says how to regenerate the figure). The
diagram is incomplete but shows the major pieces; you will also need bash, git,
and the common unix / linux command line tools our scripts call.

[![turbo-stack dependency tiers](../docs/dependency_tiers.png)](../docs/dependency_tiers.png)

| Tier | Policy | Members |
|------|--------|---------|
| **1 — External, not a submodule** | turbo-stack *never* gets or builds these; you supply them prebuilt (modules / spack / OS packages / hand-compiled) | compilers, MPI, NetCDF, CMake ≥ 3.24, make/ninja, HDF5 |
| **1.5 — External, a submodule** | turbo-stack *can* build these from their submodule (`build_dep` → `find_package`) OR you supply a prebuilt install on `CMAKE_PREFIX_PATH` | AMReX, pFUnit |
| **2 — Internal (we develop), a submodule** | turbo-stack *can* build these from their submodule (or a `*_ROOT` source override) OR you supply a prebuilt install | FMS, TIM |
| **3 — Always built inline** | turbo-stack *always* builds these (`add_subdirectory`); only the SOURCE can be swapped | turbo-stack, MOM6, MARBL |

Tiers 1.5 and 2 share the same build policy (build-from-submodule or supply-prebuilt);
they differ by *source*. Which option is taken is fixed per builder, not chosen
by you: every one-command builder builds its Tier 2 backend from source, and
Tier 1.5 is taken prebuilt from the Spack env by the Spack flavor and built from
source by the other two. A prebuilt install of your own is used only in the
[explicit flow](#explicit-iterative-any-flavor).

"Our code" is not a tier: the repos we co-develop —
**FMS, TIM** (Tier 2) and **MOM6** (Tier 3) — are the ones the drivers treat as
first-class hot-swaps, reporting each as `(override)` or `(submodule)` in the
testing matrix. Every `build_dep` dep in fact honors a `*_ROOT` source override
— AMReX/pFUnit (Tier 1.5) via `AMREX_ROOT` / `PFUNIT_ROOT` — it just goes
unreported in the matrix, and it applies only where a builder builds them, which
the Spack flavor never does. MARBL is pinned-submodule-only -- it currently rides along in Tier 3 as a MOM6
dependency; pushing it down into Tier 1.5 as an external library is a possible
future move.

## Pipeline (environment setup → build turbo-stack)

The dependency tiers above are a *classification*; the pipeline is what a machine
actually runs. It has **two stages**, shown below; `docs/build_test_orchestration.png`
shows the same two stages as the scripts drive them:

[![two stage pipeline](../docs/two_stage_pipeline.png)](../docs/two_stage_pipeline.png)

1. **Stage 1 — environment setup** *(machine-specific)* — make Tiers 1, 1.5 and 2
   available before turbo-stack is built:
   - source a `setup_environment/<flavor>.sh` recipe to put the toolchain
     (Tier 1: compiler / MPI / NetCDF / CMake) on `PATH`. **These recipes build
     nothing** — they only prepare the shell.
   - obtain the upstream submodule deps the toolchain didn't already provide —
     AMReX/pFUnit (Tier 1.5) and FMS/TIM (Tier 2) — via the `turbo_build_*`
     wrappers in `lib/common.sh` (the canonical per-dep cmake flags live there,
     once). *Which* deps need building is the machine-specific part: e.g. spack
     supplies pFUnit/AMReX prebuilt so locally you build only FMS/TIM, while
     Derecho's modules provide neither so you build all four.
2. **Stage 2 — build turbo-stack** *(same across machines)* — `build_turbo_stack.sh` runs cmake
   configure + build (and `ctest` when `--tests` is given; unit tests are opt-in),
   compiling Tier 3 (turbo-stack, MOM6, MARBL) against the prepared environment.

Only Stage 1 differs between machines; Stage 2 is always the same. The
single-backend builders (`build_*`) run both stages; the end-to-end test drivers
run a builder once per backend via the shared core in `lib/common.sh`.

## What you supply, tier by tier

Everything in tiers 1, 1.5 and 2 has to be in place before Stage 2
(`build_turbo_stack.sh`) runs, and Stage 2 builds tier 3. The sections below
cover what you have to supply for each tier, and how.

### Tier 1 — Prerequisites (no source supplied via submodules)

turbo-stack does not supply the source code of these as submodules and will not build them for you. You are expected to supply them in the environment. You can build them from source but these are typically available via a package manager, e.g. Lmod modules on HPC systems, Spack, Homebrew on macOS, apt-get on Debian, etc. None of these scripts take `cmake -D…` configure options on their command line, so each requirement below is picked up from the environment instead:

| Requirement | Sufficient to set | Notes |
|---|---|---|
| Fortran compiler | `FC`, else CMake tries to find it by searching `PATH` | GNU, Intel / IntelLLVM, NVHPC / PGI, or Flang / LLVMFlang. Any other compiler ID is a hard configure error — `cmake/TurboCompilerFlags.cmake` carries no flag set for it |
| C and C++ compilers | `CC` and `CXX`, else CMake tries to find them by searching `PATH` | the top-level project enables `C CXX`, so both C and C++ compilers are needed |
| MPI | `mpicc`, `mpifort` (or `mpif90`) and `mpicxx` (or `mpic++`) on `PATH` | the Fortran and C wrappers; the TIM/AMReX path uses the C++ one too. `MPI_HOME` is enough for CMake itself — so for a direct `build_turbo_stack.sh` run — but `build_local_with_system_toolchain.sh` checks for the wrappers on `PATH` and stops without them |
| NetCDF | `nc-config` / `nf-config` on `PATH`, or `NetCDF_ROOT`, or the install prefix on `CMAKE_PREFIX_PATH` | need the C and Fortran libraries |
| CMake | on `PATH` | ≥ 3.24 — turbo-stack, MOM6, TIM and pFUnit each require it |
| `make` or `ninja` | on `PATH` | Unix Makefiles by default, running the build scripts with `--ninja` picks Ninja instead |

Compiler flags are the same story: CMake seeds them from `FFLAGS` / `CFLAGS` /
`CXXFLAGS` natively and appends the project's own, so there is no script flag for
them. Like the compilers, they are read only on a build directory's first
configure — see [Environment](#environment).

> You do not have to assemble tier 1 by hand. A [Spack environment](#getting-tiers-1-and-15-from-spack)
> supplies it, and so does the `turbo-ci` container image used by CI, which ships tiers 1 and 1.5
> prebuilt — today you pull it and drive the build yourself, as
> [`docker/README.md`](../docker/README.md) shows. Scripts that wrap that in one command are on the way.

### Tier 1.5 — Prerequisites, but we supply the source via a submodule

AMReX and pFUnit are external libraries. The source code is provided via submodules, and which build script you run decides where they come from: the Spack flavor takes both prebuilt from its Spack environment, and the from-source builders always build them from the submodule (or from an `AMREX_ROOT` / `PFUNIT_ROOT` source tree). None of the one-command builders will pick up an install of your own. To use one, take the [explicit flow](#explicit-iterative-any-flavor): source a toolchain recipe, skip `turbo_build_amrex` / `turbo_build_pfunit`, prepend your install prefix to `CMAKE_PREFIX_PATH`, then run `build_turbo_stack.sh`. pFUnit needs one extra step: it installs into a versioned `PFUNIT-X.Y/` subdirectory that `find_package` will not find by default, so point `PFUNIT_DIR` at `<prefix>/PFUNIT-X.Y/cmake`.

#### Getting tiers 1 and 1.5 from Spack

[`spack/spack.yaml`](../spack/spack.yaml) supplies CMake, `make`/`ninja`, MPI,
NetCDF, ParallelIO, pFUnit and AMReX — everything in tier 1 except a base
compiler, plus both of tier 1.5. So all you need is a compiler and `SPACK_ROOT`
pointing at a [Spack](https://github.com/spack/spack) clone. If you already
source Spack's `share/spack/setup-env.sh` (from your shell profile, say), it
exports `SPACK_ROOT` for you and there is nothing to set. Otherwise export it by
hand — the build script sources `setup-env.sh` itself, so you do not have to:

```bash
export SPACK_ROOT=/path/to/where/you/pulled/spack
```

The `turbo_stack` environment is created on first use by
[`build_local_with_spack_env.sh`](build_local_with_spack_env.sh).

### Tier 2 — Infrastructure backend
FMS and TIM are the two backends MOM6's infrastructure layer sits on, and the two
we co-develop: TIM is TURBO's own AMReX-based layer, while FMS is GFDL's Flexible
Modeling System tracked in a [TURBO-ESM fork](https://github.com/TURBO-ESM/FMS).
turbo-stack supplies both as submodules, and every one-command builder builds
whichever one `--infra` selects — from the submodule, or from an `FMS_ROOT` /
`TIM_ROOT` source tree. A prebuilt install of your own is used only in the
explicit flow, the same way as for tier 1.5: skip `turbo_build_fms` /
`turbo_build_tim` and put its install prefix on `CMAKE_PREFIX_PATH`.

> [!WARNING]
> `FMS_ROOT`, `TIM_ROOT`, `AMREX_ROOT` and `PFUNIT_ROOT` are **not** install
> prefixes — each names a *source tree* for turbo-stack to build. See
> [Building against a development tree or a branch](#building-against-a-development-tree-or-a-branch).

### Tier 3 — What turbo-stack always builds

turbo-stack, MOM6 and MARBL are compiled inline on every build, pulled in with
`add_subdirectory` from the top-level [`CMakeLists.txt`](../CMakeLists.txt). This is
the tier Stage 2 exists to build. Unlike tiers 1.5 and 2 there is no
bring-your-own-install option — nothing goes looking for a prebuilt MOM6 or
MARBL, so here only the *source* can be swapped.

- **MOM6** is read from `MOM6_ROOT`, the one source override the build cannot do
  without: CMake hard-errors when it is unset, so the build scripts default it to
  `submodules/MOM6` for you. Point it elsewhere to build a fork or a branch.
- **MARBL** comes from `submodules/MARBL` only — it has no `*_ROOT` override.
- **turbo-stack** itself is whichever checkout you ran the scripts from, which is
  also where the pFUnit suite in [`tests/`](../tests/) lives. The suite is opt-in, so
  it is only configured when you pass `--tests`.

---

## Layout
Roughly in order from lowest level to highest level.
```
scripts/
  README.md                                   #  this file

  # Utilities sourced by other scripts:
  lib/
    common.sh                                 #   SHARED CORE — root resolution, arg parsing, turbo_build_*, builder core (turbo_run_backend_builder), matrix/verdict
    build_dep.sh                              #   build_dep() — build one cmake dep (+ rebuild sentinel)

  # STAGE 1 environment setup only - one file per flavor (sourced)
  setup_environment/
    spack_local_environment.sh                #   spack environment activation
    local_toolchain_on_path.sh                #   generic — toolchain already on PATH (no spack/modules)
    derecho_cpu_gcc_openmpi.sh                #   Derecho via Lmod modules

  # STAGE 2 — build turbo-stack: cmake configure + build (+ ctest with --tests)
  build_turbo_stack.sh

  # Orchestrators - Do stage 1 and 2 for a single backend (TIM or FMS2)
  build_local_with_spack_env.sh               # ORCHESTRATOR — stage 1 via spack
  build_local_with_system_toolchain.sh        # ORCHESTRATOR — stage 1 via bring your own toolchain
  build_on_derecho.sh                         # ORCHESTRATOR — stage 1 via Derecho's Lmod modules

# (repo top level) — high level end-to-end drivers, wraps orchestrators automate building and testing BOTH backends:
test_turbo_stack_locally.sh                   # local (spack)
test_turbo_stack_with_system_toolchain.sh     # local (bring-your-own toolchain)
test_turbo_stack_on_derecho.sh                # Derecho (qsub or interactive)
```

---

## Build and test both backends, one command

```bash
./test_turbo_stack_locally.sh                  # local (spack)
./test_turbo_stack_with_system_toolchain.sh    # local (bring-your-own toolchain on PATH)
./test_turbo_stack_on_derecho.sh               # Derecho (qsub or interactive)
```

Each runs the real single-backend builder once per backend, each in its own
process and its own build directory, and builds + `ctest`s turbo-stack for both
FMS2 and TIM. `--only FMS2|TIM`, `--parallel N`, `--clean`. All three honor the
`MOM6_ROOT` / `FMS_ROOT` / `TIM_ROOT` source overrides described below;
`AMREX_ROOT` / `PFUNIT_ROOT` only the two from-source ones, since
`test_turbo_stack_locally.sh` takes AMReX and pFUnit prebuilt from Spack.

Two different things get printed, and they are easy to conflate:

- a **testing matrix** at the start (`turbo_print_matrix`) — the commit and branch
  of turbo-stack, MOM6, TIM and FMS, each marked `(override)` or `(submodule)`.
  AMReX and pFUnit are *not* in it, even where `AMREX_ROOT` and `PFUNIT_ROOT`
  apply; `build_dep` announces those as it resolves them instead.
- a **build summary** at the end (`turbo_verdict`) — `PASS` / `FAIL` / `SKIPPED`
  per backend.

Only these drivers print either one; the single-backend builders print neither.

Artifacts land under `$TURBO_BUILD_SYSTEM_TEST_DIR` (default
`${TMPDIR:-/tmp}/turbo_build_system_test`), one directory per backend, so the two
executables end up at:

```
$TURBO_BUILD_SYSTEM_TEST_DIR/turbo-stack-with-{TIM,FMS2}/mom6_build/config_src/drivers/solo_driver/MOM6
```

`--clean` removes that whole directory first. With the default location, no
build artifact is written into `$TURBO_STACK_ROOT` — only a Derecho batch job's
PBS log, when you submit from there (see below).

### Submitting the Derecho driver as a batch job

`test_turbo_stack_on_derecho.sh` carries its own PBS directives — project code,
`-q main`, one node with 128 cores, one hour — so `qsub
test_turbo_stack_on_derecho.sh` is the whole command. A `qsub` option on the
command line overrides the matching directive, which is how to supply your own
project code:

```bash
qsub -A <project_code> -l walltime=00:30:00 test_turbo_stack_on_derecho.sh
```

It deliberately omits `#PBS -V`, so the job inherits nothing from the submitting
shell and therefore tests exactly what the repo pins. That also means an exported
`TURBO_BUILD_SYSTEM_TEST_DIR` will **not** reach it — pass it with `-v`. Worth
doing for anything you want to keep, since unlike the job scripts in `examples/`
this driver does not repoint `TMPDIR` at scratch:

```bash
qsub -v TURBO_BUILD_SYSTEM_TEST_DIR=/glade/derecho/scratch/$USER/turbo-test \
     test_turbo_stack_on_derecho.sh
```

PBS writes the job log to `turbo-stack-on-derecho-test.o<jobid>` in the directory
you submitted from; each backend also gets its own log under
`$TURBO_BUILD_SYSTEM_TEST_DIR/logs/`.

## Workflows
Scripts that run through Stage 1 and Stage 2 for a single backend.

### One-command (spack flavor)

```bash
scripts/build_local_with_spack_env.sh                    # configure + build (default backend: TIM)
scripts/build_local_with_spack_env.sh --tests            # also build + run the pFUnit unit tests
scripts/build_local_with_spack_env.sh --debug            # incremental Debug build
scripts/build_local_with_spack_env.sh --clean            # clean rebuild from scratch (deps + turbo-stack)
scripts/build_local_with_spack_env.sh --infra FMS2       # FMS2 backend instead of the default TIM
```

`build_local_with_spack_env.sh` runs all stages. It builds the selected backend via `turbo_build_fms`/`turbo_build_tim` after sourcing `setup_environment/spack_local_environment.sh` — spack provides pFUnit/AMReX but neither FMS nor TIM.

### One-command (from-source local — bring your own toolchain)

```bash
scripts/build_local_with_system_toolchain.sh                 # configure + build (default backend: TIM)
scripts/build_local_with_system_toolchain.sh --tests         # also build + run the pFUnit unit tests
scripts/build_local_with_system_toolchain.sh --infra FMS2    # FMS2 backend instead of the default TIM
scripts/build_local_with_system_toolchain.sh --clean         # clean rebuild from scratch (deps + turbo-stack)
```

The closest replacement for the old `build.sh` on a laptop / workstation: you
bring your own toolchain (compilers, MPI, NetCDF, CMake already on `PATH` —
system packages, Homebrew, an OS module system, or an already-activated
Spack/Conda env), and turbo-stack builds **all** of its upstream submodule deps
from source — pFUnit + AMReX (Tier 1.5) and FMS/TIM (Tier 2) — then builds
turbo-stack itself (Tier 3). Nothing is fetched; everything comes from
`submodules/`. It sources `setup_environment/local_toolchain_on_path.sh` (which
only *verifies* the toolchain is present — it builds nothing), then the
`turbo_build_*` wrappers. Same shape as `build_on_derecho.sh`, minus the Lmod
step. Prefer Spack to manage the whole toolchain? Use
`build_local_with_spack_env.sh` instead.

### Build on Derecho yourself:
All prerequisites to build turbo-stack are already available on Derecho as Lmod modules, and `build_on_derecho.sh` loads them for you, so getting from a fresh clone to a built MOM6 executable is:

```bash
qcmd -A <project_code> -- ./scripts/build_on_derecho.sh --tests
```

`qcmd` puts the compile on a compute node — drop it if you are already inside an interactive job. `--tests` is optional, it builds and runs the pFUnit test suite. The default location the MOM6 executable ends up at:

```
build/default/mom6_build/config_src/drivers/solo_driver/MOM6
```

The `build_on_derecho.sh` script contains a number of useful options; see them all with `-h` or `--help`. Some commonly used ones are `--infra FMS2` for the FMS2 backend (defaults to TIM), and `--clean` to rebuild everything from scratch.

Its Stage-1 recipe (`setup_environment/derecho_cpu_gcc_openmpi.sh`) runs
`module purge` before loading `gcc cmake openmpi netcdf parallelio`, so any
modules you loaded yourself beforehand are discarded.


### Explicit, iterative (any flavor)

Environment setup is a two-part phase: source the toolchain once per shell, then
explicitly build the upstream deps you need; after that run
`build_turbo_stack.sh` as often as you like:

```bash
source scripts/lib/common.sh                                   # turbo_build_* wrappers + helpers
source scripts/setup_environment/spack_local_environment.sh    # env setup: toolchain (spack); builds NOTHING
deps="$TURBO_STACK_ROOT/deps/default"
turbo_build_fms "$deps/build" "$deps/install"                  # env setup: build FMS (Tier 2); spack supplies pFUnit/AMReX (Tier 1.5)
scripts/build_turbo_stack.sh --infra FMS2                      # build turbo-stack (Tier 3; add --tests to build + run ctest)
# TIM backend instead:
turbo_build_tim "$deps/build" "$deps/install"
scripts/build_turbo_stack.sh --infra TIM
```

On a modules machine, swap the toolchain step for
`source scripts/setup_environment/derecho_cpu_gcc_openmpi.sh`; on a generic local
machine whose toolchain is already on `PATH`, swap it for
`source scripts/setup_environment/local_toolchain_on_path.sh`. In both cases the
toolchain provides no upstream deps, so also build the Tier-1.5 deps yourself
(`turbo_build_pfunit`, `turbo_build_amrex`) alongside FMS/TIM.

---

## The `build_dep` function

`scripts/lib/build_dep.sh` defines a function — sourced once, called per dep:

```bash
build_dep <name>
    --build-dir DIR
    --install-prefix DIR
    [--rebuild]
    [--parallel N | -j N]
    -- [cmake args...]
```

Cmake args go after `--` (mirrors `cmake --build dir -- ...` and `build_turbo_stack.sh`'s own pass-through).

**Source resolution** (first match wins):

1. `$<NAME>_ROOT` env var — set externally (export it to point at a local clone, e.g. a fork or PR branch you cloned yourself).
2. **Submodule fallback** — per-name table inside `build_dep.sh`:

   | `<name>` | submodule path |
   |---|---|
   | `fms`    | `$TURBO_STACK_ROOT/submodules/infra/FMS2` |
   | `pfunit` | `$TURBO_STACK_ROOT/submodules/pFUnit` |
   | `amrex`  | `$TURBO_STACK_ROOT/submodules/amrex` |
   | `tim`    | `$TURBO_STACK_ROOT/submodules/infra/TIM` |

**Sentinel**: `<build-dir>/.installed` is a small KV file recording the source SHA, source path, install prefix, and a sha256 of the (sorted) cmake args. Skip-on-rerun fires only when all four match. Flipping a cmake flag (e.g. `-DAMReX_GPU_BACKEND=CUDA`) triggers a rebuild.

**Side effects on success**: prepends `$install_prefix` to `CMAKE_PREFIX_PATH` with a dedup guard, so the install it just made is found ahead of any other already on the path. For `name=pfunit`, also exports `PFUNIT_DIR` pointing at the versioned cmake-dir glob.

---

## Building against a development tree or a branch

To build a co-developed component from somewhere other than its pinned
submodule, export its `*_ROOT` before building. No flag, no cloning by the build
scripts — and it works the same for the high-level testers and the
single-backend build scripts:

```bash
export MOM6_ROOT=/path/to/your/MOM6
export TIM_ROOT=/path/to/your/TIM
export FMS_ROOT=/path/to/your/FMS

# the high-level tester: builds and ctests both backends
./test_turbo_stack_locally.sh

# or a single-backend build script, picking up the same overrides
scripts/build_local_with_spack_env.sh --infra TIM
```

`MOM6_ROOT`, `FMS_ROOT` and `TIM_ROOT` are the co-developed ones, and they work
with every build script and tester, and with the explicit flow's `turbo_build_*`
wrappers. A bare `build_turbo_stack.sh` reads only `MOM6_ROOT`: it builds no
backend, so it finds FMS or TIM installed on `CMAKE_PREFIX_PATH`. `AMREX_ROOT`
and `PFUNIT_ROOT` work the same way, but only where the builder actually builds
tier 1.5 from submodule — the from-source builders
(`build_local_with_system_toolchain.sh`, `build_on_derecho.sh`, and their
testers). The Spack flavor shown above takes AMReX and pFUnit prebuilt from the
Spack environment and never consults those two variables; to build against your
own there, use the explicit flow described under
[tier 1.5](#tier-15--prerequisites-but-we-supply-the-source-via-a-submodule).

What gets *reported* differs between the two entry points:

- the **testers** print the testing matrix, naming turbo-stack, MOM6, TIM and
  FMS and marking each `(override)` or `(submodule)`, so the log says exactly
  what was built. AMReX and pFUnit are not in that matrix.
- the **build scripts** do not print the matrix, but [`build_dep`](#the-build_dep-function) announces each
  dependency as it resolves it, e.g.
  `[build_dep] fms: source = /path/to/your/FMS (from $FMS_ROOT)`. MOM6 is
  resolved by CMake rather than `build_dep`, and is only mentioned when you have
  *not* overridden it (`[common] MOM6_ROOT unset -> defaulting to submodule:`).

### Building a MOM6 branch you don't have checked out

`MOM6_ROOT` needs a tree you already have. To build MOM6's `dev/turbo-debug`
development branch instead of the pinned commit, there are two ways and neither
needs a flag:

**Move the submodule onto the branch.** Simplest, and `MOM6_ROOT` stays unset:

```bash
git -C submodules/MOM6 checkout dev/turbo-debug
./test_turbo_stack_locally.sh
git -C submodules/MOM6 checkout -          # put it back when done
```

**Or point `MOM6_ROOT` at a separate clone.** Leaves the submodule alone, so an
interrupted run cannot strand it on another ref:

```bash
git clone --depth 1 --recurse-submodules --shallow-submodules \
    -b dev/turbo-debug https://github.com/TURBO-ESM/MOM6 /tmp/mom6-debug
MOM6_ROOT=/tmp/mom6-debug ./test_turbo_stack_locally.sh
```

MOM6's own submodules (`pkg/CVMix-src`, `pkg/GSW-Fortran`) must be initialized
either way -- its top-level `CMakeLists.txt` hard-fails without them.
`--shallow-submodules` is what carries `--depth 1` down into them; with
`--recurse-submodules` alone they are cloned at full depth.

CI does the second of these, but through `actions/checkout` (`submodules:
recursive`, `fetch-depth: 1`) rather than the commands above -- no workflow
shells out to `git clone`, so there is no copy of this recipe to keep in sync.
The `MOM6 dev/turbo-debug` group checks the branch out into a sibling directory
and points `MOM6_ROOT` there, so the build scripts see nothing unusual. The
testing matrix then reports MOM6 as an override at the real SHA, so a log says
exactly which commit was tested.

---

## Where do dep builds + installs land?

The orchestrators derive the deps location from `--build_dir`:

- `build_local_with_spack_env.sh --build_dir /scratch/foo` → deps land at `/scratch/foo/deps/{build,install}/`.
- `build_local_with_system_toolchain.sh --build_dir /scratch/foo` → same.
- `build_on_derecho.sh --build_dir /scratch/foo` → same.
- No orchestrator given a `--build_dir`: deps land at `$TURBO_STACK_ROOT/deps/default/`.

- The end-to-end test drivers build each backend independently under
  `$TURBO_BUILD_SYSTEM_TEST_DIR/turbo-stack-with-<backend>/` (deps in its `deps/` subdir).

turbo-stack's own build tree is the `--build_dir` itself (default
`$TURBO_STACK_ROOT/build/default`), and the MOM6 executable lands inside it at
`mom6_build/config_src/drivers/solo_driver/MOM6` — MOM6 is added with
`add_subdirectory(... mom6_build)` and sets no `RUNTIME_OUTPUT_DIRECTORY`, so the
path mirrors MOM6's own source layout. With `--tests`, `ctest` can be re-run
against an existing tree with `ctest --test-dir <build_dir>`.

An out-of-tree MOM6 source (`MOM6_ROOT`) is a build *input*, not a build
artifact, so it does not land here at all — see above.

In the explicit flow you pass the `build` and `install` roots straight to the
`turbo_build_*` wrappers, so any layout is possible.

---

## The MOM6 ↔ TIM AMReX bridge

`turbo_build_tim` passes `-DTIM_ENABLE_MOM_BRIDGE=ON`, which builds
`TIM::mom_bridge` — the C++ side of the AMReX kernels MOM6 calls from the
`#ifdef _TIM` branches in `src/core/MOM_continuity_PPM.F90`.

Whether those branches are *compiled and linked* is decided entirely in MOM6, by
two gates that between them need no flag from turbo-stack and no CI plumbing:

| Gate | Mechanism | Effect |
|---|---|---|
| **Branch** | the CMake block exists only on `dev/turbo-debug` | the pinned `dev/turbo` cells have no such block; nothing to switch off |
| **Backend** | `if(MOM6_INFRA STREQUAL "TIM")` in `src/CMakeLists.txt` | FMS2 stays compiled out — it cannot provide `turbotmp_*_bridge` |

So the four CI cells resolve themselves:

| MOM6 source | backend | `_TIM` | links `TIM::mom_bridge` |
|---|---|---|---|
| pinned (`dev/turbo`) | FMS2 | no | no |
| pinned (`dev/turbo`) | TIM | no | no |
| `dev/turbo-debug` | FMS2 | no | no |
| `dev/turbo-debug` | TIM | **yes** | **yes** |

**Why the flag here is unconditional.** Because Stage 1 cannot know whether the
bridge is needed. Only the MOM6 source knows whether it carries the `#ifdef _TIM`
call sites, and Stage 1 never sees that source — `MOM6_ROOT` is Stage 2's input.
The three ways to find out are all worse than not asking:

| | |
|---|---|
| ask the caller | puts a per-lane conditional back into the CI workflow |
| grep the MOM6 source for `_TIM` | couples a dep builder to MOM6's internals |
| read the branch name | does not work — CI builds a detached ref, and detached HEAD is a submodule's normal state |

It also keeps `turbo_build_tim` the same shape as its siblings: every
`turbo_build_*` wrapper takes a build dir and an install prefix and nothing else.
A condition here would make TIM's builder the only one that knows MOM6 exists,
inverting the tier contract above.

The cost is one 3-TU C++ compile — ~3 s, a 55 KB archive — in the cells that do not
use it, and **nothing on their link lines**: `mom_bridge` is a separate archive that
only MOM6 pulls in. Worth revisiting if the bridge grows substantially, since that
cost scales with the number of kernels; the link-side cost does not.

(A shared `--build_dir` is the one case where varying the flag would also cost
rebuilds, since `build_dep` folds cmake args into its sentinel hash. That is a
local-iteration concern only — each CI job is a fresh container.)

**This buys compile + link coverage, not kernel correctness.** The guards wrap one
arm of a runtime dispatch (`ZONAL_EDGE_THICKNESS_MODE` and five siblings, each
defaulting to `TIMH_runFORTRAN`), so defining `_TIM` compiles that arm in without
executing it.

Exactly what it catches, on every build:

- the C++ bridge sources **compile**. Before this they reached nothing a library
  build produced — `mom/cpp` was wired only into `test_mom` — so they could rot
  unnoticed.
- a missing or renamed export becomes a **link error**.

What it does **not** catch: signature or struct-layout drift. MOM6 declares the
bridge as `bind(C)` interface blocks, so the Fortran compiler checks each call site
against MOM6's *own* declaration, and the linker then matches `turbotmp_*_bridge`
by symbol name alone — `extern "C"` encodes no signature. `RealArray_C` and `Box_C`
are hand-maintained on both sides with no `static_assert` or generated header
between them, so a divergence in arity, type or layout links cleanly and misbehaves
at runtime. Closing that needs a real cross-check (offset assertions, or generating
the Fortran interfaces from the C header) and is follow-on work.

**Ordering.** MOM6 hard-errors at configure when `MOM6_INFRA=TIM` and
`TIM::mom_bridge` is absent, naming the TIM rebuild flag. Since the
`dev/turbo-debug` CI cells track that branch's tip, TIM and this flag must be in
place *before* MOM6's side merges, or the cell goes red in between.

---

## Parallel build jobs

`--parallel N` / `-j N` on the orchestrators exports `CMAKE_BUILD_PARALLEL_LEVEL=N`. Every downstream `cmake --build` invocation (deps + turbo-stack) picks it up natively without any flag plumbing. You can also set `CMAKE_BUILD_PARALLEL_LEVEL` in your shell profile / qsub directive / CI config to skip the CLI flag entirely:

```bash
export CMAKE_BUILD_PARALLEL_LEVEL=32
scripts/build_local_with_spack_env.sh                 # no --parallel needed
```

When neither is set, cmake's own defaults apply: 1 for Make, nproc for Ninja.

`build_dep.sh` and `build_turbo_stack.sh` also accept their own `--parallel N` flag as a per-call override.

---

## Environment

None of the entry-point scripts take `cmake -D…` configure options on their
command line, so whatever their own flags (`--infra`, `--debug`, `--tests`, …) do
not select comes from the environment. The
two `--` pass-throughs above are not exceptions to that: `build_dep`'s carries
each dependency's canonical flags down from the `turbo_build_*` wrappers, and
`build_turbo_stack.sh`'s goes to `cmake --build`, not to configure.

### Toolchain selection — read by CMake itself

| Variable | Effect |
|---|---|
| `FC`, `CC`, `CXX` | the Fortran / C / C++ compiler. Unset, CMake searches `PATH`. |
| `FFLAGS`, `CFLAGS`, `CXXFLAGS` | seed `CMAKE_<LANG>_FLAGS`; the project appends its own flags on top. |
| `MPI_HOME` | hint for `find_package(MPI)` when the compiler wrappers are not on `PATH` — enough for a direct `build_turbo_stack.sh` run, but not for `build_local_with_system_toolchain.sh`, whose toolchain check requires the wrappers on `PATH`. |
| `NetCDF_ROOT` | hint for `FindNetCDF` when `nc-config` / `nf-config` are not on `PATH`. |
| `CMAKE_PREFIX_PATH` | where prebuilt dependencies are found. `build_dep` prepends each install prefix it creates. |
| `PFUNIT_DIR` | pFUnit's cmake dir. `build_dep` exports it because pFUnit installs into a versioned `PFUNIT-X.Y/` subdirectory that `find_package` will not walk into. |

> [!IMPORTANT]
> `FC`, `CC`, `CXX` and the `*FLAGS` are read **only on the first configure** of a
> build directory — CMake caches them. To change a compiler or a flag in a build
> directory you have already configured, rebuild with `--clean`, which passes
> `cmake --fresh`.

The Fortran compiler must be one CMake identifies as GNU, Intel/IntelLLVM,
NVHPC/PGI or Flang/LLVMFlang: `cmake/TurboCompilerFlags.cmake` carries a flag set
per family and `FATAL_ERROR`s on anything else.

### turbo-stack's own

- `TURBO_STACK_ROOT` — normally **not set**; every entry point self-locates its
  own checkout (via `lib/common.sh`), so you build the checkout you run from.
  turbo-stack is a top-level orchestrator, so there is no "root override" — to
  build a different copy, run *its* scripts. If an exported `TURBO_STACK_ROOT`
  disagrees with the script's own location the script hard-errors (unset it)
  rather than silently using the other copy (the multi-checkout footgun).
- `SPACK_ROOT` — required for the spack flavor. But sourcing the shell startup script that spack provides for you should set this already.

Optional, for testing against local dev trees (see
[Building against a development tree or a branch](#building-against-a-development-tree-or-a-branch)):

- `MOM6_ROOT`, `FMS_ROOT`, `TIM_ROOT` — hot-swap a co-developed repo's source
  (default: the pinned submodule).
- `AMREX_ROOT`, `PFUNIT_ROOT` — the same, for the from-source builders only.
- `CMAKE_BUILD_PARALLEL_LEVEL` — default parallelism for every `cmake --build` in the pipeline (see "Parallel build jobs").
