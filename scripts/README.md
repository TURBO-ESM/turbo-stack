# `scripts/`

Build orchestration for turbo-stack. The directory is organized around a **3-step pipeline**:

1. **Set up the environment** — get a working toolchain (compiler, MPI, NetCDF, CMake) on `PATH` and set the env vars turbo-stack's CMake needs.
2. **Build dependencies from source** — when something the toolchain doesn't provide (FMS, pFUnit, AMReX, TIM) needs to be cmake-built and installed into a per-tag prefix.
3. **Build turbo-stack** — `cmake` configure + build + `ctest`.

Different machines/flavors fill in steps 1 and 2 differently; step 3 is always the same.

---

## Layout

```
scripts/
  README.md                                   # ← this file
  build_with_spack.sh                         # ORCHESTRATOR — spack flavor one-command (steps 1+2+3)
  build_dependencies_from_source.sh           # STEP 2 — builds FMS/pFUnit/AMReX/TIM from source (sourced)
  build_turbo_stack.sh                        # STEP 3 — cmake configure + build + ctest (exec'd)
  setup_environment/                                    # STEP 1 — one file per flavor/machine (all sourced)
    spack_local_environment.sh                             # generic: spack env activation
    emulate_derecho_modules_locally_with_spack.sh          # TEMP: emulate Derecho on a laptop via a minimal spack env
    derecho_cpu_gcc_openmpi.sh                             # real Derecho via Lmod modules (CPU, gcc, OpenMPI)
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

`build_with_spack.sh` runs all three steps. For `--infra TIM` it sources `build_dependencies_from_source.sh --only tim` after `setup_environment/spack_local_environment.sh` because spack provides FMS/pFUnit/AMReX but not TIM.

### Explicit two-step (any flavor; iterative development)

Source the env recipe once per shell, then run `build_turbo_stack.sh` as many times as you like:

```bash
# spack flavor
source scripts/setup_environment/spack_local_environment.sh
scripts/build_turbo_stack.sh                   # for --infra TIM you also need:
                                               #   source scripts/build_dependencies_from_source.sh --only tim
                                               #   scripts/build_turbo_stack.sh --infra TIM

# module flavor (Derecho)
source scripts/setup_environment/derecho_cpu_gcc_openmpi.sh    # loads modules AND builds FMS/pFUnit/AMReX/TIM via step 2
scripts/build_turbo_stack.sh

# laptop-as-Derecho emulation
source scripts/setup_environment/emulate_derecho_modules_locally_with_spack.sh
scripts/build_turbo_stack.sh
```

---

## How dependencies are resolved

`build_dependencies_from_source.sh` looks at five env vars to decide where each dependency's source tree lives:

| Env var | Default if unset | Role |
|---|---|---|
| `MOM6_ROOT` | `$TURBO_STACK_ROOT/submodules/MOM6` | Read by top-level `CMakeLists.txt` — MOM6 is built in-tree, not installed |
| `FMS_ROOT` | `$TURBO_STACK_ROOT/submodules/infra/FMS2` | Source for the FMS build → install prefix |
| `TIM_ROOT` | `$TURBO_STACK_ROOT/submodules/infra/TIM` | Source for the TIM build → install prefix |
| `PFUNIT_ROOT` | `$TURBO_STACK_ROOT/submodules/pFUnit` | Source for the pFUnit build → install prefix |
| `AMREX_ROOT` | `$TURBO_STACK_ROOT/submodules/amrex` | Source for the AMReX build → install prefix |

To test against a local dev tree, export the corresponding `_ROOT` before sourcing the env recipe:

```bash
export MOM6_ROOT=/home/me/projects/MOM6
source scripts/setup_environment/derecho_cpu_gcc_openmpi.sh
scripts/build_turbo_stack.sh
```

To skip building a specific dep (e.g., when spack already provides it):

```bash
# spack flavor: skip everything except TIM (this is what build_with_spack.sh --infra TIM does)
source scripts/build_dependencies_from_source.sh --only tim
```

Flags on `build_dependencies_from_source.sh`: `--tag`, `--prefix`, `--parallel|-j`, `--rebuild`, `--no-fms`, `--no-pfunit`, `--no-amrex`, `--no-tim`, `--only LIST`.

---

## Required environment

Set these in your shell profile (e.g. `~/.bashrc`):

- `TURBO_STACK_ROOT` — path to your turbo-stack clone.
- `SPACK_ROOT` — path to a Spack installation (only needed for the spack flavor).

Optional, for testing against local dev trees:

- `MOM6_ROOT`, `TIM_ROOT` (or others) — when set, override the submodule default.

---

## Design rationale & history

See [`../setup_env_separation_plan.md`](../setup_env_separation_plan.md) at the repo root for the design discussion, refactor status, and known issues (e.g. stale submodule pins).
