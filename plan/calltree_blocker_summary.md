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
- Size: 1889 lines total / 1449 code (`CorAdCalc` + `gradKE` + `UP3_reconstruction`/
  `UP3_Koren_limiter_reconstruction` + the 22 `fac_fn`/`weno_*` procedures).

## `vertvisc_family` (`vertvisc`/`vertvisc_coef`/`vertvisc_remnant`)
Detail: [`vertvisc_family.md`](../.claude/calltree-plans/vertvisc_family.md)

- 🔴 Blocking: combined shared-infrastructure PR not landed — needs the *largest* set of any tree:
  `visc`, `tv`, `OBC`, `ADp`, `forces`, `VarMix`, `Waves` (7 types).
- 🔴 Blocking, separate: `Waves`'s optional-struct status — affects `vertvisc` only, not the other
  two entry points.
- 🟡 Not blocking, unfinished: `vertvisc_CS` bundle field list explicitly partial.
- ✅ Resolved this session: `forces%frac_shelf_u`/`v` confirmed `pointer`+`associated()`-guarded
  (was an open question).
- Size: 2824 lines total / 1988 code (`vertvisc`/`vertvisc_coef`/`vertvisc_remnant`/
  `vertvisc_limit_vel`/`find_coupling_coef`/`find_coupling_coef_k`/`find_coupling_coef_gl90`;
  excludes `write_u_accel`/`write_v_accel`/`find_ustar_mech_forcing`, which are external and
  excluded from bridging).

## `horizontal_viscosity`
Detail: [`horizontal_viscosity.md`](../.claude/calltree-plans/horizontal_viscosity.md)

- ✅ Phase 1 redone and verified — the previous stale survey has been replaced. Cross-checked
  independently (manual `call`-statement grep against current source) and it matches: the same 8
  descendants (`hor_visc_Leith_grad`/`backscatter_h`/`backscatter_q`/`GME_setup`/`smooth_GME`/
  `smooth_x9_uv`/`smooth_x9_h`/`Leithy_Ah`), `nkblock` now correctly in the external signature.
- **Real scope change, not just a citation fix: QG-Leith and ZB2020 are now explicitly out of
  scope** for this campaign (classified as out-of-tree calls) — the old plan had included both.
  `OBC`'s treatment simplified as a consequence: presence-checking only
  (`convert_present_to_associated`, bare-pointer form), no union shadow needed, since the subtree
  that used to dereference it (QG-Leith) is no longer in scope.
- 🔴 Blocking: combined shared-infrastructure PR not landed — needs `ADp`, `MEKE`, `VarMix` (down
  from `ADp`/`OBC`/`VarMix`/`MEKE`, one fewer type than the old plan, since `OBC` no longer needs
  a shadow).
- ✅ `STOCH` stays tree-scoped, not blocked by the combined PR — built locally.
- 🟡 The optional-struct-dummy gap has a *decided* answer for this tree specifically (Q1: shadow
  `ADp`/`STOCH` first via `create_shadow_container_type`, then apply
  `convert_present_to_associated`'s grouped-argument rule on top) — but this hasn't been confirmed
  against `shared_type_unions.md`'s own tracking note, which as of last check still lists the gap
  as unresolved campaign-wide. Don't treat it as closed for other trees until that's verified.
- Size, now confirmed rather than a lower bound: **2678 lines total, 2109 code** — matches what
  was computed as a partial lower bound before the redo, now the actual total since QG-Leith/
  ZB2020 are confirmed out of scope.

## `PressureForce`
Detail: [`PressureForce.md`](../.claude/calltree-plans/PressureForce.md)

- ✅ Not blocked by EOS — deliberately left external/unblocked permanently, doesn't wait on
  `EOS_bridge_design.md`'s implementation.
- 🔴 Blocking: combined shared-infrastructure PR not landed (needs `tv`, `ADp` — genuinely
  dereferenced, not opaque, here).
- ✅ Does *not* have the optional-struct-dummy gap the other trees hit.
- Minor, non-blocking: `PressureForce_CS`'s own field list not separately surveyed.
- Size: 2779 lines total / 1991 code (all six subroutines: `PressureForce_Mont_Bouss`/
  `_nonBouss`, `PressureForce_FV_Bouss`/`_nonBouss`, `Set_pbce_Bouss`/`_nonBouss`).

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

## `tracer_hordiff`
Detail: [`tracer_hordiff.md`](../.claude/calltree-plans/tracer_hordiff.md)

- ⚠️ Doc's line citations independently verified stale (spot-checked directly against source —
  not a script artifact): several descendants are far shorter than cited (e.g. `interface_scalar`
  is 39 lines against an implied ~134; `mark_unstable_cells` is 17 against an implied ~91). The
  *descendant list itself* wasn't re-verified for completeness the way `horizontal_viscosity`'s
  was — only the sizes were confirmed by finding real subroutine boundaries directly.
- 🔴 Blocking: combined shared-infrastructure PR not landed — needs **five** types: `MEKE`,
  `VarMix`, `visc` (`vertvisc_type`), `tv`, `Reg`/`Tr` (`tracer_registry_type`/`tracer_type`).
- 🔴 Blocking, separate: `Reg`/`Tr` array-of-struct decomposition — the *same* gap as
  `advect_tracer`'s, explicitly shared work per the doc ("combine with `advect_tracer`'s
  decomposition work — same type, same gap"), though this tree needs a larger field set.
- 🔴 Blocking, separate: `MEKE`'s field list has an unresolved cross-tree reconciliation specific
  to this pairing — `tracer_hordiff` needs `Kh`/`KhTr_fac`, but whether those overlap with
  `horizontal_viscosity`'s "most/all 15 fields" claim was never itemized (this is
  `shared_type_unions.md`'s own Stage 11 pre-check, still open).
- ✅ No optional-struct-dummy gap flagged.
- 🟡 Minor, non-blocking: `read_khdt_x`/`read_khdt_y` flagged as possibly dead code, needs
  confirming during Phase 2.
- Not a monolith needing a split-by-scheme decision (unlike `horizontal_viscosity`/`CorAdCalc`) —
  its three gated branches are already separate subroutines, closer in shape to
  `set_viscosity_family`.
- Size: 3645 lines total / 2839 code across 19 subroutines spanning three files
  (`MOM_tracer_hor_diff.F90`, `MOM_hor_bnd_diffusion.F90`, `MOM_neutral_diffusion.F90`) — second
  largest of every tree checked, after `btstep`.

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
- Scope is broader than the trees above: also covers `set_viscous_BBL`/`set_viscous_ML`, not yet
  given a dedicated blocker-check pass.

---

## The one-sentence version

Every tree checked except `EOS_bridge_design.md` is blocked on the same combined
shared-infrastructure PR landing as a whole; `btstep` and `advect_tracer` additionally need a
second, structurally distinct fix (array-of-struct decomposition) that landing the PR won't
provide; `horizontal_viscosity`'s Phase 1 has now been redone and verified, narrowing its own
combined-PR footprint by one type (`OBC` no longer needed) as a side effect of QG-Leith/ZB2020
being newly scoped out.
