# Calltree conversion plans — blocker summary (base: double_gyre_unsplit)

Consolidated status across every `convert_calltree` plan checked in this session, so the current
blocker set doesn't have to be re-derived from scratch each time. Full detail, evidence, and
citations live in the individual plan files under `.claude/calltree-plans/` — this document is a
pointer-heavy index, not a replacement for them.

**This file covers the base target only: `double_gyre_unsplit` (`SPLIT=False, USE_RK2=True`).**
For the additional work needed to extend this base to full `double_gyre` (`SPLIT=True`) support —
`btstep` in full, plus a validation-only caveat on `vertvisc_remnant` (documented here, grouped
with its `vertvisc_family` siblings, since it's a small ~106-line piece of that tree) — see
[`calltree_patch_summary_double_gyre.md`](calltree_patch_summary_double_gyre.md). That file is a thin pointer plus exactly
what's additional; it doesn't restate anything from here.

**A third tier builds on the `double_gyre` patch: `benchmark`** (adds real thermodynamics and
variable mixing on top of the same split dynamics — re-activates `tv` and `VarMix`, which stay
deferred at the two tiers below) — see
[`calltree_patch_summary_benchmark.md`](calltree_patch_summary_benchmark.md).

**Legend:** ✅ resolved/confirmed clean · 🔴 blocking (external dependency) · 🟡 not blocking, but
real unfinished work · ⚠️ overrides everything else below it for that tree

Verified against source directly in this session (not just trusted from the plan docs) — see each
plan file's own "Blockers, current as of this check" section for the exact grep/read evidence.

`double_gyre_unsplit`'s exercised code is a strict subset of `double_gyre`'s (confirmed via the
gcovlens coverage report and a source trace of `MOM.F90`'s `CS%split` branch,
`MOM.F90:1367-1425`), so everything built and validated against this base gets reused, unchanged,
once the patch file's additional work lands — nothing here needs to be redone for `double_gyre`.

**Action item, ahead of any of the below mattering in practice:** no `MOM_input`/`MOM_override`
for `double_gyre_unsplit` exists locally (only pre-generated coverage HTML does, at
`/Users/dennis/Desktop/Work/TURBO/code-coverage/double_gyre_unsplit/`) — source it from upstream
MOM6-examples (`ocean_only/double_gyre_unsplit`) or recover whatever inputs produced that coverage
run, before treating double_gyre_unsplit as an actual buildable/runnable base target.

---

## Deferred shared types: `OBC`/`ADp`/`tv`/`VarMix`/`Waves`/`pbv`/`MEKE` — the precedent applied to itself too

The runtime exercise audit (`shared_type_unions.md`) found `OBC`/`ADp`/`tv`/`VarMix`/`Waves`/
`pbv`/`MEKE` **all** PASSED-BUT-INERT under both double_gyre configs — every guard check is
correct, but no field carries real data under either config. `forces`/`vertvisc_type` (the only
two genuinely-live types) were already pulled into their own local shadows (see the per-type
table below). This session, the same "leave it raw, build a shadow only when a later need
justifies it" treatment `continuity()` already gave `OBC` historically was extended to **all
seven** inert types, `OBC` included — not just the other six. (Corrected in-session: an earlier
pass kept `OBC` active as the deferral's "anchor" rather than deferring it too — that was a
misreading; the whole point is `OBC` already sat in exactly this bucket via `continuity()`.)

**Net effect: the combined shared-infrastructure PR is now completely empty** (down from 9 types
→ 7 → 0 across two sessions). Every tree's remaining blocker list below reflects this.

| Tree | Combined-PR types before this session | Remaining now |
|---|---|---|
| `CorAdCalc` | `OBC`, `ADp`, `Waves`, `pbv` | **none** (`Waves`'s optional-struct blocker also moot) |
| `horizontal_viscosity` | `ADp`, `MEKE`, `VarMix` | **none** |
| `PressureForce` | `tv`, `ADp` | **none** |
| `vertvisc_family` | `tv`, `OBC`, `ADp`, `VarMix`, `Waves` | **none** (`Waves`'s optional-struct blocker also moot) |
| `set_viscosity_family` | `tv`, `OBC` | **none** |
| `tracer_hordiff` | `MEKE`, `VarMix`, `tv` | **none** (only the unrelated `Reg`/`Tr` gap remains) |
| `advect_tracer` | `OBC` | **none** from this mechanism (only the unrelated `Reg`/`Tr` gap remains) |

(`btstep` also needed `ADp`/`OBC` from this PR and is equally unblocked by the deferral — its full
status is in [`calltree_patch_summary_double_gyre.md`](calltree_patch_summary_double_gyre.md), since the tree itself is
patch-scope, not base-scope.)

**Every base tree now has zero remaining `create_shadow_container_type` dependencies.** This is a
real change to near-term scheduling: `horizontal_viscosity`, `PressureForce`, `CorAdCalc`,
`vertvisc_family`, and `set_viscosity_family` have **no remaining shared-infrastructure blocker of
any kind** — only `advect_tracer`/`tracer_hordiff` (`Reg`/`Tr`) still have a real blocker in this
file, an independent array-of-struct-decomposition gap unrelated to shared-type shadows. (`btstep`
has the analogous `BTCL_u`/`BTCL_v` gap — see the patch file.)

---

`btstep` is patch-scope, not base-scope — its full status lives in
[`calltree_patch_summary_double_gyre.md`](calltree_patch_summary_double_gyre.md), not here.

## `CorAdCalc` (Coriolis/advection)
Detail: [`CorAdCalc.md`](../.claude/calltree-plans/CorAdCalc.md)

- ✅ **No longer blocking at all.** `OBC`/`AD`/`Waves`/`pbv` — this tree's only ties to the combined
  shared-infrastructure PR — were all deferred this session, confirmed PASSED-BUT-INERT (see the
  deferral section above; `OBC` corrected in-session, an earlier pass kept it active). Zero
  remaining `create_shadow_container_type` dependencies.
- ✅ `Waves`'s optional-struct status is now moot — deferred along with `Waves` itself.
- 🟡 Not blocking, unfinished: setup→per-scheme subroutine interface not fully enumerated;
  `gradKE` split-or-not not confirmed.
- Downstream, not Phase-2: WENO/UP3 fixed-size-array Phase-3 bridging treatment undecided.
- Size: 1889 lines total / 1449 code (`CorAdCalc` + `gradKE` + `UP3_reconstruction`/
  `UP3_Koren_limiter_reconstruction` + the 22 `fac_fn`/`weno_*` procedures).

## `vertvisc_family` (`vertvisc`/`vertvisc_coef`/`vertvisc_remnant`)
Detail: [`vertvisc_family.md`](../.claude/calltree-plans/vertvisc_family.md)

- ✅ **No longer blocking at all — down from a peak of 7 types to 0 across two sessions** (see the
  next two bullets and the deferral section above).
- ✅ **Mechanism change (earlier this session): `visc` (`vertvisc_type`) and `forces` moved out of
  the combined PR entirely.** Field-by-field audit showed all 15 non-`h_ML` `vertvisc_type` fields,
  and all of `forces`'s fields relevant to this tree, are shared only within this exact
  vertvisc-family cluster (`vertvisc`/`vertvisc_coef`/`vertvisc_remnant`/`set_viscous_BBL`/
  `set_viscous_ML`) or, for `forces%taux`/`tauy` specifically, with `btstep` alone — never the
  wide, campaign-spanning sharing the other types have. Neither wholesale-converted
  (`forces%taux`/`tauy` touch 12 files including CESM's production `nuopc_cap` coupling
  interface — too wide for a `BT_cont_type`-style conversion) nor left in the combined PR;
  instead, one local shadow scoped to this cluster (plus a small shared shadow for `taux`/`tauy`
  with `btstep`), buildable now, independent of the combined PR. See `shared_type_unions.md`'s
  "Mechanism decision" section.
- ✅ **Mechanism change (this session): `OBC`/`tv`/`ADp`/`VarMix`/`Waves` all deferred until
  needed** — confirmed PASSED-BUT-INERT under both double_gyre configs, `OBC` included (corrected
  in-session — an earlier pass kept it active, same treatment now extended to it as `continuity()`
  already applied historically). See `shared_type_unions.md`'s "Mechanism decision 2" section and
  the deferral section above. `Waves`'s optional-struct-status question (below) is moot as a
  result.
- **Correction, this session**: `forces%taux`/`forces%tauy` are also dereferenced directly by
  `set_viscous_ML` (`MOM_set_viscosity.F90:2286-2288,2563-2565`) — not previously recorded; this
  tree's `forces` need is really three-way (`btstep`/`vertvisc`/`set_viscous_ML`), not two.
- ✅ `Waves`'s optional-struct status is now moot — deferred along with `Waves` itself (affected
  `vertvisc` only, not the other two entry points, when it was still a live question).
- 🟡 Not blocking, unfinished: `vertvisc_CS` bundle field list explicitly partial.
- ✅ Resolved earlier: `forces%frac_shelf_u`/`v` confirmed `pointer`+`associated()`-guarded (was an
  open question) — now flagged again, differently: coverage under `double_gyre_unsplit` shows
  these fields "live" with suspicious `taux`-sized hit counts despite `ICE_SHELF=False`, likely a
  coverage-tool artifact, not confirmed real (see `shared_type_unions.md`'s runtime exercise audit).
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
- ✅ **No longer blocking at all.** `ADp`/`MEKE`/`VarMix` — this tree's only remaining ties to the
  combined shared-infrastructure PR — were deferred this session (confirmed PASSED-BUT-INERT under
  both double_gyre configs; see the deferral section above). `OBC` was already dropped from this
  tree's needs in an earlier redo (QG-Leith/ZB2020 scoped out). **Zero remaining
  `create_shadow_container_type` dependencies on anything outside this tree.**
- ✅ `STOCH` stays tree-scoped, never blocked externally — built locally.
- 🟡 The optional-struct-dummy gap narrows: `ADp` is now moot (deferred, no shadow to build
  presence-semantics for); `STOCH` still has a *decided* answer for this tree (Q1: shadow first via
  `create_shadow_container_type`, then `convert_present_to_associated`'s grouped-argument rule) —
  unconfirmed against `shared_type_unions.md`'s own tracking note, which now lists only `set_dtbt`'s
  `BT_cont` as a still-live instance campaign-wide (`OBC`'s own combo is now moot too, deferred —
  see that file's "Open item" section).
- Size, now confirmed rather than a lower bound: **2678 lines total, 2109 code** — matches what
  was computed as a partial lower bound before the redo, now the actual total since QG-Leith/
  ZB2020 are confirmed out of scope.

## `PressureForce`
Detail: [`PressureForce.md`](../.claude/calltree-plans/PressureForce.md)

- ✅ Not blocked by EOS — deliberately left external/unblocked permanently, doesn't wait on
  `EOS_bridge_design.md`'s implementation.
- ✅ **No longer blocking at all.** `tv`/`ADp` — this tree's only ties to the combined
  shared-infrastructure PR, genuinely dereferenced not opaque here — were deferred this session
  (confirmed PASSED-BUT-INERT under both double_gyre configs; see the deferral section above).
  **Zero remaining `create_shadow_container_type` dependencies.**
- ✅ Does *not* have the optional-struct-dummy gap the other trees hit.
- Minor, non-blocking: `PressureForce_CS`'s own field list not separately surveyed.
- Size: 2779 lines total / 1991 code (all six subroutines: `PressureForce_Mont_Bouss`/
  `_nonBouss`, `PressureForce_FV_Bouss`/`_nonBouss`, `Set_pbce_Bouss`/`_nonBouss`).

## `advect_tracer` (`advect_tracer`/`advect_x`/`advect_y`)
Detail: [`advect_tracer.md`](../.claude/calltree-plans/advect_tracer.md)

- ✅ Doc verified accurate — no staleness found, only minor line-drift (-7 lines).
- ✅ **No longer blocking at all.** `OBC` — this tree's only tie to the combined
  shared-infrastructure PR — was deferred this session, confirmed PASSED-BUT-INERT (corrected
  in-session, an earlier pass kept it active; see the deferral section above). Zero remaining
  `create_shadow_container_type` dependencies.
- 🔴 Blocking, separate — now the one real blocker: `tracer_registry_type`/`tracer_type`
  (`Reg`/`Tr`) is an array-of-struct needing hand-authored per-field decomposition — same gap as
  `btstep`'s `BTCL_u`/`BTCL_v`, first appearance of this specific type.
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
- ✅ **No longer blocked by shared-type shadows at all.** `MEKE`, `VarMix`, `tv` — three of this
  tree's original five combined-PR ties — were deferred this session (confirmed PASSED-BUT-INERT
  under both double_gyre configs; see the deferral section above). `visc` (`vertvisc_type`, just
  the `h_ML` field) is a small tree-local shadow, never gated on the combined PR at all.
- 🔴 Blocking, separate — the one real remaining blocker: `Reg`/`Tr` array-of-struct
  decomposition — the *same* gap as `advect_tracer`'s, explicitly shared work per the doc
  ("combine with `advect_tracer`'s decomposition work — same type, same gap"), though this tree
  needs a larger field set.
- ✅ `MEKE`'s cross-tree field-reconciliation question (whether `tracer_hordiff`'s `Kh`/`KhTr_fac`
  overlap with `horizontal_viscosity`'s "most/all 15 fields") is now moot — deferred along with
  `MEKE` itself.
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
- Size: 6752 lines total / 4501 code across the 8 in-scope EOS-form kernel files (`MOM_EOS_linear`/
  `_UNESCO`/`_Wright`/`_Wright_full`/`_Wright_red`/`_Jackett06`/`_Roquet_rho`/`_Roquet_SpV.F90`) —
  the actual per-form ports, not yet started except `buggy_Wright_EOS`. `TEOS10_EOS` deferred,
  excluded (247 lines / 136 code, vendored GSW toolbox not counted). Separately, the bridge-seam
  file being shimmed, `MOM_EOS.F90`, is 3024 lines / 2189 code total — only a handful of its
  generic-interface concrete routines (`calculate_density_1d`/`_2d`, etc.) actually get a shim,
  not the whole file.

## Shared infrastructure (`shared_type_unions.md`'s combined PR — what every 🔴 above is actually waiting on)
Detail: [`shared_type_unions.md`](../.claude/calltree-plans/shared_type_unions.md)

- ✅ Resolved: Stage 1, `BT_cont_type` wholesale conversion — the only stage this PR ever actually
  completed.
- ✅ **Mechanism change (earlier this session): `forces` and `vertvisc_type` moved out of this PR
  entirely.** Both types' cross-tree overlap turned out to be narrow and localized —
  `vertvisc_type` shared only within the vertvisc-family cluster, `forces` shared only between
  that cluster and `btstep` for `taux`/`tauy` specifically — not the campaign-wide sharing the
  remaining types had, and both had blast radii too wide for a `BT_cont_type`-style wholesale
  conversion instead (`forces%taux`/`tauy` alone touch 12 files, including CESM's production
  `nuopc_cap` coupling interface). Each now gets its own small local shadow, buildable immediately
  and independently of this PR. See `shared_type_unions.md`'s "Mechanism decision" section.
- ✅ **Mechanism change (this session): the remaining seven types — `OBC`/`ADp`/`tv`/`VarMix`/
  `Waves`/`pbv`/`MEKE` — all deferred until needed, `OBC` included.** Corrected in-session: an
  earlier pass kept `OBC` active as the deferral's "anchor" (the type whose historical `continuity()`
  treatment justified deferring the other six) rather than deferring it too — that was wrong, since
  `OBC` already sat in exactly this "confirmed PASSED-BUT-INERT under both double_gyre configs"
  bucket itself. **This PR is now completely empty — no `create_shadow_container_type` work
  remains for it at all.** See `shared_type_unions.md`'s "Mechanism decision 2" section.
- ✅ Every tree that needed any of these 9 original types now has **zero** remaining
  `create_shadow_container_type` dependency — verified repo-wide, no shadow container type exists
  anywhere for any of them, and none is being built. Field lists for all nine are preserved in
  `shared_type_unions.md` for whenever any gets un-deferred.
- ✅ The one genuine internal ordering dependency this file ever had (Stage 2,
  `tracer_registry_type`/`tracer_type`, needing to land before `OBC`'s now-deferred shadow) is
  moot — but `tracer_registry_type`/`tracer_type`'s decomposition itself is **not** deferred: it's
  still directly needed by `advect_tracer`/`tracer_hordiff` for their own `Reg`/`Tr` dummies,
  independent of `OBC%segment%tr_Reg`. Track it as those two trees' own blocker, not as a stage of
  this now-empty PR.
- Size: 1073 lines total / 572 code across the 13 derived-type definitions originally surveyed —
  `accel_diag_ptrs` (`ADp`), `OBC_segment_type`+`ocean_OBC_type` (`OBC`), `mech_forcing`
  (`forces`), `VarMix_CS`, `wave_parameters_CS` (`Waves`), `porous_barrier_type` (`pbv`),
  `thermo_var_ptrs` (`tv`), `vertvisc_type`, `MEKE_type`, `tracer_type`+`tracer_registry_type`
  (`Reg`/`Tr`), and `BT_cont_type` (already ✅ done — 36/18 of the total). This is the size of the
  *type definitions* originally surveyed, not the (much larger) set of call sites across the
  codebase that dereference them — kept as historical record now that the PR itself is empty.

---

## The one-sentence version

The combined shared-infrastructure PR that used to block every tree in this campaign is now
**completely empty** — `forces`/`vertvisc_type` moved to their own local shadows in an earlier
session, and the remaining seven types (`OBC`/`ADp`/`tv`/`VarMix`/`Waves`/`pbv`/`MEKE`) were all
deferred this session, `OBC` included (corrected in-session from an earlier pass that kept `OBC`
active). **Every base-scope tree now has zero `create_shadow_container_type` dependency.** What's
left, in this file, is exactly one array-of-struct-decomposition gap unrelated to the now-empty
combined PR: `tracer_registry_type`/`tracer_type` (`advect_tracer`/`tracer_hordiff`, shared work).
`horizontal_viscosity`, `PressureForce`, `CorAdCalc`, `vertvisc_family`, and `set_viscosity_family`
have no remaining blocker of any kind from this mechanism — `vertvisc_family`'s own
`visc`/`forces`-subset local shadow work (shared within that cluster, plus a small `taux`/`tauy`
shadow with `btstep`) was never blocked either way and can proceed independently. See
[`calltree_patch_summary_double_gyre.md`](calltree_patch_summary_double_gyre.md) for `btstep`'s analogous
`BTCL_u`/`BTCL_v` gap and the `vertvisc_remnant` validation caveat — both patch-scope, not
base-scope.
