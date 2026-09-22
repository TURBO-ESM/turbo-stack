# Two-stage pipeline — recreation prompt

Use the prompt below to regenerate `two_stage_pipeline.dot` (and the PNG) with Claude Code when the
build's stage structure changes. It describes the two stages and their data flow, not the exact dot
syntax.

Render with: `dot -Tpng -o docs/two_stage_pipeline.png docs/two_stage_pipeline.dot`.

This is the conceptual companion to `build_test_orchestration` (which shows the driver/builder
*script* flow across machines). This figure is deliberately flavor-agnostic: it shows only the two
stages and the shell-state boundary between them.

---

## Prompt

Generate a Graphviz dot file at `docs/two_stage_pipeline.dot` showing the two-stage build pipeline of
turbo-stack, and render it to `docs/two_stage_pipeline.png` with `dot -Tpng`.

### Narrative the figure must land
- **Stage 1 — "Environment"**: prepare everything the build needs — the toolchain (compilers, CMake,
  make/ninja) plus the installed dependency prefixes — and collapse it all into a single "Expected
  environment (shell state)" box.
- **Stage 2 — "build_turbo_stack.sh"**: cmake configure → build → (opt-in) ctest, producing the
  MOM6 / turbo-stack build output.
- **The hand-off is the central message**: a single bold edge carries the Stage-1 shell state into
  Stage 2; `build_turbo_stack.sh` has no knowledge of the Stage-1 setup beyond what that shell state
  carries.
- Deliberately flavor-agnostic: NO launch wrappers, NO orchestrator scripts, NO spack-vs-modules
  split, NO `build_dep`/source-resolution detail. That machine/script flow lives in
  `build_test_orchestration`; keep this figure to just the two stages and their boundary.

### Layout rules
- `rankdir=TB`, `splines=ortho`, `compound=true`, `newrank=true`.
- Two outer clusters stacked top→bottom with distinct fills so the boundary is obvious:
  - `cluster_stage1` — label `"Environment"`, fill `#dce8f5`, `margin=14`.
  - `cluster_stage2` — label `"build_turbo_stack.sh"`, fill `#d8f0d8`, `margin=14`.
- Node shapes: **box** for toolchain tools and the cmake step boxes; **cylinder** for installed dep
  artifacts (the prefixes that land on `CMAKE_PREFIX_PATH`); **ellipse** for `ctest`.
- Edge text via `xlabel=` (the ortho router does not place inline `label=` reliably).
- The two cross-cluster hand-off edges terminate at a cluster with `lhead=cluster_*` — this is the one
  place `lhead` is intended: `cmake --build → MOM6 install` with `lhead=cluster_turbo_stack_build_output`,
  and the bold `stage1_outputs → cmake configure` with `lhead=cluster_stage2`. Every other edge points
  at a specific named node.
- Bold edge (`penwidth=2`) for the Stage 1 → Stage 2 hand-off.

### Stage 1 — "Environment" cluster
Put all the toolchain + install nodes on ONE rank (`rank=same`), ordered left→right with invisible
weighted edges, all feeding one outputs box:
- Sub-cluster **"Tools"** (white fill): boxes `Compilers`, `CMake`, `make or ninja` — all `#bcd4ec`.
- **External prebuilt installs** (a bare subgraph, no visible box): cylinders `MPI install`,
  `NetCDF install`, `HDF5 install` (`#bcd4ec`). These are Tier 1 (external, not submodules; supplied
  by modules/spack).
- Sub-cluster **"submodules"** (white fill): cylinders `FMS install`, `pFUnit install`,
  `AMReX install`, `TIM install` (`#bcd4ec`). These are the deps turbo-stack can build from its
  submodules (AMReX/pFUnit = Tier 1.5, FMS/TIM = Tier 2).
- `stage1_outputs` box (green `#c8e6c9`):
  `"Expected environment  (shell state)\nPATH · CC, CXX, FC  ·  CMAKE_PREFIX_PATH  ·  PFUNIT_DIR"`.
- Edges into `stage1_outputs` (each via `xlabel=`):
  - every install cylinder → outputs, `"CMAKE_PREFIX_PATH"` (pFUnit's is
    `"CMAKE_PREFIX_PATH and PFUNIT_DIR"`).
  - `Compilers` → outputs `"CC, CXX, FC"`; `CMake` → outputs `"PATH"`; `make or ninja` → outputs `"PATH"`.

### Stage 2 — "build_turbo_stack.sh" cluster
- `cmake configure` box `"-DMOM6_INFRA=TIM|FMS2 (default TIM)"` (`#a3e0a3`).
- `cmake --build` box `"(reads CMAKE_BUILD_PARALLEL_LEVEL)"` (`#a3e0a3`).
- `ctest` ellipse `"pFUnit unit tests (opt-in: --tests / TURBO_BUILD_UNIT_TESTS=ON)"` (`#52c452`).
- Sub-cluster **"turbo stack build output"** (white fill): cylinder `MOM6 install` → box
  `turbo-stack unit tests`.
- Edges: `cmake configure → cmake --build`; `cmake --build → MOM6 install` (with `lhead` into the
  output sub-cluster); `cmake --build → ctest` `xlabel="--tests"`; `turbo-stack unit tests → ctest`.

### The hand-off (central message)
- Bold edge (`penwidth=2`) `stage1_outputs → cmake configure`, `lhead=cluster_stage2`, `xlabel` =
  "Shell state crosses the stage boundary — build_turbo_stack.sh has no knowledge of the Stage-1
  environment setup beyond what that shell state carries."

### Constraints / gotchas
- The two stage clusters must be clearly separated — distinct fills and the bold cross-boundary edge.
- Edge text uses `xlabel=`, never `label=`.
- `lhead=cluster_*` is used ONLY for the two cross-cluster hand-off edges above; every other edge
  points at a named node.
