# Dependency DAG — recreation prompt

Use the prompt below to regenerate `dependency_dag.dot` (and the PNG) with Claude Code after the dependency structure changes. The prompt describes the *relationships*, not the exact dot syntax, so it stays valid as targets are added or renamed.

---

## Prompt

Generate a Graphviz dot file at `docs/dependency_dag.dot` showing the build-time dependencies of the turbo-stack project. Render it to `docs/dependency_dag.png` with `dot -Tpng`.

### Layout rules
- `rankdir=TB` — high-level consumers at the top, low-level libraries at the bottom.
- `splines=ortho`, `compound=true`.
- Group nodes into labelled clusters by origin (see below).
- Use dashed edges for conditional / hot-swap relationships.
- Diamond nodes for INTERFACE adapter targets (backend-agnostic wrappers).
- Ellipse nodes for executables and test suites.
- **Never use `lhead=cluster_*` on edges.** All arrows must point to specific named nodes, even when the target lives inside a cluster. Using `lhead` collapses multiple distinct edges into a single arrow at the cluster boundary, hiding which library is actually being linked.

### Clusters and their nodes

**External (Spack / system packages)** — yellow fill (`#fffacd`):
- `HDF5`
- `NetCDF::NetCDF_C` → depends on HDF5
- `NetCDF::NetCDF_Fortran` → depends on NetCDF_C
- `MPI::MPI_Fortran`
- `AMReX (+fortran)`
- `PFUNIT::pfunit`

**FMS2 (Spack install or submodules/infra/FMS2)** — blue fill (`#dce8f5`):
- `FMS::fms_r8` → NetCDF_C, NetCDF_Fortran, MPI

**TIM repo (TIM_ROOT)** — orange fill (`#fde8d8`):
- `TIM::tim_r8` → AMReX, NetCDF_C, NetCDF_Fortran, MPI

**TURBO::infra_r8 (INTERFACE — turbo-stack CMake)** — diamond, green fill (`#c8e6c9`):
- Hot-swap wrapper: dashed edge to `FMS::fms_r8` labelled `TURBO_INFRA=FMS2`
- Dashed edge to `TIM::tim_r8` labelled `TURBO_INFRA=TIM`

**turbo-stack marbl_build/ (submodules/MARBL)** — purple fill (`#ede0f5`):
- `MOM6::MARBL`

**MOM6 repo (MOM6_ROOT)** — green fill (`#d8f0d8`):
- `MOM6::CVMix`
- `MOM6::GSW` → NetCDF_C, NetCDF_Fortran
- `MOM6::framework_base`
- `MOM6::infra` → TURBO::infra_r8, MPI, NetCDF_Fortran, framework_base (private)
- `MOM6::framework` → infra, framework_base
- `MOM6::grid` → framework
- `MOM6::io` → grid
- `MOM6::ocean` → io, grid, CVMix, GSW, MOM6::MARBL  (darker green `#52c452`)
- `MOM6 (executable)` ellipse → ocean  (dark green `#2e8b57`, white font)

**turbo-stack tests/** — tan fill (`#f0e8d8`):
- `pFUnit unit tests (40 tests)` ellipse → MOM6::framework, MOM6::infra, TURBO::infra_r8, PFUNIT::pfunit

### Direct link structure for tests
Every test executable links `TURBO::infra_r8` directly (via the `add_mom_test` CMake macro).
Most tests also link `MOM6::infra`; one test (`test_create_mom_domain`) links `MOM6::framework`.
Arrows point to the specific targets, not the cluster boundary.
