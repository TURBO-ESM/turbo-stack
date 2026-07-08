# Dependency DAG — recreation prompt

Use the prompt below to regenerate `cmake_dependency_dag.dot` (and the PNG) with Claude Code after the dependency structure changes. The prompt describes the *relationships*, not the exact dot syntax, so it stays valid as targets are added or renamed.

---

## Prompt

Generate a Graphviz dot file at `docs/cmake_dependency_dag.dot` showing the build-time dependencies of the turbo-stack project. Render it to `docs/cmake_dependency_dag.png` with `dot -Tpng`.

### Layout rules
- `rankdir=TB` — high-level consumers at the top, low-level libraries at the bottom.
- `splines=ortho`, `compound=true`.
- Group nodes into labelled clusters by origin (see below).
- Use dashed edges for conditional / hot-swap relationships.
- **Use `xlabel=` (not `label=`) for any edge that carries a text label.** Graphviz's orthogonal router does not support inline edge labels; `xlabel` places the text externally and avoids the layout warning.
- Diamond nodes for INTERFACE adapter targets (backend-agnostic wrappers). The diamond shape alone
  conveys "INTERFACE" — label such nodes with just the target name (e.g. `TURBO::infra_r8`), no extra
  annotation text in the label.
- Ellipse nodes for executables and test suites.
- **Never use `lhead=cluster_*` on edges.** All arrows must point to specific named nodes, even when the target lives inside a cluster. Using `lhead` collapses multiple distinct edges into a single arrow at the cluster boundary, hiding which library is actually being linked.

### Clusters and their nodes

**External** — cluster fill `#f5f5dc`; dependency nodes yellow (`#fffacd`):
- `HDF5`
- `NetCDF::NetCDF_C` → depends on HDF5
- `NetCDF::NetCDF_Fortran` → depends on NetCDF_C
- `MPI::MPI_Fortran`
- `AMReX`
- `PFUNIT::pfunit`

**FMS2 (FMS_ROOT)** — blue fill (`#dce8f5`):
- `FMS::fms_r8` → NetCDF_C, NetCDF_Fortran, MPI

**TIM repo (TIM_ROOT)** — orange fill (`#fde8d8`):
- `TIM::tim_r8` → AMReX, NetCDF_C, NetCDF_Fortran, MPI

**TURBO::infra_r8** — diamond, green fill (`#c8e6c9`):
- Hot-swap wrapper: dashed edge to `FMS::fms_r8` labelled `MOM6_INFRA=FMS2`
- Dashed edge to `TIM::tim_r8` labelled `MOM6_INFRA=TIM`
- The backend is selected by the `MOM6_INFRA` CMake cache variable (defined in
  MOM6's `cmake/MOM6Options.cmake`; the turbo-stack build scripts default to TIM
  and always pass `-DMOM6_INFRA`, set via `--infra`). Only one of the two dashed
  edges is live in any given build.
- Solid edge to `NetCDF::NetCDF_C` (always present). turbo-stack attaches it
  explicitly so `libnetcdf.so`'s absolute path lands on every link line that uses
  TURBO::infra_r8 — FMS/TIM only carry NetCDF_Fortran, whose bare `-lnetcdf` flag
  fails to resolve on split lib/lib64 installs (e.g. NCAR Derecho's module).

**turbo-stack marbl_build/ (submodules/MARBL)** — purple fill (`#ede0f5`):
- `MARBL::marbl` — pure Fortran library; no cmake-level external dependencies

**MOM6 repo (MOM6_ROOT)** — green fill (`#d8f0d8`):
MOM6 source lives in the external `MOM6_ROOT` directory (not an in-tree submodule);
turbo-stack includes it via `add_subdirectory("${MOM6_SOURCE_DIR}" mom6_build)`.
MOM6's CMake builds five Fortran libraries plus the executable — there are **no**
`framework_base`, `grid`, or `io` sub-libraries. `framework` is now a single
library (model-agnostic code that depends only on `infra`); the former `grid`/`io`
sources that depend on model modules compile straight into `ocean`.
- `MOM6::CVMix` — pure Fortran, no link deps
- `MOM6::GSW` → NetCDF_C, NetCDF_Fortran (private)
- `MOM6::infra` → TURBO::infra_r8, MPI, NetCDF_Fortran (all public)
- `MOM6::framework` → infra (public)
- `MOM6::ocean` → framework, CVMix, GSW, MARBL::marbl (all public)  (darker green `#52c452`)
- `MOM6 (executable)` ellipse → ocean (private)  (dark green `#2e8b57`, white font)

**turbo-stack tests/** — tan fill (`#f0e8d8`):
(turbo-stack builds `tests/` when `TURBO_BUILD_UNIT_TESTS=ON` — opt-in via the
orchestrators' `--tests` flag — wired in by the root CMakeLists; `tests-legacy/`
is a dead tree kept for reference and is not added as a subdirectory — ignore it.)
- `pFUnit unit tests` ellipse, labelled `(executable)` (like `MOM6 (executable)`) → MOM6::framework, MOM6::infra, TURBO::infra_r8, PFUNIT::pfunit
  - The node carries `(executable)` rather than a test count, so it needs no edit
    when tests are added or removed.
  - Three suites under `tests/interface/`, each a set of pFUnit test executables:
    - `MOM_coms_infra/` (link MOM6::infra)
    - `MOM_coms_helpers/` (link MOM6::infra)
    - `MOM_domain_infra/` (one test links MOM6::infra, one links MOM6::framework)
  - All tests always link TURBO::infra_r8 (via the `add_mom_test` CMake macro).

### Direct link structure for tests
Every test executable links `TURBO::infra_r8` directly (via the `add_mom_test` CMake macro).
Most tests also link `MOM6::infra`; one test (`test_create_mom_domain`) links `MOM6::framework`.
Arrows point to the specific targets, not the cluster boundary.
