# `scripts/`

Build orchestration for turbo-stack.

## Dependency contract (tiers)

turbo-stack classifies every dependency by **its build policy** — see
`docs/dependency_tiers.png` (and `docs/dependency_tiers_prompt.md` to regenerate):

| Tier | Policy | Members |
|------|--------|---------|
| **1 — External, not a submodule** | turbo-stack *never* gets or builds these; you supply them prebuilt (modules / spack / OS packages / hand-compiled) | compilers, MPI, NetCDF, CMake ≥ 3.24, make/ninja, HDF5 |
| **1.5 — External, a submodule** | turbo-stack *can* build these from their submodule (`build_dep` → `find_package`) OR you supply a prebuilt install on `CMAKE_PREFIX_PATH` | AMReX, pFUnit |
| **2 — Internal (we develop), a submodule** | turbo-stack *can* build these from their submodule (or a `*_ROOT` source override) OR you supply a prebuilt install | FMS, TIM |
| **3 — Always built inline** | turbo-stack *always* builds these (`add_subdirectory`); only the SOURCE can be swapped | turbo-stack, MOM6, MARBL |

Tiers 1.5 and 2 share the same build policy (build-from-submodule or supply-prebuilt);
they differ by *source*. "Our code" is not a tier: the repos we co-develop —
**FMS, TIM** (Tier 2) and **MOM6** (Tier 3) — are the ones hot-swappable via
`*_ROOT` (default: the pinned submodule). AMReX/pFUnit (Tier 1.5) are external
submodules with no `*_ROOT` override; MARBL is pinned-submodule-only.

## Pipeline (environment setup → build turbo-stack)

The dependency tiers above are a *classification*; the pipeline is what a machine
actually runs. It has **two stages** (see `docs/build_test_orchestration.png`):

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
2. **Stage 2 — build turbo-stack** *(uniform)* — `build_turbo_stack.sh` runs cmake
   configure + build (and `ctest` when `--tests` is given; unit tests are opt-in),
   compiling Tier 3 (turbo-stack, MOM6, MARBL) against the prepared environment.

Only Stage 1 differs between machines; Stage 2 is always the same. The
single-backend builders (`build_*`) run both stages; the end-to-end test drivers
run a builder once per backend via the shared core in `lib/common.sh`.

---

## Layout

```
scripts/
  README.md                                   # ← this file
  lib/                                        # sourced libraries:
    common.sh                                 #   SHARED CORE — root resolution, arg parsing, turbo_build_*, builder core (turbo_run_backend_builder), matrix/verdict
    build_dep.sh                              #   build_dep() — build one cmake dep (+ rebuild sentinel)
  build_local_with_spack_env.sh               # ORCHESTRATOR — spack flavor, single backend
  build_local_with_system_toolchain.sh        # ORCHESTRATOR — from-source local (bring-your-own toolchain), single backend
  build_on_derecho.sh                         # ORCHESTRATOR — Derecho (Lmod modules), single backend
  build_turbo_stack.sh                        # STAGE 2 — build turbo-stack: cmake configure + build (+ ctest with --tests) (exec'd)
  setup_environment/                          # STAGE 1 (env setup) — toolchain ONLY, one file per flavor (sourced)
    spack_local_environment.sh                #   spack env activation
    local_toolchain_on_path.sh                #   generic local — toolchain already on PATH (no spack/modules)
    derecho_cpu_gcc_openmpi.sh                #   real Derecho via Lmod modules (CPU, gcc, OpenMPI)

# (repo top level) — end-to-end drivers, BOTH backends:
test_turbo_stack_locally.sh                   # local (spack)
test_turbo_stack_with_system_toolchain.sh     # local (bring-your-own toolchain)
test_turbo_stack_on_derecho.sh                # Derecho (qsub or interactive)
```

---

## Workflows

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

### Both backends, one command (end-to-end test)

```bash
./test_turbo_stack_locally.sh                  # local (spack)
./test_turbo_stack_with_system_toolchain.sh    # local (bring-your-own toolchain on PATH)
./test_turbo_stack_on_derecho.sh               # Derecho (qsub or interactive)
```

Each runs the real single-backend builder once per backend (each in its own
process, from scratch), builds + `ctest`s turbo-stack for FMS2 and TIM, and prints
a per-backend matrix/verdict. `--only FMS2|TIM`, `--parallel N`, `--clean`.  All
three support the `fetch_*` / `*_ROOT` overrides described below.

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

CMake args go after `--` (mirrors `cmake --build dir -- ...`).  This is `build_dep`'s
own convention; `build_turbo_stack.sh` has no `--` pass-through -- extra cmake
arguments there come from `TURBO_CMAKE_CONFIGURE_ARGS` / `TURBO_CMAKE_BUILD_ARGS`.

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

**Side effects on success**: appends `$install_prefix` to `CMAKE_PREFIX_PATH` with a dedup guard. For `name=pfunit`, also exports `PFUNIT_DIR` pointing at the versioned cmake-dir glob.

---

## Overriding which source a build uses (hot-swap)

To iterate against a local dev tree of a co-developed repo (no cloning, no
submodule), export its `*_ROOT` before building:

```bash
export MOM6_ROOT=/home/me/projects/MOM6
export FMS_ROOT=/home/me/projects/FMS
scripts/test_turbo_stack_locally.sh        # or build_local_with_spack_env.sh, or the explicit flow
```

`turbo_build_fms` (→ `build_dep`) picks up `$FMS_ROOT` via the source-resolution
precedence below; MOM6's CMakeLists reads `$MOM6_ROOT` directly. The testing
matrix printed at the top of each driver shows whether each component resolved to
its submodule or to an override.

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

An out-of-tree MOM6 source (`MOM6_ROOT`) is a build *input*, not a build
artifact, so it does not land here at all — see above.

In the explicit flow you pass the `build` and `install` roots straight to the
`turbo_build_*` wrappers, so any layout is possible.

---

## Machine- and run-specific CMake flags

Two environment variables are appended to the CMake command lines:

| Variable | Appended to |
|---|---|
| `TURBO_CMAKE_CONFIGURE_ARGS` | the `cmake` **configure** line |
| `TURBO_CMAKE_BUILD_ARGS` | `cmake --build` |

```bash
TURBO_CMAKE_CONFIGURE_ARGS=-DCMAKE_EXPORT_COMPILE_COMMANDS=ON ./test_turbo_stack_locally.sh
TURBO_CMAKE_BUILD_ARGS=-v scripts/build_local_with_spack_env.sh --infra TIM
```

Variables rather than flags, for the same reason `CMAKE_BUILD_PARALLEL_LEVEL` is
one: the need is *"on this machine, always pass X"* and *"for this run, also pass
Y"*. A variable expresses both from a shell profile, a qsub directive, a flavor's
`setup_environment/` recipe, or a CI `env:` block — and every entry point picks
it up without any script parsing or forwarding it.

They are appended **after** the options the scripts choose themselves, and CMake
takes the last `-D` for a given variable, so a machine can override
`CMAKE_BUILD_TYPE` and friends.

### Compiler flags go through CMake's own variables

Split on whitespace, so **a single argument cannot contain a space**. That is a
smaller limitation than it looks, because the case that needs one — per-machine
compiler flags — is handled by CMake itself. It seeds `CMAKE_Fortran_FLAGS`,
`CMAKE_C_FLAGS` and `CMAKE_CXX_FLAGS` from `FFLAGS`, `CFLAGS` and `CXXFLAGS` at
first configure:

```bash
FFLAGS="-O2 -g" ./test_turbo_stack_locally.sh
```

Same idea as `CMAKE_BUILD_PARALLEL_LEVEL` — CMake reads it natively, so no script
has to forward anything. Everything the two `TURBO_CMAKE_*` variables are for
(`-DSOME_OPTION=ON`, `--target foo`) is space-free argument by argument — `--target
foo` is two arguments, but neither contains a space — so whitespace splitting is
enough and no `eval` is involved.

If a genuinely space-containing option ever does come up, `cmake -C
<initial-cache-file>` is the robust answer: the values live in CMake code rather
than in a shell string, so no quoting question arises at all.

One caveat: **the values are not re-passed when unset**, so one set once persists
in `CMakeCache.txt` for that build directory. Ordinary CMake behaviour, but it
means dropping the variable does not revert the setting — use `--clean` or a
fresh `--build_dir`.

`MOM6_INFRA` and `TURBO_BUILD_UNIT_TESTS` are **rejected by the orchestrators**.
Those also decide [Stage 1](#pipeline-environment-setup--build-turbo-stack) —
which backend's dependencies get built, and whether pFUnit is built at all — and
Stage 1 reads `--infra`/`--tests`, not these variables. Setting them here would
build one configuration and compile another, so it fails at argument-parse time,
before any dependency is built. Use `--infra` and `--tests`.

`build_turbo_stack.sh` on its own does *not* reject them: it is Stage 2, there is
no Stage 1 in that invocation to disagree with, and a caller driving it directly
is managing their own environment.

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

- `TURBO_STACK_ROOT` — normally **not set**; every entry point self-locates its
  own checkout (via `lib/common.sh`), so you build the checkout you run from.
  turbo-stack is a top-level orchestrator, so there is no "root override" — to
  build a different copy, run *its* scripts. If an exported `TURBO_STACK_ROOT`
  disagrees with the script's own location the script hard-errors (unset it)
  rather than silently using the other copy (the multi-checkout footgun).
- `SPACK_ROOT` — required for the spack flavor (local builds).

Optional, for testing against local dev trees:

- `MOM6_ROOT`, `FMS_ROOT`, `TIM_ROOT` — hot-swap a co-developed repo's source
  (default: the pinned submodule).
- `CMAKE_BUILD_PARALLEL_LEVEL` — default parallelism for every `cmake --build` in the pipeline (see "Parallel build jobs").
