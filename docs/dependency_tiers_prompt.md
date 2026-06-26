# Dependency tiers (the build contract) — recreation prompt

Use the prompt below to regenerate `dependency_tiers.dot` (and the PNG) with Claude Code when
turbo-stack's dependency *policy* changes (a dep added/removed, or a dep's tier changes). The
prompt describes the *classification*, not exact dot syntax, so it stays valid as members move.

Render with: `dot -Tpng -o docs/dependency_tiers.png docs/dependency_tiers.dot`.

This figure is the **contract companion** to `cmake_dependency_dag.png`. The DAG shows build-time *link*
relationships (what links what); this figure shows turbo-stack's *build policy* toward each
dependency — what it never builds, what it optionally builds, what it always builds. Same nodes,
grouped differently.

---

## Prompt

Generate a Graphviz dot file at `docs/dependency_tiers.dot` classifying every turbo-stack
dependency by turbo-stack's BUILD POLICY (not by who owns or co-develops it). Render to
`docs/dependency_tiers.png` with `dot -Tpng`.

### Layout rules
- `rankdir=TB`, `splines=ortho`, `compound=true`, `newrank=true`.
- Each tier is ONE horizontal band: put all of a tier's nodes at `{rank=same; ...}` inside its
  cluster.
- Stack the bands top→bottom with ONE invisible edge per boundary (consumers on top, prerequisites
  at the bottom): Tier 3 → Tier 2 → Tier 1. Anchor each invisible edge on the RIGHTMOST node of
  each tier so the spine stays a straight vertical line (e.g. `t3_mom6 → t2_fms → t1_hdf5`).
- This layout renders each `rank=same` band RIGHT-TO-LEFT relative to declaration order, so declare
  a band's nodes in REVERSE of the desired left-to-right order (and list them in the same reversed
  order inside `{rank=same; ...}`).
- Each hot-swap (`*_ROOT`) target must be the RIGHTMOST node in its tier, so its dashed line enters
  from the east side and stays in the clear right margin instead of crossing the bold cluster-label
  text. Hence MOM6 is rightmost in Tier 3 and FMS is rightmost in Tier 2.
- Keep boxes compact: wrap any long label across lines with `\n` (e.g. `C/C++/Fortran\ncompilers`,
  `NetCDF\n(C+Fortran)`), and wrap each multi-clause cluster label onto two lines.
- Edge text uses `xlabel=`, never `label=` (orthogonal router).
- Hot-swap annotation edges set `constraint=false` (so they don't perturb the banded layout) and
  `penwidth=1.4` (so the dashed lines read clearly where they cross a cluster background).

### Tiers (clusters), policy label, members, colors
The labels classify the BUILD axis (never built / can-build-or-prebuilt / always built):
- **Tier 3 — turbo-stack ALWAYS compiles it inline** (`add_subdirectory`); no prebuilt-library
  option — only the SOURCE can be swapped.  Cluster `#d8f0d8`. Members (left→right):
  `MARBL` (`#d8b4fe`), `turbo-stack` (`#c8e6c9`), `MOM6` (`#90ee90`) — MOM6 rightmost so its
  `MOM6_ROOT` hot-swap line enters cleanly from the east.
- **Tier 2 — turbo-stack CAN build it** (submodule or `*_ROOT` SOURCE) OR you supply a PREBUILT
  install on `CMAKE_PREFIX_PATH` (`find_package`).  Cluster `#fdeede`. Members (left→right):
  `pFUnit` (`#fffacd`), `AMReX` (`#fffacd`), `TIM` (`#ffcc99`), `FMS` (`#add8e6`) — FMS rightmost
  (for its `FMS_ROOT` line). In practice FMS/TIM are built from submodule; AMReX/pFUnit come
  prebuilt from the Tier-1 provider (spack).
- **Tier 1 — turbo-stack NEVER builds these; you supply them PREBUILT** (modules / spack / OS
  packages). Cluster `#f5f5dc`, nodes `#fffacd`. Members, left→right: C/C++/Fortran compilers, MPI,
  CMake>=3.24, make/ninja, NetCDF (C+Fortran), HDF5.

### Deliberately excluded (do NOT re-add)
- **FFTW** — not a turbo-stack requirement. It is only a transitive artifact of how spack
  concretizes AMReX (AMReX's optional FFT module); the from-source AMReX build (`turbo_build_amrex`)
  does not enable it (`-DAMReX_FFT` is never passed), and no turbo-stack or TIM source calls it. It
  belongs under AMReX (Tier 2), not as a Tier-1 prerequisite.
- **Tier 0 (legacy / dev tooling)** — `CESM_share` (referenced only by the retiring `build.sh` and
  `dev-utils/gen_parse_tree.sh`) and `gcovlens` (standalone coverage tooling, never a dependency).
  Neither is in the new CMake build graph, so the figure shows only the live contract (Tiers 1–3).

### Hot-swap cross-cut (NOT a tier)
A sticky note (`shape=note`, `#fff2cc`) labelled "*_ROOT = bring your own SOURCE (turbo-stack still
builds it; co-developed repos) — default = pinned submodule", with dashed brown edges
(`color="#a06000"`, `penwidth=1.4`, `arrowhead=odot`, `constraint=false`) to the three co-developed
repos, xlabelled `FMS_ROOT`, `TIM_ROOT`, `MOM6_ROOT`.  They span Tier 2 (FMS, TIM) and Tier 3 (MOM6)
on purpose.  This is a SOURCE override (turbo-stack still builds it) — distinct from Tier 2's "supply
a PREBUILT install on CMAKE_PREFIX_PATH".  MOM6 and FMS sit at the right edge of their tiers so these
lines enter from the east and stay in the clear right margin; TIM is interior, so its line necessarily
runs through Tier 2's right side (kept off the label text by the trimmed Tier-2 label).

### Narrative the figure must land
- Tier is set by turbo-stack's build policy, not authorship: TIM is ours but Tier 2 (can be built or
  supplied prebuilt); MOM6 is ours but Tier 3 (always compiled inline).
- Two orthogonal axes: the BUILD axis above (never / can-build-or-prebuilt / always), and the SOURCE
  axis — `*_ROOT` swaps the source tree of a co-developed repo (FMS/TIM/MOM6) while turbo-stack still
  builds it.  Don't conflate "bring your own SOURCE" (`*_ROOT`) with "bring your own PREBUILT library"
  (`CMAKE_PREFIX_PATH`, Tier 2 only).
