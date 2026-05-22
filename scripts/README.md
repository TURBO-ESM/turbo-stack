# `scripts/`

Build orchestration for turbo-stack. The directory is organized around a **2-step pipeline**:

1. **Set up the environment** — get a working toolchain (compiler, MPI, NetCDF, CMake) on `PATH` AND build/install any dependencies the toolchain doesn't provide.
2. **Build turbo-stack** — `cmake` configure + build + `ctest`.

Different machines/flavors fill in step 1 differently; step 2 is always the same.

---

## Layout

```
scripts/
  README.md                                   # ← this file
  build_with_spack.sh                         # ORCHESTRATOR — spack flavor one-command (steps 1+2)
  build_dep.sh                                # library — defines build_dep() (sourced)
  fetch_source.sh                             # library — defines fetch_source() (sourced)
  build_turbo_stack.sh                        # STEP 2 — cmake configure + build + ctest (exec'd)
  setup_environment/                          # STEP 1 — one file per flavor/machine (all sourced)
    spack_local_environment.sh                             # generic: spack env activation, no from-source deps
    emulate_derecho_modules_locally_with_spack.sh          # TEMP: emulate Derecho on a laptop via a minimal spack env + from-source deps
    derecho_cpu_gcc_openmpi.sh                             # real Derecho via Lmod modules (CPU, gcc, OpenMPI) + from-source deps
```

Future per-machine orchestrators (`build_on_derecho.sh`, `build_on_derecho_with_gpus.sh`, …) sit alongside `build_with_spack.sh` at the top level.

---

## Workflows

### One-command (spack flavor)

```bash
scripts/build_with_spack.sh                    # configure + build + test
scripts/build_with_spack.sh --debug            # full clean rebuild
scripts/build_with_spack.sh --infra TIM        # spack env + from-source TIM (spack does not package TIM)
```

`build_with_spack.sh` runs all steps. For `--infra TIM` it calls `build_dep tim` inline after `setup_environment/spack_local_environment.sh` because spack provides FMS/pFUnit/AMReX but not TIM.

### Explicit two-step (any flavor; iterative development)

Source the env recipe once per shell, then run `build_turbo_stack.sh` as many times as you like:

```bash
# spack flavor
source scripts/setup_environment/spack_local_environment.sh
scripts/build_turbo_stack.sh                   # for --infra TIM you also need:
                                               #   source scripts/build_dep.sh
                                               #   build_dep tim --build-dir ... --install-prefix ... -- -D64BIT=ON -D32BIT=OFF
                                               #   scripts/build_turbo_stack.sh --infra TIM

# module flavor (Derecho)
source scripts/setup_environment/derecho_cpu_gcc_openmpi.sh    # loads modules AND builds FMS/pFUnit/AMReX/TIM via build_dep
scripts/build_turbo_stack.sh

# laptop-as-Derecho emulation
source scripts/setup_environment/emulate_derecho_modules_locally_with_spack.sh
scripts/build_turbo_stack.sh
```

---

## The `build_dep` function

`scripts/build_dep.sh` defines a function — sourced once, called per dep:

```bash
build_dep <name>
    [--source PATH | --clone --url URL --ref REF --clone-dest DIR]
    --build-dir DIR
    --install-prefix DIR
    [--rebuild]
    [--parallel N | -j N]
    -- [cmake args...]
```

Cmake args go after `--` (mirrors `cmake --build dir -- ...` and `build_turbo_stack.sh`'s own pass-through).

**Source resolution** (first match wins):

1. `--source PATH` — explicit override on the call.
2. `--clone --url U --ref R --clone-dest DIR` — clone into `DIR`, also exports `$<NAME>_ROOT`.
3. `$<NAME>_ROOT` env var — set externally (e.g. by `fetch_source.sh` or by the user).
4. **Submodule fallback** — per-name table inside `build_dep.sh`:

   | `<name>` | submodule path |
   |---|---|
   | `fms`    | `$TURBO_STACK_ROOT/submodules/infra/FMS2` |
   | `pfunit` | `$TURBO_STACK_ROOT/submodules/pFUnit` |
   | `amrex`  | `$TURBO_STACK_ROOT/submodules/amrex` |
   | `tim`    | `$TURBO_STACK_ROOT/submodules/infra/TIM` |

**Sentinel**: `<build-dir>/.installed` is a small KV file recording the source SHA, source path, install prefix, and a sha256 of the (sorted) cmake args. Skip-on-rerun fires only when all four match. Flipping a cmake flag (e.g. `-DAMReX_GPU_BACKEND=CUDA`) triggers a rebuild.

**Side effects on success**: appends `$install_prefix` to `CMAKE_PREFIX_PATH` with a dedup guard. For `name=pfunit`, also exports `PFUNIT_DIR` pointing at the versioned cmake-dir glob.

---

## The `fetch_source` function

`scripts/fetch_source.sh` is for **source-only-consumed** deps — MOM6, MARBL — that turbo-stack's CMakeLists.txt reads via `<NAME>_ROOT` but doesn't build separately:

```bash
fetch_source --name NAME --url URL --branch REF --dest DIR [--force]
```

Idempotent clone-or-fetch + hard-reset to `origin/<branch>` + recursive submodule update. Exports `<NAME_UPPER>_ROOT="$dest"`.

`--url` is required (no default) — see the script header for the rationale.

For *buildable* deps (FMS, pFUnit, AMReX, TIM) that you want to clone from a fork or branch, use `build_dep --clone --url ... --ref ... --clone-dest ...` instead. That handles cloning and building in one call.

---

## Overriding which source a build_dep call uses

To iterate against a local dev tree (no cloning, no submodule):

```bash
export MOM6_ROOT=/home/me/projects/MOM6
export FMS_ROOT=/home/me/projects/FMS
source scripts/setup_environment/derecho_cpu_gcc_openmpi.sh
scripts/build_turbo_stack.sh
```

The env script's build_dep calls pick up `$FMS_ROOT` via the env-var precedence layer; MOM6's CMakeLists reads `$MOM6_ROOT` directly.

---

## Where do dep builds + installs land?

The orchestrators derive the deps location from `--build_dir`:

- `build_with_spack.sh --build_dir /scratch/foo` → deps land at `/scratch/foo/deps/{build,install}/`.
- `build_on_derecho.sh --build_dir /scratch/foo` → same.
- Neither orchestrator given a `--build_dir`: deps land at `$TURBO_STACK_ROOT/deps/default/`.

The orchestrators don't expose a separate flag for the deps location; `--build_dir` is the single knob. Power users who need deps in a path *unrelated* to the turbo-stack build dir can source an env script directly with its `--deps-build-root` flag:

```bash
source scripts/setup_environment/derecho_cpu_gcc_openmpi.sh --deps-build-root /scratch/shared-deps
scripts/build_turbo_stack.sh --build_dir /scratch/my-build
```

---

## Parallel build jobs

`--parallel N` / `-j N` on the orchestrators exports `CMAKE_BUILD_PARALLEL_LEVEL=N`. Every downstream `cmake --build` invocation (deps + turbo-stack) picks it up natively without any flag plumbing. You can also set `CMAKE_BUILD_PARALLEL_LEVEL` in your shell profile / qsub directive / CI config to skip the CLI flag entirely:

```bash
export CMAKE_BUILD_PARALLEL_LEVEL=32
scripts/build_with_spack.sh                 # no --parallel needed
```

When neither is set, cmake's own defaults apply: 1 for Make, nproc for Ninja.

`build_dep.sh` and `build_turbo_stack.sh` also accept their own `--parallel N` flag as a per-call override.

---

## Required environment

Set these in your shell profile (e.g. `~/.bashrc`):

- `TURBO_STACK_ROOT` — path to your turbo-stack clone.
- `SPACK_ROOT` — path to a Spack installation (only needed for the spack flavor).

Optional, for testing against local dev trees:

- `MOM6_ROOT`, `FMS_ROOT`, `TIM_ROOT`, `PFUNIT_ROOT`, `AMREX_ROOT` — when set, override the corresponding submodule default.
- `CMAKE_BUILD_PARALLEL_LEVEL` — when set, controls the default parallelism for every `cmake --build` in the pipeline (see "Parallel build jobs" above).
