# Legacy build system — mkmf `build.sh`

> [!IMPORTANT]
> This is the **original** turbo-stack build system, driven by `build.sh` and the
> GFDL [mkmf](https://github.com/NOAA-GFDL/mkmf) makefile generator. It is kept
> working while the project migrates, but **new work should use the CMake build
> system** described in the [top-level README](../README.md) and documented in
> full in [`scripts/README.md`](../scripts/README.md).

The two build systems are independent — different drivers, different dependency
handling, different output locations — so they do not interfere with each other.
Both are exercised in CI, in separate lanes:

| Lane | Workflows |
|---|---|
| legacy (this document) | `build-tests.yaml`, `build-tests-iturbo.yaml`, `unit-tests.yaml`, `matrix-compiler-smoketest.yaml`, `code-coverage-reports.yaml` |
| CMake | `turbo-cmake-container-tests.yaml` (via the reusable `cmake-build.yaml`) |

Everything below is the build documentation as it stood before the CMake build
system landed, preserved so that existing instructions, job scripts and habits
keep working.

---

## Building the MOM6 executable on derecho

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

You can also specify an infrastructure layer other than the default `TIM`, e.g.,

```bash
./build.sh --infra FMS2
```

> [!NOTE]
> The README documented `FMS2` as `build.sh`'s default backend. That stopped
> being true in commit `a662188` ("Change default infra to TIM", 2026-04-22),
> which moved the default to `TIM` without updating the README. Corrected here;
> `build.sh --help` is authoritative.

Once the build is complete, the executable will be at `bin/[COMPILER]/MOM6_using_[INFRA]/MOM6/MOM6`.

## Building the MOM6 executable on other machines

To port this repository to a new machine, create a new makefile template in the `build-utils/makefile-templates/`
directory, following the naming convention `[MACHINE_NAME]-[COMPILER].mk`. You can use the existing templates as a reference.

Once the template is created, you can build the MOM6 executable using the `build.sh` script by
specifying the machine name and compiler, e.g.,

```bash
./build.sh --machine ubuntu --compiler gnu
```

## Building with different infrastructure backends

MOM6 can be built either with FMS2 or with the new Turbo Infrastructure for MOM (TIM) layer backed by AMReX.  The options to enable this are:

```bash
./build.sh ... --infra TIM
```

This will use the new TIM library and interface with MOM6 and will build AMReX as needed from source locally.

To leverage a pre-existing AMReX install, do:

```bash
./build.sh ... --infra TIM --amrex /path/to/amrex/install
```

The AMReX path should be the top level install directory which contains `lib`, `include`, etc.  The AMReX install must be built with Fortran and Fortran interfaces activated which are currently not the default (see [the customization options here](https://amrex-codes.github.io/amrex/docs_html/BuildingAMReX.html#customization-options) for more options).

See the TURBO specific [Makefile](../build-utils/amrex-utils/Makefile) that builds AMReX with the current needed options.

## Running unit tests

To build and run the unit tests instead of building MOM6, you can add `--unit-tests-only` to the build command.

This will run the unit tests in the test directory and will produce output similar to:

```
Test project /path/to/turbo/unit-tests
    Start 1: infra_tests
1/1 Test #1: infra_tests ......................   Passed    0.54 sec

100% tests passed, 0 tests failed out of 1

Total Test time (real) =   0.54 sec
make: Leaving directory '/path/to/turbo/unit-tests'
Finished build at Mon Jan  1 00:00:00 PM MST 1970
```

Currently, unit tests only test the interface and TIM source, not MOM6 or FMS.

The legacy suite lives in [`tests-legacy/`](../tests-legacy/); the pFUnit suite
the CMake build runs is [`tests/`](../tests/).

## Running example experiments with a legacy build

The examples in [`examples/`](../examples/) work with either build system — only
the path to the executable differs. For a legacy build:

```bash
cd examples/double_gyre/
../../bin/intel/MOM6_using_TIM/MOM6/MOM6
```

The path encodes what you built: `bin/<compiler>/MOM6_using_<infra>/MOM6/MOM6`.
The command above is what a default `./build.sh` produces (`intel`, `TIM`); a
`./build.sh --compiler gnu --infra FMS2` lands at
`bin/gnu/MOM6_using_FMS2/MOM6/MOM6` instead. The `job-*.sh` scripts in each
example set `COMPILER` and `INFRA` at the top for the same reason.

See the [top-level README](../README.md) for the equivalent CMake paths and for
the `make archive` / `make clean` workflow, which is build-system independent.

## All `build.sh` options

`build.sh --help` prints the authoritative list. As of this writing:

```
Usage: ./build.sh [--compiler <compiler>] [--machine <machine>] [--memory-mode <memory_mode>] [--infra <infra>] [--codecov] [--offload] [--debug] [--override]
  --compiler <compiler>        Compiler to use (default: intel)
  --machine <machine>          Machine type (default: ncar)
  --memory-mode <memory_mode>  Memory mode (default: dynamic_symmetric)
  --infra <infra>              Subdirectory of config_src/infra/ to build
                               (valid values [FMS2, TIM]; default: TIM)
  --codecov                    Enable code coverage (default: disabled)
  --debug                      Enable debug mode (default: disabled)
  --override                   If a build already exists, clear it and rebuild (default: false)
  --unit-tests-only            Build infrastructure unit tests rather than MOM6 executable (default: false)
  --offload                    Enable GPU offload instead of host only CPU mode (default: false)
  --amrex <path_to_amrex>      Specifies the path to search for a pre-installed build of amrex
  --pfunit <path_to_pfunit>    Specified the path to search for a pre-installed build of pfunit
  --jobs <num_jobs>            Sets the number of jobs to use for make/cmake calls.
```

## Supporting machinery

| Path | Purpose |
|---|---|
| `build.sh` | The driver |
| `build-utils/mkmf/` | GFDL makefile generator |
| `build-utils/makefile-templates/` | Per-machine × compiler makefile fragments (`[MACHINE]-[COMPILER].mk`) |
| `build-utils/amrex-utils/Makefile` | Builds AMReX with the options TURBO needs |
| `build-utils/pfunit-utils/` | pFUnit build support for the legacy unit tests |
| `build-utils/pio-utils/` | ParallelIO build support |
| `tests-legacy/` | The legacy unit-test suite |
| `bin/` | Build output (`bin/[COMPILER]/MOM6_using_[INFRA]/MOM6/MOM6`); git-ignored |
