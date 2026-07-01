# `scripts/`

Build orchestration for turbo-stack.

## Dependency contract (tiers)

turbo-stack classifies every dependency by **its build policy** — see
`docs/dependency_tiers.png` (and `docs/dependency_tiers_prompt.md` to regenerate):

| Tier | Policy | Members |
|------|--------|---------|
| **1 — Prerequisites** | turbo-stack *never* builds these; you provide them (modules / spack / OS packages) | compilers, MPI, NetCDF, CMake ≥ 3.24, make/ninja, FFTW, HDF5 |
| **2 — Convenience-built** | turbo-stack *can* build these from a submodule (`build_dep` → `find_package`); you may supply your own instead | AMReX, pFUnit, FMS, TIM |
| **3 — Always built inline** | turbo-stack *always* builds these (`add_subdirectory`) | turbo-stack, MOM6, MARBL |

"Our code" is not a tier: the repos we co-develop — **FMS, TIM** (Tier 2) and
**MOM6** (Tier 3) — are the ones hot-swappable via `*_ROOT` (default: the pinned
submodule). MARBL is pinned-submodule-only.

## Pipeline (3 stages)

The directory is organized around a **3-stage pipeline** (see
`docs/turbo_stack_pipeline.png`):

1. **Tier-1 toolchain** — a `setup_environment/<flavor>.sh` recipe (sourced) puts
   a compiler / MPI / NetCDF / CMake on `PATH`. **These recipes build nothing** —
   they only prepare the shell.
2. **Tier-2 deps** — the caller *explicitly* builds the convenience deps the
   toolchain didn't already provide, via the `turbo_build_*` wrappers in
   `lib/common.sh` (the canonical per-dep cmake flags live there, once).
3. **Build turbo-stack** — `build_turbo_stack.sh` runs cmake configure + build + `ctest`.

Different machines fill in stage 1 (and which Tier-2 deps need building)
differently; stage 3 is always the same. The single-backend builders (`build_*`)
run all three stages; the end-to-end test drivers run a builder once per backend
via the shared core in `lib/common.sh`.

---

## Layout

```
scripts/
  README.md                                   # ← this file
  lib/                                        # sourced libraries:
    common.sh                                 #   SHARED CORE — root resolution, arg parsing, turbo_build_*, matrix/verdict
    build_dep.sh                              #   build_dep() — build one cmake dep (+ rebuild sentinel)
  build_local_with_spack_env.sh                         # ORCHESTRATOR — spack flavor, single backend
  build_on_derecho.sh                         # ORCHESTRATOR — Derecho (Lmod modules), single backend
  build_turbo_stack.sh                        # STAGE 3 — cmake configure + build + ctest (exec'd)
  setup_environment/                          # STAGE 1 — Tier-1 toolchain ONLY, one file per flavor (sourced)
    spack_local_environment.sh                #   spack env activation
    derecho_cpu_gcc_openmpi.sh                #   real Derecho via Lmod modules (CPU, gcc, OpenMPI)

# (repo top level) — end-to-end drivers, BOTH backends:
test_turbo_stack_locally.sh                   # local (spack)
test_turbo_stack_on_derecho.sh                # Derecho (qsub or interactive)
```

---

## Workflows

### One-command (spack flavor)

```bash
scripts/build_local_with_spack_env.sh                    # configure + build + test
scripts/build_local_with_spack_env.sh --debug            # incremental Debug build
scripts/build_local_with_spack_env.sh --clean            # clean rebuild from scratch
scripts/build_local_with_spack_env.sh --infra TIM        # spack env + from-source TIM (spack does not package TIM)
```

`build_local_with_spack_env.sh` runs all stages. It builds the selected backend via `turbo_build_fms`/`turbo_build_tim` after sourcing `setup_environment/spack_local_environment.sh` — spack provides pFUnit/AMReX but neither FMS nor TIM.

### Both backends, one command (end-to-end test)

```bash
./test_turbo_stack_locally.sh                  # local (spack)
./test_turbo_stack_on_derecho.sh               # Derecho (qsub or interactive)
```

Each runs the real single-backend builder once per backend (each in its own
process, from scratch), builds + `ctest`s turbo-stack for FMS2 and TIM, and prints
a per-backend matrix/verdict. `--only FMS2|TIM`, `--parallel N`, `--clean`.  Both
support the `fetch_*` / `*_ROOT` overrides described below.

### Explicit, iterative (any flavor)

Stage 1 (toolchain) is sourced once per shell; then explicitly build the Tier-2
deps you need and run `build_turbo_stack.sh` as often as you like:

```bash
source scripts/lib/common.sh                                   # turbo_build_* wrappers + helpers
source scripts/setup_environment/spack_local_environment.sh    # Tier-1 (spack); builds NOTHING
deps="$TURBO_STACK_ROOT/deps/default"
turbo_build_fms "$deps/build" "$deps/install"                  # Tier-2 (spack supplies pFUnit/AMReX)
scripts/build_turbo_stack.sh                                   # Tier-3 (FMS2)
# TIM backend instead:
turbo_build_tim "$deps/build" "$deps/install"
scripts/build_turbo_stack.sh --infra TIM
```

On a modules machine, swap stage 1 for
`source scripts/setup_environment/derecho_cpu_gcc_openmpi.sh` and also build the
deps the modules don't provide (`turbo_build_pfunit`, `turbo_build_amrex`).

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

---

## Where do dep builds + installs land?

The orchestrators derive the deps location from `--build_dir`:

- `build_local_with_spack_env.sh --build_dir /scratch/foo` → deps land at `/scratch/foo/deps/{build,install}/`.
- `build_on_derecho.sh --build_dir /scratch/foo` → same.
- Neither orchestrator given a `--build_dir`: deps land at `$TURBO_STACK_ROOT/deps/default/`.

- The end-to-end test drivers build each backend independently under
  `$TURBO_BUILD_SYSTEM_TEST_DIR/turbo-stack-with-<backend>/` (deps in its `deps/` subdir).

In the explicit flow you pass the `build` and `install` roots straight to the
`turbo_build_*` wrappers, so any layout is possible.

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

- `TURBO_STACK_ROOT` — **optional**; every entry point self-locates its own
  checkout (via `lib/common.sh`). Set it only to override — a warning fires if an
  exported value disagrees with the script's own location (the multi-checkout
  footgun).
- `SPACK_ROOT` — required for the spack flavor (local builds).

Optional, for testing against local dev trees:

- `MOM6_ROOT`, `FMS_ROOT`, `TIM_ROOT` — hot-swap a co-developed repo's source
  (default: the pinned submodule). `PFUNIT_ROOT`, `AMREX_ROOT` are also honored by `build_dep`.
- `CMAKE_BUILD_PARALLEL_LEVEL` — default parallelism for every `cmake --build` in the pipeline (see "Parallel build jobs").
