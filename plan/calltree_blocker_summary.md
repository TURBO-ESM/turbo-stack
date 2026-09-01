# Calltree conversion plans — blocker summary

Consolidated status across every `convert_calltree` plan checked in this session, so the current
blocker set doesn't have to be re-derived from scratch each time. Full detail, evidence, and
citations live in the individual plan files under `.claude/calltree-plans/` — this document is a
pointer-heavy index, not a replacement for them.

**Legend:** ✅ resolved/confirmed clean · 🔴 blocking (external dependency) · 🟡 not blocking, but
real unfinished work · ⚠️ overrides everything else below it for that tree

Verified against source directly in this session (not just trusted from the plan docs) — see each
plan file's own "Blockers, current as of this check" section for the exact grep/read evidence.

---

## `btstep` (barotropic solver — `btstep`/`btcalc`/`bt_mass_source`/`set_dtbt`)
Detail: [`btstep.md`](../.claude/calltree-plans/btstep.md)

- ✅ Resolved: `BT_cont_type` wholesale conversion — verified done across all 5 files.
- 🔴 Blocking: combined shared-infrastructure PR not landed (needs `ADp`, `OBC`).
- 🔴 Blocking: `BTCL_u`/`BTCL_v` array-of-struct decomposition — no sibling skill exists, affects
  11 subroutines.
- 🟡 Narrower blocker: optional-struct-dummy mechanism unresolved, but only affects `set_dtbt`'s
  `BT_cont` param.
- Size: 4465 lines (own tree) / 4947 (all four entry points) — largest of every tree checked.

## `CorAdCalc` (Coriolis/advection)
Detail: [`CorAdCalc.md`](../.claude/calltree-plans/CorAdCalc.md)

- 🔴 Blocking: combined shared-infrastructure PR not landed (needs `OBC`, `AD`, `Waves`, `pbv`).
- 🔴 Blocking, separate: `Waves`'s optional-struct status unresolved.
- 🟡 Not blocking, unfinished: setup→per-scheme subroutine interface not fully enumerated;
  `gradKE` split-or-not not confirmed.
- Downstream, not Phase-2: WENO/UP3 fixed-size-array Phase-3 bridging treatment undecided.

## `vertvisc_family` (`vertvisc`/`vertvisc_coef`/`vertvisc_remnant`)
Detail: [`vertvisc_family.md`](../.claude/calltree-plans/vertvisc_family.md)

- 🔴 Blocking: combined shared-infrastructure PR not landed — needs the *largest* set of any tree:
  `visc`, `tv`, `OBC`, `ADp`, `forces`, `VarMix`, `Waves` (7 types).
- 🔴 Blocking, separate: `Waves`'s optional-struct status — affects `vertvisc` only, not the other
  two entry points.
- 🟡 Not blocking, unfinished: `vertvisc_CS` bundle field list explicitly partial.
- ✅ Resolved this session: `forces%frac_shelf_u`/`v` confirmed `pointer`+`associated()`-guarded
  (was an open question).

## `horizontal_viscosity`
Detail: [`horizontal_viscosity.md`](../.claude/calltree-plans/horizontal_viscosity.md)

- ⚠️ **Overrides everything below**: Phase 1 is stale and needs to be redone — 5 real descendant
  subroutines were never surveyed (`hor_visc_GME_setup`/`Leith_grad`/`Leithy_Ah`/`backscatter_h`/
  `backscatter_q`), the external signature is missing a parameter (`nkblock`), the entry-point
  line range is wrong.
- 🔴 Blocking (known part of the tree): combined shared-infrastructure PR not landed (needs `ADp`,
  `OBC`, `VarMix`, `MEKE`).
- 🔴 Blocking (known part of the tree): optional-struct-dummy gap *originated here* — largest
  instance of any tree, 5 affected dummies (`BT`/`TD`/`ADp`/`STOCH` + `OBC` combo).
- Note: `STOCH`'s shadow is tree-scoped, *not* blocked by the combined PR — built locally.
- Unknown: what the 5 newly-found subroutines depend on — genuinely unsurveyed until Phase 1 is
  redone.

## `PressureForce`
Detail: [`PressureForce.md`](../.claude/calltree-plans/PressureForce.md)

- ✅ Not blocked by EOS — deliberately left external/unblocked permanently, doesn't wait on
  `EOS_bridge_design.md`'s implementation.
- 🔴 Blocking: combined shared-infrastructure PR not landed (needs `tv`, `ADp` — genuinely
  dereferenced, not opaque, here).
- ✅ Does *not* have the optional-struct-dummy gap the other trees hit.
- Minor, non-blocking: `PressureForce_CS`'s own field list not separately surveyed.

## `advect_tracer` (`advect_tracer`/`advect_x`/`advect_y`)
Detail: [`advect_tracer.md`](../.claude/calltree-plans/advect_tracer.md)

- ✅ Doc verified accurate — no staleness found, only minor line-drift (-7 lines).
- 🔴 Blocking: combined shared-infrastructure PR not landed — needs `OBC`. Smallest footprint of
  any tree checked (just the one type).
- 🔴 Blocking, separate: `tracer_registry_type`/`tracer_type` (`Reg`/`Tr`) is an array-of-struct
  needing hand-authored per-field decomposition — same gap as `btstep`'s `BTCL_u`/`BTCL_v`, first
  appearance of this specific type.
- ✅ No optional-struct-dummy gap flagged.
- Verified, not a blocker but relevant to testing: its `create_group_pass`/`do_group_pass` calls
  are genuinely exercised in `benchmark`, not in `double_gyre` — and if ungrouped for testing, the
  replacement calls must sit at the `do_group_pass` position, not the registration points.
- Size: 1178 lines total / 861 code — smallest of every tree checked.

## `EOS_bridge_design.md` (not a calltree entry point — the blocking-prerequisite design `PressureForce` and future EOS-touching trees depend on)
Detail: [`EOS_bridge_design.md`](../.claude/calltree-plans/EOS_bridge_design.md)

- ✅ Design fully decided: scope (8 forms, TEOS10 deferred), dispatch mechanism (switch),
  three-tier verification policy, capture-fixture sourcing, per-form file layout, per-call-tree
  AMReX-mode scoping, `calculate_TFreeze` correctly split out.
- 🟡 Not blocking, real work not started: actually porting the 8 forms' kernels to C++ — only
  `buggy_Wright_EOS` has a concrete near-term plan.
- 🟡 Not blocking, unresolved: landing sequencing for the two shared-infrastructure pieces
  (marshalling helper, tree-scoping mechanism).
- 🟡 Deferred, not urgent: `calculate_TFreeze`'s own per-rank shim design — no currently-scoped
  tree calls it.
- **Important: EOS itself blocks nothing.** Every EOS-touching tree's "leave alone, view-marshal"
  classification is permanent and works today regardless of this design's implementation status.

## Shared infrastructure (`shared_type_unions.md`'s combined PR — what every 🔴 above is actually waiting on)
Detail: [`shared_type_unions.md`](../.claude/calltree-plans/shared_type_unions.md)

- ✅ Resolved: Stage 1, `BT_cont_type` wholesale conversion.
- 🔴 Not yet done: Stages 2-12 — verified repo-wide, no shadow container type exists anywhere for
  `OBC`/`ADp`/`tv`/`forces`/`vertvisc_type`/`pbv`/`VarMix`/`Waves`/`MEKE`, and `tracer_type`'s
  decomposition hasn't been built.
- 🟡 One genuine internal ordering dependency (the only one in the file): Stage 2
  (`tracer_registry_type`/`tracer_type`) must land before Stage 3 (`OBC`), since
  `OBC%segment(:)%tr_Reg` nests it.
- 🟡 Two stages deliberately isolated with their own unresolved sub-problems: `Waves` (Stage 10,
  optional-struct-dummy design question) and `MEKE` (Stage 11, field-list reconciliation between
  `tracer_hordiff` and `horizontal_viscosity`).
- **Prioritization signal:** `ADp`/`tv` (Stages 4-5) are ordered early specifically because
  `PressureForce` — the doc's own "recommended next entry-point plan to execute" — needs only
  those two.
- **Practical catch:** the PR lands as one combined merge (Stage 12 is whole-package verification
  before the final commit) — no tree can consume a partially-finished PR, so every tree above
  stays blocked until all 12 stages land together.
- Scope is broader than the six trees above: also covers `set_viscous_BBL`/`set_viscous_ML` and
  `tracer_hordiff`, not yet given a dedicated blocker-check pass.

---

## The one-sentence version

Every tree checked except `EOS_bridge_design.md` is blocked on the same combined
shared-infrastructure PR landing as a whole; `btstep` and `advect_tracer` additionally need a
second, structurally distinct fix (array-of-struct decomposition) that landing the PR won't
provide; and `horizontal_viscosity` needs its own Phase 1 redone before its blocker list can even
be considered complete.
