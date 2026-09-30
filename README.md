[![turbo-stack CMake build](https://github.com/TURBO-ESM/turbo-stack/actions/workflows/turbo-cmake-container-tests.yaml/badge.svg)](https://github.com/TURBO-ESM/turbo-stack/actions/workflows/turbo-cmake-container-tests.yaml)
[![legacy mkmf build](https://github.com/TURBO-ESM/turbo-stack/actions/workflows/build-tests.yaml/badge.svg)](https://github.com/TURBO-ESM/turbo-stack/actions/workflows/build-tests.yaml)

# TURBO Stack

Welcome to the *TURBO Stack* repository, the central software hub for the TURBO project.
This repository brings together various components that make up the TURBO Stack, including:

 - [MOM6](https://github.com/TURBO-ESM/MOM6)
 - [TIM](https://github.com/TURBO-ESM/TIM) 
 - [FMS](https://github.com/TURBO-ESM/FMS)
 - [MARBL](https://github.com/marbl-ecosys/MARBL)
 - development and testing utilities
 - and future libraries and components that will be developed as part of the TURBO project.

> **There are two build systems.** This README documents the **CMake** build system, which is where new work should go. The original mkmf `build.sh` build still works and is still exercised in CI; it is documented in [`docs/legacy_build_system.md`](docs/legacy_build_system.md).

## Getting the code

Clone the repository along with all submodules:

```bash
git clone --recursive https://github.com/TURBO-ESM/turbo-stack.git
```

If you already cloned this repo but forgot the `--recursive` you can get the submodules at any time with:
```bash
git submodule update --init --recursive
```

## Quick start: build the MOM6 executable

One script takes you from a fresh clone to a MOM6 executable: it sets up the environment, builds the dependencies your environment did not supply, then configures and builds turbo-stack and MOM6 with CMake. Pick the one for your machine:

| Your machine | Command |
|---|---|
| Derecho (NCAR), Lmod modules | `scripts/build_on_derecho.sh` |
| Laptop / workstation, let Spack manage the toolchain | `scripts/build_local_with_spack_env.sh` |
| Laptop / workstation, toolchain already on `PATH` | `scripts/build_local_with_system_toolchain.sh` |

Each builds MOM6 against one [infrastructure backend](#choosing-an-infrastructure-backend), TIM unless you ask for FMS2. To build and test both backends in one go, see [Build and test both backends in one command](#build-and-test-both-backends-in-one-command). [`scripts/README.md`](scripts/README.md) explains how the build is put together, and its [Workflows](scripts/README.md#workflows) section is the full reference for these scripts.

### On Derecho

All the prerequisites are available on Derecho as Lmod modules, and `build_on_derecho.sh` loads them for you, so building the standalone MOM6 executable is:

```bash
cd turbo-stack/
qcmd -A <project_code> -- ./scripts/build_on_derecho.sh
```

`qcmd` puts the compile on a compute node — drop it if you are already inside an interactive job. The script runs `module purge` before loading its own modules, so any modules you loaded yourself are not used.

Once the build is complete, the executable is at `build/default/mom6_build/config_src/drivers/solo_driver/MOM6`.

### On other machines

On a laptop or workstation, pick a script by where the toolchain — compilers, MPI, NetCDF and CMake — comes from:

```bash
scripts/build_local_with_spack_env.sh          # Spack supplies MPI, NetCDF and CMake
scripts/build_local_with_system_toolchain.sh   # you already have all of it on PATH
```

The Spack script needs only a compiler and a Spack clone; see [Getting tiers 1 and 1.5 from Spack](scripts/README.md#getting-tiers-1-and-15-from-spack). The system-toolchain script checks that `mpicc`, `mpifort` (or `mpif90`), `mpicxx` (or `mpic++`) and `cmake` are on `PATH`, and stops before building anything if one is missing; [Tier 1](scripts/README.md#tier-1--prerequisites-no-source-supplied-via-submodules) in the `scripts/` README lists what each prerequisite needs. Either way the executable lands in the same place as on Derecho.

To give another machine a one-command script of its own, the way Derecho has one, write a `scripts/setup_environment/<machine>.sh` recipe that loads its toolchain, and a builder that sources it. [`build_on_derecho.sh`](scripts/build_on_derecho.sh) is the model: a toolchain hook plus one call into the shared build code. See [Pipeline](scripts/README.md#pipeline-environment-setup--build-turbo-stack) in the `scripts/` README.

### Build options

All three scripts take the same options — `build_local_with_spack_env.sh` adds `--recreate-spack-env` — and `-h` or `--help` on any of them prints them. For `build_on_derecho.sh`:

```text
$ scripts/build_on_derecho.sh --help
Usage: ./scripts/build_on_derecho.sh [options]

`TURBO_STACK_ROOT` is self-located from this script (build the checkout you run
from). See scripts/README.md for the dependency tier model.  Derecho's Lmod
modules provide only Tier 1, so this builder builds Tier 1.5 (pFUnit/AMReX) and
Tier 2 (FMS/TIM) from the submodules, then builds turbo-stack (Tier 3).

Optional environment variables (hot-swap a dep's source; default = submodule):
  MOM6_ROOT / FMS_ROOT / TIM_ROOT   out-of-tree source overrides

Options:
  --debug                 Build with CMAKE_BUILD_TYPE=Debug (passed through)
  --clean                 Clean rebuild from scratch.  Removes the Stage-1
                          upstream dep builds/installs AND passes cmake --fresh
                          --clean-first to the Stage-2 turbo-stack build.
  --ninja                 Use Ninja generator (passed through)
  --infra FMS2|TIM        Infrastructure backend (default: TIM, passed
                          through to build_turbo_stack.sh).
  --tests                 Also build pFUnit + the unit-test suite and run
                          ctest (default: off -- a plain build produces just
                          the executable, and pFUnit is not built).
  --build_dir DIR         Build directory for turbo-stack itself (passed
                          through to build_turbo_stack.sh).  Also controls
                          where from-source dep cmake builds + installs
                          land: $DIR/deps/build/<name>/ and
                          $DIR/deps/install/.  When --build_dir is omitted,
                          deps land at $TURBO_STACK_ROOT/deps/default/.
  --parallel N, -j N      Parallel build jobs.  Exported as
                          CMAKE_BUILD_PARALLEL_LEVEL so every downstream
                          `cmake --build` invocation (deps + turbo-stack)
                          picks it up natively, without any flag plumbing.
                          When omitted, cmake's own defaults apply (1 for
                          Make, nproc for Ninja).
  -h, --help              Print this usage text and exit.

Examples:
  build_on_derecho.sh                        # TIM backend, build the executable
  build_on_derecho.sh --tests                # also build + run the unit tests
  build_on_derecho.sh --infra FMS2           # FMS2 backend instead of TIM
  build_on_derecho.sh --debug --clean        # clean Debug rebuild (deps + turbo-stack)
```

The script's own `--help` is authoritative if this copy ever falls behind it.

### Choosing an infrastructure backend

MOM6 is built against exactly one infrastructure layer, chosen with `--infra`:

- **`TIM`** — Turbo Infrastructure for MOM, backed by AMReX. **The default.**
- **`FMS2`** — the traditional Flexible Modeling System layer; the reference backend.

The two are mutually exclusive, and the choice decides which dependency gets
built: `--infra TIM` builds TIM, `--infra FMS2` builds FMS. Switching backends
in an existing build directory is safe — the flag is always passed to CMake
explicitly, so a previous choice never sticks in the cache.

### Where the build lands

With no `--build_dir`, the build lands inside the checkout you ran the scripts from:

| Path | Contents |
|---|---|
| `build/default/` | turbo-stack's CMake build tree |
| `build/default/mom6_build/config_src/drivers/solo_driver/MOM6` | the standalone MOM6 executable |
| `deps/default/build/`, `deps/default/install/` | the dependencies built from `submodules/` |

Passing `--build_dir DIR` moves both: the build tree to `DIR` and the
dependencies to `DIR/deps/{build,install}/`. Both locations are outside `bin/`,
so a CMake build and a legacy mkmf build can coexist.

### Running the unit tests

The [pFUnit](https://github.com/Goddard-Fortran-Ecosystem/pFUnit) suite in [`tests/`](tests/) is **opt-in**. Add `--tests` to any of the build commands above to build the suite as well and run it under `ctest` once the build finishes:

```bash
qcmd -A <project_code> -- ./scripts/build_on_derecho.sh --tests
```

The run ends with `ctest`'s report — here from a CI run with the TIM backend, trimmed:

```text
Test project /path/to/turbo-stack/build/default
      Start  1: test_broadcast_int1D
 1/40 Test  #1: test_broadcast_int1D ...................   Passed    0.10 sec
      Start  2: test_broadcast_int320D
 2/40 Test  #2: test_broadcast_int320D .................   Passed    0.09 sec
...
      Start 40: test_create_mom_domain
40/40 Test #40: test_create_mom_domain .................   Passed    0.10 sec

100% tests passed, 0 tests failed out of 40

Total Test time (real) =   3.80 sec
```

The tests are MPI-aware — each declares the PE counts it runs on, e.g. `@test(npes=[4])`. They cover MOM6's infrastructure interface layer against whichever backend you built, not MOM6's ocean code itself. To re-run them without rebuilding:

```bash
ctest --test-dir build/default
```

See [`tests/README.md`](tests/README.md) for how to add one.

### Running example experiments

[`examples/`](examples/) holds ready-to-run standalone MOM6 configurations
(`double_gyre`, `benchmark`, CESM grids, …). Run the executable from inside the
example directory so it picks up that experiment's `MOM_input`, `input.nml` and
`diag_table`:

```bash
cd examples/double_gyre/
../../build/default/mom6_build/config_src/drivers/solo_driver/MOM6
```

For computationally more expensive examples, such as `benchmark`, run MOM6 in
parallel:

```bash
mpirun ../../build/default/mom6_build/config_src/drivers/solo_driver/MOM6
```

Example job submission scripts are provided in all of the example directories.
Make sure to adjust the project code and the path to the executable you built.

Once the run is complete, the model output files will be in the example
directory. To *archive* them:

```bash
make archive
```

This will create a copy of the output files in the `archive/` directory, with a
timestamp indicating when the archive was created. To clean up an example
directory, i.e., to remove all untracked output files (except the archive):

```bash
make clean
```

## Build and test both backends in one command

There are high level drivers at the repo root that build **and** `ctest` both backends (TIM and FMS2), each in its own build directory, and print a per-backend matrix and PASS/FAIL verdict. Artifacts go under `$TURBO_BUILD_SYSTEM_TEST_DIR` (default `${TMPDIR:-/tmp}/turbo_build_system_test`), so with the default they write nothing into your checkout — a Derecho batch job's PBS log aside:

```bash
./test_turbo_stack_locally.sh                   # Spack toolchain
./test_turbo_stack_with_system_toolchain.sh     # your own toolchain on PATH
./test_turbo_stack_on_derecho.sh                # Derecho (qsub or interactive)
```

`--only FMS2|TIM` narrows to one backend; `--clean` wipes that artifact directory first, for a genuine from-scratch run; `--parallel N` sets the job count. The matrix reports the commit and branch of turbo-stack, MOM6, TIM and FMS, and whether each came from its pinned submodule or from an override, so a log says exactly what was tested. A build summary at the end of the run gives the PASS / FAIL verdict for each backend.

See [Build and test both backends, one command](scripts/README.md#build-and-test-both-backends-one-command)
in the `scripts/` README for the full reference on each of these.

To build or test against your own MOM6, TIM or FMS tree instead of the pinned
submodule, see [Building against a development tree or a branch](scripts/README.md#building-against-a-development-tree-or-a-branch)
in the `scripts/` README.

### As a batch job on Derecho

```bash
qsub test_turbo_stack_on_derecho.sh
```

That driver is a true one liner: it carries its own PBS directives (turbo project code, one node, 128 cores, one hour run time, etc.), then for each backend in turn — TIM and FMS2 — runs [`build_on_derecho.sh`](#on-derecho) with the unit tests switched on: it loads some dependencies using Derecho's modules, builds the remaining dependencies from the pinned submodules, builds MOM6, and runs the pFUnit suite. Each backend gets its own build directory, and the run ends with a PASS / FAIL verdict for each.

It is deliberately self-contained: nothing from your login shell reaches the job, scripts run `module purge` before loading their own set of modules (so any modules you loaded yourself prior to launch will not be used), and no `#PBS -V` so environment variables don't make it into the job. The builds land outside your checkout; the one file PBS writes where you submitted from is the job log, `turbo-stack-on-derecho-test.o<jobid>`. A per-backend log sits alongside the builds.

To change the project code or walltime, or where the builds are written, see
[Submitting the Derecho driver as a batch job](scripts/README.md#submitting-the-derecho-driver-as-a-batch-job)
in the `scripts/` README.

## Continuous integration

CI covers both build systems in separate lanes and separate containers:

| Lane | Workflows | Build system |
|---|---|---|
| CMake | `turbo-cmake-container-tests.yaml` (via the reusable `cmake-build.yaml`) | `scripts/build_local_with_spack_env.sh` in the prebuilt `turbo-ci` image |
| legacy | `build-tests.yaml`, `build-tests-iturbo.yaml`, `unit-tests.yaml`, `matrix-compiler-smoketest.yaml`, `code-coverage-reports.yaml` | `./build.sh` in the NCAR CISL dev containers |

The CMake lane runs four cells: the pinned MOM6 submodule and the tip of MOM6's
`dev/turbo-debug` branch, each against both backends. Refreshing the CI image
after a `spack/spack.yaml` change is a manual step — see
[`docker/README.md`](docker/README.md).

## Going further

| Document | What it covers |
|---|---|
| [`scripts/README.md`](scripts/README.md) | **The full build-system reference** — how the build is put together, the dependency tiers and what you supply for each, the two-stage pipeline, `build_dep`, building against a development tree, parallelism, every environment variable |
| [`docs/legacy_build_system.md`](docs/legacy_build_system.md) | The original mkmf `build.sh` build system |
| [`tests/README.md`](tests/README.md) | Writing and adding pFUnit unit tests |
| [`docker/README.md`](docker/README.md) | The CI container image and the workflows that build and consume it |
| [`examples/README.md`](examples/README.md) | Running and archiving the example experiments |
| `docs/*.dot` | Sources for the build-system figures, which `scripts/README.md` uses. After editing one, re-render and commit the PNG: `dot -Tpng -o docs/<name>.png docs/<name>.dot`. Each figure's `*_prompt.md` records what it must show |
