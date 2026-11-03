# TURBO Stack changelog

Changes made across turbo-stack and its submodules, newest first. Planned work
lives in `BACKLOG.md`. Each entry names the backlog item it came from (if any),
the repository and files changed, and whether the change is committed.

Format: one `##` section per date, one `###` entry per change, with these
fields: **Backlog item**, **Repository**, **Files**, **Committed**, then a short
description.

---

## 2026-11-03

### Scratch buffers in generated kernels must use `The_Async_Arena()`

- **Backlog item:** TB-007 (step 3; the continuity fix itself is still open)
- **Repository:** protoMOMxx
- **Files:** `.claude/skills/generate_amrex_code/lessons.md`,
  `.claude/skills/generate_amrex_code/SKILL.md`
- **Committed:** no

The `generate_amrex_code` skill now requires every scratch
`FArrayBox`/`IArrayBox` allocated inside a kernel to pass
`amrex::The_Async_Arena()` explicitly.

- `lessons.md` §4: the scratch-buffer convention used to show
  `FArrayBox tmp_fab(box, ncomp)` (the default arena). It now shows the
  explicit async arena.
- `lessons.md` §7 #20 (new pitfall): explains the stream race with
  `The_Arena()`, why the single-stream bridge path and capture replay can't
  detect it, the cost, the reference ports (CorAdCalc, hor_visc,
  vert_friction) and the one that slipped (continuity). The bridge helper's
  `A4Box` buffers are out of scope.
- `SKILL.md` hard rules: a matching rule.

### "C order" / "Fortran↔C transpose" descriptions corrected in the skill

- **Backlog item:** TB-010 ("do soon" part; the `turbotmp_helper.hpp` comments
  and the code change are still open)
- **Repository:** protoMOMxx
- **Files:** `.claude/skills/generate_amrex_code/lessons.md`,
  `.claude/skills/generate_amrex_code/SKILL.md`
- **Committed:** no

`amrex::Array4` is column-major, the same as Fortran, so the bridge helper's
copy is an identity copy, not a transpose. The skill described it as a layout
conversion.

- `lessons.md`: the overview diagram, the §1 file table, §2 (`A4Box` buffers
  now described as having the same layout as Fortran, with the identity copy
  pointing to TB-010) and §2.2.
- `SKILL.md`: the skill description, and the hard rule now forbids adding or
  describing a transpose or "C order".

The skill version marker (`0.3.3`) was not bumped. It is shared with the
Fortran-side skill family, so a bump is a cross-repository decision.

### Design notes added

- **Backlog items:** TB-002, TB-008, TB-016
- **Repository:** protoMOMxx
- **Files:** `docs/design/northeast_stagger_views.md`,
  `docs/design/answers_not_structure.md`
- **Committed:** no

- `northeast_stagger_views.md`: calling the MOM kernels from the native driver
  through zero-copy northeast index views (TB-002).
- `answers_not_structure.md`: the principle that the MOM6 bridge path
  guarantees bit-for-bit answers, not identical structure. It covers what must
  be preserved, what may differ, how divergence is validated, and a checklist.
