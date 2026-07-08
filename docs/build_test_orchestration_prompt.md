# Build/test pipeline — recreation prompt

Use the prompt below to regenerate `build_test_orchestration.dot` (and the PNG) with Claude Code after
the orchestration scripts change. It describes the structure and data flow, not exact dot syntax.

Render with: `dot -Tpng -o docs/build_test_orchestration.png docs/build_test_orchestration.dot`.

This is the canonical pipeline figure. `local_spack_pipeline` and the old
`test_new_build_system_on_derecho` figures were retired in favour of it; `two_stage_pipeline` is kept as
a more detailed companion. Both use the same two stages: **Stage 1 — environment setup** (source the
toolchain, then build the upstream deps) and **Stage 2 — build turbo-stack**. The dependency *tiers*
(1 / 1.5 / 2 / 3) are a separate classification (see `dependency_tiers_prompt.md`): Stage 1 satisfies
Tiers 1, 1.5 and 2; Stage 2 builds Tier 3.

---

## Prompt

Generate a Graphviz dot file at `docs/build_test_orchestration.dot` showing the turbo-stack build/test
orchestration, and render to `docs/build_test_orchestration.png` with `dot -Tpng`.

### Narrative the figure must land
- **Every labelled box is a script; the steps inside it are what that script does.**  Put this idea
  in the graph title.
- There are **two machine paths** that share the tail.  Each path is: a **test driver** (loops the
  backends) → a **single-backend builder** (does Stage 1: environment setup — toolchain + deps) → the
  **shared `build_turbo_stack.sh`** (Stage 2) → verdict.  The driver does NOT re-implement the stages
  — it runs the real builder a user would run, once per backend, each in its own process.
- **Script ownership must be legible:**
  - The **test driver** does: parse args · loop backends · print verdict (put these in its label).
  - The **builder** box contains its Stage 1 (environment setup) steps: source the toolchain env
    (builds nothing → Tier 1) and build the upstream deps (`turbo_build_*` from submodule, or a
    `*_ROOT` override — AMReX/pFUnit = Tier 1.5, FMS/TIM = Tier 2).
  - **`build_turbo_stack.sh`** is Stage 2 (cmake configure/build → ctest; builds Tier 3), exec'd by
    each builder, and is SHARED by both paths (a single node both paths converge on).
  - The verdict is printed by the test driver.
- `scripts/lib/common.sh` is the shared-helpers substrate used by all scripts (NOT a flow step): show
  it as a side note, high level — "root self-location · arg parsing · `turbo_build_*` wrappers · the
  per-backend loop + verdict (`turbo_run_test_driver`)".
- Source overrides default to the pinned submodule: `*_ROOT` points at a local dev tree of a
  co-developed repo (MOM6/FMS/TIM).  `FMS_ROOT`/`TIM_ROOT` feed each builder's Stage-1 dep builds;
  `MOM6_ROOT` feeds Stage-2's CMake.

### Visual language
- Test-driver ellipses `#fffacd`.
- Path A (local · spack) builder cluster fill `#e7eff8`; Path B (Derecho · Lmod modules) builder
  cluster fill `#fbeee6`.  Cluster label = the builder script name + "(run once per backend)",
  `labeljust=l`.
- Stage-1 toolchain box `#bcd4ec`; Stage-1 deps box `#c8e6c9`; shared Stage-2 ellipse `#90ee90`; verdict box `#c8e6c9`.
- `common.sh` note: `shape=note` `#dce8f5`.  Overrides note: `shape=note` `#fff2cc`.
- `rankdir=TB`, `splines=ortho`, `compound=true`, `newrank=true`.  Edge text via `xlabel=`.  Point
  edges at specific nodes (never `lhead=cluster_*`).

### Nodes & flow
- Two **test-driver** ellipses at `{rank=same}`: `test_turbo_stack_locally.sh` and
  `test_turbo_stack_on_derecho.sh (qsub / bash)`, each labelled with "parse args · loop backends ·
  print verdict".
- Two **builder clusters** (the boxes ARE the builder scripts), each containing a Stage-1 toolchain
  box → Stage-1 deps box:
  - `build_local_with_spack_env.sh`: toolchain = source `spack_local_environment.sh` (builds nothing
    → Tier 1); deps = the selected backend only — `turbo_build_fms` for FMS2 or `turbo_build_tim` for
    TIM (mutually exclusive; both Tier 2); pFUnit / AMReX (Tier 1.5) come from spack.
  - `build_on_derecho.sh`: toolchain = source `derecho_cpu_gcc_openmpi.sh` (builds nothing → Tier 1);
    deps = `turbo_build_pfunit ; _fms ; _amrex ; _tim` (pFUnit/AMReX = Tier 1.5; FMS/TIM = Tier 2).
- Each driver → its builder's Stage-1 toolchain node (xlabel "loop: --infra FMS2, then TIM").
- Each builder's Stage-1 deps node → the shared **`build_turbo_stack.sh`** ellipse (xlabel "exec"); its
  label notes "exec'd by each builder" + "Stage 2: cmake configure/build → ctest (Tier 3)".  Unit tests
  are opt-in (`--tests`); the test drivers pass it, so ctest runs in the driven pipeline.
- Shared `build_turbo_stack.sh` → **verdict** box ("testing matrix + per-backend verdict … printed by
  the test driver").
- **`common.sh` note** → each driver, dashed (`color="#5b7aa6"`, `arrowhead=odot`, `constraint=false`).
- **Overrides note** → each builder's Stage-1 deps box (xlabel "FMS_ROOT / TIM_ROOT") and → the shared
  Stage-2 ellipse (xlabel "MOM6_ROOT"), dashed (`color="#a06000"`, `arrowhead=odot`, `constraint=false`).
