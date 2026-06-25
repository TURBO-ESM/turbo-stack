# Build/test pipeline — recreation prompt

Use the prompt below to regenerate `turbo_stack_pipeline.dot` (and the PNG) with Claude Code after
the orchestration scripts change. It describes the structure and data flow, not exact dot syntax.

Render with: `dot -Tpng -o docs/turbo_stack_pipeline.png docs/turbo_stack_pipeline.dot`.

This is the canonical tier-based pipeline figure. `local_spack_pipeline` and the old
`test_new_build_system_on_derecho` figures were retired in favour of it; `build_pipeline` is kept as
a more detailed, Stage-based companion (env+deps as Stage 1, build as Stage 2).

---

## Prompt

Generate a Graphviz dot file at `docs/turbo_stack_pipeline.dot` showing the turbo-stack build/test
orchestration, and render to `docs/turbo_stack_pipeline.png` with `dot -Tpng`.

### Narrative the figure must land
- **Every labelled box is a script; the steps inside it are what that script does.**  Put this idea
  in the graph title.
- There are **two machine paths** that share the tail.  Each path is: a **test driver** (loops the
  backends) → a **single-backend builder** (does Tier 1 + Tier 2) → the **shared `build_turbo_stack.sh`**
  (Tier 3) → verdict.  The driver does NOT re-implement the tiers — it runs the real builder a user
  would run, once per backend, each in its own process.
- **Script ownership must be legible:**
  - The **test driver** does: parse args · loop backends · print verdict (put these in its label).
  - The **builder** box contains the steps it performs: Tier 1 (source the toolchain env; builds
    nothing) and Tier 2 (`turbo_build_*` from submodule, or a `*_ROOT` override).
  - **`build_turbo_stack.sh`** is Tier 3 (cmake configure/build → ctest), exec'd by each builder, and
    is SHARED by both paths (a single node both paths converge on).
  - The verdict is printed by the test driver.
- `scripts/lib/common.sh` is the shared-helpers substrate used by all scripts (NOT a flow step): show
  it as a side note, high level — "root self-location · arg parsing · `turbo_build_*` wrappers · the
  per-backend loop + verdict (`turbo_run_test_driver`)".
- Overrides default to the pinned submodule: `fetch_*` clones a branch; `*_ROOT` points at a dev
  tree.  `FMS_ROOT`/`TIM_ROOT` feed each builder's Tier-2; `MOM6_ROOT` feeds Tier-3's CMake.

### Visual language
- Test-driver ellipses `#fffacd`.
- Path A (local · spack) builder cluster fill `#e7eff8`; Path B (Derecho · Lmod modules) builder
  cluster fill `#fbeee6`.  Cluster label = the builder script name + "(run once per backend)",
  `labeljust=l`.
- Tier-1 box `#bcd4ec`; Tier-2 box `#c8e6c9`; shared Tier-3 ellipse `#90ee90`; verdict box `#c8e6c9`.
- `common.sh` note: `shape=note` `#dce8f5`.  Overrides note: `shape=note` `#fff2cc`.
- `rankdir=TB`, `splines=ortho`, `compound=true`, `newrank=true`.  Edge text via `xlabel=`.  Point
  edges at specific nodes (never `lhead=cluster_*`).

### Nodes & flow
- Two **test-driver** ellipses at `{rank=same}`: `test_turbo_stack_locally.sh` and
  `test_turbo_stack_on_derecho.sh (qsub / bash)`, each labelled with "parse args · loop backends ·
  print verdict".
- Two **builder clusters** (the boxes ARE the builder scripts), each containing a Tier-1 box → Tier-2
  box:
  - `build_local_with_spack_env.sh`: Tier 1 = source `spack_local_environment.sh` (builds nothing);
    Tier 2 = `turbo_build_fms ; turbo_build_tim` (pFUnit / AMReX come from spack).
  - `build_on_derecho.sh`: Tier 1 = source `derecho_cpu_gcc_openmpi.sh` (builds nothing); Tier 2 =
    `turbo_build_pfunit ; _fms ; _amrex ; _tim`.
- Each driver → its builder's Tier-1 node (xlabel "loop: --infra FMS2, then TIM").
- Each builder's Tier-2 node → the shared **`build_turbo_stack.sh`** ellipse (xlabel "exec"); its
  label notes "exec'd by each builder" + "Tier 3: cmake configure/build → ctest".
- Shared `build_turbo_stack.sh` → **verdict** box ("testing matrix + per-backend verdict … printed by
  the test driver").
- **`common.sh` note** → each driver, dashed (`color="#5b7aa6"`, `arrowhead=odot`, `constraint=false`).
- **Overrides note** → each builder's Tier-2 box (xlabel "FMS_ROOT / TIM_ROOT") and → the shared
  Tier-3 ellipse (xlabel "MOM6_ROOT"), dashed (`color="#a06000"`, `arrowhead=odot`, `constraint=false`).
