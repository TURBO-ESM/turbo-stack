# Dependency layers (the build contract) — recreation prompt

Use the prompt below to regenerate `dependency_layers.dot` (and the PNG) with Claude Code when
turbo-stack's dependency *policy* changes (a dep added/removed, or a dep's layer changes). The
prompt describes the *classification*, not exact dot syntax, so it stays valid as members move.

Render with: `dot -Tpng -o docs/dependency_layers.png docs/dependency_layers.dot`.

This figure is the **contract companion** to `cmake_dependency_dag.png`. The DAG shows build-time *link*
relationships (what links what); this figure shows turbo-stack's *build policy* toward each
dependency — what it never builds, what it optionally builds, what it always builds. Same nodes,
grouped differently.

---

## Prompt

Generate a Graphviz dot file at `docs/dependency_layers.dot` classifying every turbo-stack
dependency by turbo-stack's BUILD POLICY (not by who owns or co-develops it). Render to
`docs/dependency_layers.png` with `dot -Tpng`.

### Layout rules
- `rankdir=TB`, `splines=ortho`, `compound=true`, `newrank=true`.
- Each layer is ONE horizontal band: put all of a layer's nodes at `{rank=same; ...}` inside its
  cluster.
- Stack the bands top→bottom with ONE invisible edge per boundary (consumers on top, prerequisites
  at the bottom): Layer 4 → Layer 3 → Layer 2 → Layer 1. Anchor each invisible edge on the RIGHTMOST
  node of each layer and give it a high `weight` (e.g. `weight=10`) so those anchor nodes hold a
  straight vertical column and the bands right-align (overlap) instead of staggering — that stagger is
  what makes the figure needlessly wide (e.g. `l4_mom6 → l3_fms → l2_amrex → l1_hdf5`).
- This layout renders each `rank=same` band RIGHT-TO-LEFT relative to declaration order, so declare
  a band's nodes in REVERSE of the desired left-to-right order (and list them in the same reversed
  order inside `{rank=same; ...}`).
- Each hot-swap (`*_ROOT`) target must be the RIGHTMOST node in its layer, so its dashed line enters
  from the east side and stays in the clear right margin instead of crossing the bold cluster-label
  text. Hence MOM6 is rightmost in Layer 4 and FMS is rightmost in Layer 3.
- Keep node boxes compact: wrap any long node label across lines with `\n` (e.g. `C/C++/Fortran\ncompilers`,
  `NetCDF\n(C+Fortran)`). Each cluster label has three blocks — a title, a `Source:` sentence, and a
  `Build:` sentence — separated by a blank line (`\n\n`). Hard-wrap with `\n` to ≲60 characters per
  line and keep the `Source:` and `Build:` blocks to at most two lines each; a long unwrapped label
  line is the main thing that makes a band (and the whole figure) needlessly wide.
- Edge text uses `xlabel=`, never `label=` (orthogonal router).
- Hot-swap annotation edges set `constraint=false` (so they don't perturb the banded layout) and
  `penwidth=1.4` (so the dashed lines read clearly where they cross a cluster background).

### Layers (clusters), members, colors
Each cluster label has three lines: a **title** (what kind of dependency), a **Source:** line (how
turbo-stack obtains the source), and a **Build:** line (turbo-stack's build policy). Layers are ordered
top→bottom by how much turbo-stack does for you, most on top. The build axis has three policies
(never built / can-build-or-prebuilt / always built); the can-build-or-prebuilt policy is split into
two layers by source type (co-developed vs external submodule):
- **Layer 4 — Code turbo-stack builds.**  Source: turbo-stack always has its own source; MARBL source
  always via submodule; MOM6 source via submodule or override.  Build: ALWAYS compiled inline
  (`add_subdirectory`) — no prebuilt-library option, only the SOURCE can be swapped.  Cluster
  `#d8f0d8`. Members (left→right): `MARBL` (`#d8b4fe`), `turbo-stack` (`#c8e6c9`), `MOM6` (`#90ee90`)
  — MOM6 rightmost so its `MOM6_ROOT` hot-swap line enters cleanly from the east.
- **Layer 3 — Internal (we develop) upstream libraries.**  Source: turbo-stack CAN get it via
  submodule, with the option to override and bring your own development source branch or fork
  (`*_ROOT`).  Build: turbo-stack CAN build it OR you supply a PREBUILT install on `CMAKE_PREFIX_PATH`
  (`find_package`).  Cluster `#fdeede`. Members (left→right): `protoMOMxx` (`#ffe0b2`), `TIM`
  (`#ffcc99`), `FMS` (`#add8e6`) — FMS rightmost (for its `FMS_ROOT` line). One invisible spacer node
  (`style=invis`) pads the band's left half so the members stay right-of-centre and the `TIM_ROOT`
  and `PROTOMOMXX_ROOT` hot-swap labels clear the cluster title. In practice FMS/TIM/protoMOMxx are
  always built from submodule (the co-developed TURBO-ESM repos, which is why they — not
  AMReX/pFUnit — are drawn with `*_ROOT` hot-swap lines). protoMOMxx is built only for the TIM
  backend, after TIM: it provides `protoMOMxx::mom_bridge`, the C++ side of the AMReX kernels MOM6
  calls under `-D_TIM`, and links TIM. Only its kernel and bridge targets are built
  (`PROTOMOM_KERNELS_ONLY`), so it is a library dependency like TIM, not a Layer-4 model.
- **Layer 2 — External upstream libraries that are submodules.**  Source: turbo-stack CAN get it via
  submodule; `AMREX_ROOT` / `PFUNIT_ROOT` swap that source wherever a builder builds them, but these
  are not co-developed, so draw no hot-swap line to them.  Build: turbo-stack CAN build the
  submodule source OR you provide a PREBUILT install on `CMAKE_PREFIX_PATH` (`find_package`).  Cluster
  `#f5f5dc`, nodes `#fffacd`. Members (left→right): `pFUnit`, `AMReX`.  In practice they come prebuilt
  from the Layer-1 provider where available (e.g. spack) and are built from submodule where it is not
  (e.g. Derecho).  Same build *policy* as Layer 3, split out to separate external submodules from the
  co-developed repos.
- **Layer 1 — External tools and upstream libraries that are not submodules.**  Source: turbo-stack
  NEVER gets it for you.  Build: turbo-stack NEVER builds these; you supply them PREBUILT (modules /
  OS packages / spack / hand-compiled / etc.).  Cluster `#f5f5dc`, nodes `#fffacd`. Members
  (left→right): C/C++/Fortran compilers, MPI, CMake>=3.24, make/ninja, NetCDF (C+Fortran), HDF5.

### Deliberately excluded (do NOT re-add)
- **FFTW** — not a turbo-stack requirement. It is only a transitive artifact of how spack
  concretizes AMReX (AMReX's optional FFT module); the from-source AMReX build (`turbo_build_amrex`)
  does not enable it (`-DAMReX_FFT` is never passed), and no turbo-stack or TIM source calls it. It
  belongs under AMReX (Layer 2), not as a Layer-1 prerequisite.
- **Layer 0 (legacy / dev tooling)** — `CESM_share` (referenced only by the retiring `build.sh` and
  `dev-utils/gen_parse_tree.sh`) and `gcovlens` (standalone coverage tooling, never a dependency).
  Neither is in the new CMake build graph, so the figure shows only the live contract (Layers 1, 2,
  3, 4).

### Hot-swap cross-cut (NOT a layer)
A sticky note (`shape=note`, `#fff2cc`) labelled "*_ROOT = bring your own SOURCE (turbo-stack still
builds it; co-developed repos) — default = pinned submodule", with dashed brown edges
(`color="#a06000"`, `penwidth=1.4`, `arrowhead=odot`, `constraint=false`) to the four co-developed
repos, xlabelled `FMS_ROOT`, `TIM_ROOT`, `PROTOMOMXX_ROOT`, `MOM6_ROOT`.  They span Layer 3 (FMS, TIM,
protoMOMxx) and Layer 4 (MOM6) on purpose.  This is a SOURCE override (turbo-stack still builds it) —
distinct from the Layer 2 / Layer 3 option to "supply a PREBUILT install on CMAKE_PREFIX_PATH".  MOM6
and FMS sit at the right edge of their layers so these lines enter from the east and stay in the clear
right margin; TIM and protoMOMxx are interior, so their lines necessarily run through Layer 3's right
side (kept off the label text by the trimmed Layer-3 label).

### Narrative the figure must land
- Layer is set by turbo-stack's build policy, not authorship: TIM is ours but Layer 3 (can be built or
  supplied prebuilt); MOM6 is ours but Layer 4 (always compiled inline).
- Layer 3 and Layer 2 share the SAME build policy (can-build-or-prebuilt); they are split to separate
  the co-developed TURBO-ESM repos with a `*_ROOT` source swap (FMS/TIM/protoMOMxx, Layer 3) from the
  external third-party submodules with no source swap (AMReX/pFUnit, Layer 2).
- Two orthogonal axes: the BUILD axis above (never / can-build-or-prebuilt / always), and the SOURCE
  axis — `*_ROOT` swaps the source tree of a co-developed repo (FMS/TIM/protoMOMxx/MOM6) while turbo-stack still
  builds it.  Don't conflate "bring your own SOURCE" (`*_ROOT`) with "bring your own PREBUILT library"
  (`CMAKE_PREFIX_PATH` — available for Layer 2 and Layer 3).
