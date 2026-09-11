# Shared derived-type unions across `convert_calltree` campaigns

Authoritative source for every derived type needed, container-based, by more than one actively-
converted entry point. Extracted from `btstep.md`/`horizontal_viscosity.md` when a third tree
(`vertvisc`/`vertvisc_coef`) needed the same types and per-file cross-referencing started
straining. **Every per-entry-point plan file references this file for these types instead of
duplicating or pointing at each other.** Update this file, not a per-entry-point plan, when a
new tree needs one of these types.

## Execution: one combined infrastructure PR, ahead of every entry point (user decision — now empty)

**Status: this PR has shrunk from 9 types to 0.** Originally covered `ADp`, `OBC`, `forces`,
`VarMix`, `Waves`, `pbv`, `tv`, `vertvisc_type`, `MEKE`. `forces`/`vertvisc_type` moved out to
their own local shadows in an earlier session (see "Mechanism decision" below). This session, the
remaining seven — `OBC`, `ADp`, `tv`, `VarMix`, `Waves`, `pbv`, `MEKE` — were all **deferred until
needed** (see "Mechanism decision 2" below), `OBC` included. `BT_cont_type`'s wholesale conversion
(see below) is already done and is the only stage this PR ever actually completed. The remaining
paragraphs in this section describe the original rationale for bundling multiple types into one
PR — retained as historical record (it's still exactly why `forces`/`vertvisc_type` needed
building once and shared when they were live shadow candidates, and would apply again if any of
the seven deferred types gets un-deferred alongside another that shares its fields), not because
anything is actively queued under it right now.

Every shadow type in this file — historically, before the deferrals above — `ADp`, `OBC`,
`forces`, `VarMix`, `Waves`, `pbv`, `tv`, `vertvisc_type`, `MEKE` via `create_shadow_container_type`;
`tracer_registry_type`/`tracer_type` via its own hand-authored decomposition (no sibling skill
covers it, see its section above); `BT_cont_type` via its own wholesale-conversion route (see
below) — was to get built **once**, on **one dedicated branch, landing as one combined PR**,
before any entry point's own Phase 2 runs, not as a side effect of whichever entry point happens
to reach Phase 2 Stage 2 first. Same principle across all three mechanisms, just different tooling
per type. **Now that nothing remains active, this section is kept for the stage-numbering history
below and as the template to reapply if/when any deferred type comes back into scope alongside
another that shares its fields.**

**Why**: without this, whichever entry-point PR runs Stage 2 first for a given type (say `OBC`)
is the one that actually authors that type's definition and generic build/copy-back logic —
silently making every *later* entry point's PR depend on that *earlier* PR's specific diff having
landed, and mixing "new shared infrastructure" into what should be a clean "convert this tree's
own callsites" diff. Pulling it out removes both problems: reviewers see the infrastructure
surface once, in isolation, and every entry-point PR after that is purely mechanical.

**What still stays in each entry point's own PR, and is not eliminated by this**: the small,
tree-specific glue inside that tree's own wrapper — declare a shadow instance, call its
build-from-my-own-dummy step, use the shadow in the container-converted body, call copy-back at
the end. That call is genuinely part of *that tree's* callsite work (it's instantiating the
shared type against that tree's own data) and can't be extracted any further than this — only the
type definition and its generic build/copy-back mechanism move to the combined infrastructure PR.

**Sequencing consequence**: no entry-point plan's Phase 2 Stage 1 needs to wait for this PR to
land — the TreeRoot split is independent. Stage 2 (and any stage touching a listed type) does
wait, the same way `btstep.md` already documents for `BT_cont_type` specifically.

## Base/patch caveat (double_gyre_unsplit base, double_gyre patch)

This combined PR's scope is config-independent — gated by which derived types a tree touches, not
by which MOM6 config runs it — so the double_gyre_unsplit-base/double_gyre-patch resequencing
(see `btstep.md`, `vertvisc_family.md`) doesn't unblock or reblock any stage here. One caveat,
though: coverage shows `MOM_variables.F90` (the closest match to "shared types" in this file) has
a real reachability difference between configs — 27.5% (28/102 lines) under `double_gyre` vs.
15.9% (20/126 lines) under `double_gyre_unsplit`, and the *total* line count itself differs (102
vs. 126), meaning different derived-type members are reachable depending on which dynamics core is
compiled in. Any BT-related shadow fields built during this PR (`ADp`, anything
`BT_cont_type`-adjacent) should be re-verified against actual `double_gyre` capture output
specifically during the *patch* phase — the base phase (double_gyre_unsplit) won't exercise those
fields, so it can't sanity-check them.

## Runtime exercise audit — which of these 9 types are actually live under double_gyre (either config)

Coverage evidence (both `double_gyre` and `double_gyre_unsplit` — this axis is orthogonal to
`SPLIT`, no type below showed a split/unsplit-dependent difference) shows most of these shadow
types are threaded through every call site correctly but carry no real payload in this idealized,
adiabatic, shelf-free, wave-free, MEKE-off configuration:

| Type | Verdict | Why |
|---|---|---|
| `forces` | **EXERCISED (partially)** | Wind-stress/BBL fields real; see tiered table below |
| `vertvisc_type` | **EXERCISED (partially)** | BBL friction fields real; see tiered table below |
| `tv` | PASSED-BUT-INERT | `ENABLE_THERMODYNAMICS=False` → `eqn_of_state` never associated, `T`/`S` never populated |
| `ADp` | PASSED-BUT-INERT | `present(ADp)` true, but every `diag_*` field's ID gate is false (diagnostics not requested in `double_gyre`'s `diag_table`) |
| `pbv` | PASSED-BUT-INERT | Fields read unconditionally, but `USE_POROUS_BARRIER=False` means they're always the trivial fully-open default |
| `VarMix` | PASSED-BUT-INERT | `use_variable_mixing` guard is true (force-enabled by an unrelated default), but the real fields (`Res_fn_*`, `SN_*`, etc.) are never computed |
| `Waves` | PASSED-BUT-INERT | `USE_WAVES=False`; guard covered-false, body never runs; unsplit doesn't even pass `Waves` into `CorAdCalc` |
| `OBC` | PASSED-BUT-INERT | `OBC_NUMBER_OF_SEGMENTS=0` (closed basin) → `associated(OBC)` false everywhere downstream |
| `MEKE` | PASSED-BUT-INERT | `USE_MEKE=False`; `allocated(MEKE%...)` guards covered-false, `step_forward_MEKE` never invoked |

**Consequence for this PR's verification (Stage 12):** once every shadow above is built, only
`forces` and `vertvisc_type` can be capture-fixture-validated with non-trivial data under either
double_gyre config. The other 7 shadows' build/copy-back logic will be exercised (the guard paths
are real) but never checked against real non-null/non-default values by any config currently in
this campaign's scope — that needs a fuller-physics config (`benchmark` showed materially higher
coverage of the relevant files in the earlier campaign-wide coverage pass) before those 7 shadows
can be considered runtime-verified, not just structurally correct.

**Field-level detail for the two exercised types**, filtering out `associated()`/`present()`
guard checks and allocation/registration bookkeeping (which show large hit counts regardless of
whether the underlying data is ever touched — a real trap in this coverage report, see the
artifact notes below):

- **`forces` (`mech_forcing`, 23 fields total): 7 show genuine physics-path dereferences** —
  `taux`, `tauy`, `tau_mag`, `ustar`, `p_surf`, `frac_shelf_u`, `frac_shelf_v`. The other 16 are
  ice-shelf-only, iceberg-only, wave-coupling-only, or tripolar-grid-rotation-only fields, all
  correctly dead given `ICE_SHELF=False`/no wave coupling/a rectangular (non-tripolar) grid.
- **`vertvisc_type` (`visc`, 25 fields total): 6 show genuine physics-path dereferences** —
  `bbl_thick_u`, `bbl_thick_v`, `kv_bbl_u`, `Ray_u`, `Ray_v`, `h_ML` (the last is init-only, not
  live-loop). The other 19 are KPP/ePBL, CVMix-shear, bulk-mixed-layer, or ice-shelf fields, all
  correctly dead given `ENABLE_THERMODYNAMICS=False`/`BULKMIXEDLAYER=False`/no ice shelf.

**Coverage-tool artifacts found, not to be read as physics findings:** (1) `forces%frac_shelf_u`/
`frac_shelf_v` show hit counts identical to the unconditional `taux` line right next to them, despite
`ICE_SHELF=False` implying the array should never even be allocated — most likely a gcov line/
basic-block misattribution, not evidence the ice-shelf path is secretly live; flag before trusting
either field's "exercised" status for anything load-bearing. (2) The reverse problem also occurs:
`visc%bbl_thick_u`/`bbl_thick_v`'s own assignment lines and `visc%kv_bbl_v`'s assignment line
(`MOM_set_viscosity.F90:1189,1192,1193`) are marked `nonexec`/0-hits despite their downstream
consumers showing tens of millions of hits — the data had to come from somewhere, so these lines
are certainly executing; the tool just isn't crediting them. One outright impossible case: a bare
Fortran comment (`MOM_set_viscosity.F90:2968`) is reported "covered, hits=2." Net: treat this
report's per-line attribution as directionally useful but not literally trustworthy at the single-
line level — the file/subroutine-level covered-vs-uncovered verdicts (which is what every other
finding in this document relies on) are much more robust than any single line's hit count.

## Should `forces`/`vertvisc_type` be restructured into subtypes by usage pattern?

Raised after the audit above showed both types' Tier 1/Tier 2 split lines up cleanly with real
physics-package boundaries (wind/BBL-friction vs. ice-shelf/bulk-mixed-layer/CVMix-shear/wave-
coupling). **Recommendation: no, not on the real Fortran types — but the question is already
half-answered by the union-shadow mechanism this file uses, and it's worth being explicit about
why.**

- **Don't touch `mech_forcing`/`vertvisc_type` themselves.** These are upstream MOM6 types used
  far beyond this campaign (15 and 20 files respectively, outside any conversion tree) — splitting
  them into subtypes would be an invasive change to MOM6 itself, not a bridge-layer decision this
  campaign owns, and every field's tier assignment above is derived from one idealized
  configuration's coverage (with confirmed tool-attribution artifacts on both types, see above) —
  not a solid enough basis to redesign a shared upstream type around.
- **The union-shadow mechanism already does the equivalent thing, correctly.** Each type's shadow
  in this file is a needs-based projection — only fields an in-scope entry point actually
  dereferences make the list (7 of `forces`'s 23 fields, 16 of `vertvisc_type`'s 25) — not the
  full original type. That's already "usage-pattern-based," just driven by *which trees are being
  converted*, not by *which physics packages happen to be on in one test config*. No further
  splitting is needed for the shadow's field list itself to stay minimal.
- **What the Tier 1/Tier 2 columns add on top, usefully:** a validation-priority signal *within*
  each already-minimal shadow — which fields Stage 12 (whole-package verification) can actually
  check against real double_gyre/double_gyre_unsplit capture data now, vs. which need a
  shelf/wave/MEKE-enabled config later. Treat this as a documentation/prioritization aid, not a
  reason to further partition the shadow's C++ representation.
- **One place actual C++-side sub-structuring could pay off later, not now:** if/when the shared-
  infrastructure PR's `create_shadow_container_type` mechanism is implemented, grouping each
  shadow's Tier 2 fields into a clearly-named sub-block (e.g. an `ice_shelf`-tagged group within
  the `forces` shadow) could make it obvious at a glance which fields are validated vs.
  structurally-present-but-unverified. That's an implementation-time call for whoever builds
  Stage 6/7, not something to lock in at the planning stage — the mechanism's actual shape isn't
  designed yet, and premature structure here would be exactly the kind of speculative abstraction
  this campaign has avoided everywhere else.

## Mechanism decision: `forces` and `vertvisc_type` move out of the combined PR (user decision, this session)

Follow-up to the audit above: once the actual cross-tree overlap was checked field-by-field
(not just "how many trees need this type" but "which specific fields do more than one tree
touch"), both types turned out to need a different mechanism than the other 7 — not a
BT_cont_type-style wholesale conversion of the real Fortran type, and not the 9-type combined PR
either, but a **local shadow scoped to exactly the trees that share each field**, matching the
localized usage the audit revealed.

**Why not wholesale conversion (the BT_cont_type precedent), for either type:**
`BT_cont_type`'s wholesale conversion worked because its total footprint was narrow — 5 files,
all internal MOM6 dynamics-core code, no consumers outside the campaign. Checked directly this
session: `forces%taux`/`forces%tauy` (the only genuinely cross-tree-shared `forces` fields) are
dereferenced in **12 files**, and 5 of those are coupler/driver "cap" layers —
`mom_surface_forcing_nuopc.F90` (the **CESM production coupling interface**, 15+ separate
read/write sites), `MOM_surface_forcing_gfdl.F90` (FMS_cap), `MOM_surface_forcing.F90`/
`user_surface_forcing.F90` (solo_driver), `mom_surface_forcing_mct.F90` (STALE_mct_cap).
Wholesale-converting these fields' declared type would mean touching production coupling code
that feeds real climate-model runs, not just this campaign's idealized test configs — a
materially higher-stakes change than `BT_cont_type` ever was. `vertvisc_type` is shared 20 files
outside the campaign — also too wide for wholesale conversion to make sense.

**Why not the 9-type combined PR either, for either type:** the combined PR exists to solve one
specific problem — avoiding a shared type having its shape unilaterally decided by whichever
entry-point PR reaches Stage 2 first. That problem only exists where genuinely-independent
conversion efforts share the same field. Checked field-by-field:

- **`forces`**: only `taux`/`tauy` are shared across independent efforts — needed by `btstep`
  (unrelated to the vertvisc family), and separately by `vertvisc`/`set_viscous_ML` (both inside
  the vertvisc-family cluster below). **Corrected finding, this session: `set_viscous_ML` also
  dereferences `forces%taux`/`forces%tauy` directly** (`MOM_set_viscosity.F90:2286-2288,2563-2565`,
  in its BBL-stress calculation) — the existing field table only listed `btstep`/`vertvisc`,
  missing this third consumer. Every other `forces` field is single-tree
  (`rigidity_ice_u`/`rigidity_ice_v` — btstep only; `omega_w2x` — vertvisc only; `p_surf` —
  set_viscous_ML only) or shared only *within* the already-coupled vertvisc-family cluster
  (`frac_shelf_u`/`frac_shelf_v` — vertvisc_coef + set_viscous_ML, both in that cluster) — none of
  those need cross-campaign coordination at all.
- **`vertvisc_type`**: all 15 fields beyond `h_ML` are shared only among
  `vertvisc`/`vertvisc_coef`/`vertvisc_remnant`/`set_viscous_BBL`/`set_viscous_ML` — a family
  already being surveyed and converted together in one plan (`vertvisc_family.md`), not five
  independent efforts. `h_ML` is different in kind: it's dereferenced by `tracer_hordiff`'s own
  in-tree descendants (`hor_bnd_diffusion`, `neutral_diffusion_calc_coeffs`), not by
  `tracer_hordiff`'s top-level body, and has nothing to do with the vertvisc-family cluster beyond
  sharing the same underlying Fortran type — it's `tracer_hordiff`'s own single-tree local need,
  tracked separately.

**Decision:**

1. **`forces%taux`/`forces%tauy` — one shared shadow, scoped to exactly the trees that need it**
   (`btstep` + the vertvisc-family cluster), built independently of the 9-type combined PR, never
   touching `MOM_forcing_type.F90`'s real type definition or any of the 9 files outside this
   campaign. Whichever of `btstep`/`vertvisc`/`set_viscous_ML` reaches Phase 2 Stage 2 first builds
   it; the others consume it — same "build once, don't let one PR silently gate another" principle
   as the combined PR, just scoped to 2-3 trees instead of the whole campaign.
2. **`forces%rigidity_ice_u/v`** — folded into `btstep`'s own tree-local shadow work (already
   documented in `btstep.md`), no sharing needed.
3. **`forces%omega_w2x`, `frac_shelf_u/v`, `p_surf`, and all 15 non-`h_ML` `vertvisc_type` fields**
   — one shared local shadow scoped to the vertvisc-family cluster
   (`vertvisc`/`vertvisc_coef`/`vertvisc_remnant`/`set_viscous_BBL`/`set_viscous_ML`), built by
   whichever of those five reaches Phase 2 Stage 2 first, consumed by the rest. Not gated on the
   9-type combined PR at all — this cluster's `visc`/`forces`-subset work can start immediately, in
   parallel with that PR. (The cluster's Stage 2 still separately needs `OBC`/`ADp`/`tv`/`VarMix`/
   `Waves` from the combined PR for its *other* shared types — this change only removes `forces`
   and `vertvisc_type` from that dependency, it doesn't fully unblock the cluster.)
4. **`vertvisc_type%h_ML`** — folded into `tracer_hordiff`'s own tree-local shadow work, unrelated
   to the vertvisc-family cluster's shadow.

**Net effect on the combined PR (at the time):** shrinks from 9 types to 7 (`OBC`, `ADp`, `tv`,
`VarMix`, `Waves`, `pbv`, `MEKE`). The per-type sections for `forces` and `vertvisc_type` below
reflect this. **Superseded by "Mechanism decision 2" immediately below, which narrows the
remaining 7 down to 1 (`OBC`).**

## Mechanism decision 2: `OBC`/`ADp`/`tv`/`VarMix`/`Waves`/`pbv`/`MEKE` all deferred until needed — the precedent applied to itself too (user decision, this session, corrected)

Follow-up to the runtime exercise audit above, which found `OBC`/`ADp`/`tv`/`VarMix`/`Waves`/
`pbv`/`MEKE` **all** PASSED-BUT-INERT under both `double_gyre` and `double_gyre_unsplit` — every
guard check (`associated(...)`, `present(...)`, config flags) evaluates correctly, but no field
carries real non-default data under either config. `forces`/`vertvisc_type` were the only two
types with genuine live payload, and were already pulled out of this PR (see "Mechanism decision"
above). **Decision: apply the same treatment `continuity()` already gave `OBC` historically to
all seven remaining inert types, `OBC` included** — across every currently-active entry-point plan
that touches any of them. (Corrected in-session: an earlier pass at this decision kept `OBC` itself
active as the "anchor" rather than deferring it too — that was a misreading of the instruction.
The whole point is that `OBC` was already sitting in this exact bucket via `continuity()`, so it
belongs in the deferral, not outside it.)

**What "the same treatment as `OBC` in `continuity()`" means, concretely** (see the confirmation
given earlier this session): `continuity()` never built a shadow for `OBC` at all — it dereferenced
`OBC`'s fields as plain, unconverted Fortran, no `%view()`, no container, no marshalling boundary —
and treated building a real shadow as strictly optional/non-blocking, revisited only when a later
tree's need justified it. Applying that here, to all seven: `OBC`, `ADp`, `tv`, `VarMix`, `Waves`,
`pbv`, `MEKE` are reclassified from `create_shadow_container_type`/union shadow to **"leave alone —
view-marshal at call site,"** the same classification already used for confirmed-opaque leaves
like `CDp`/`PointAccel_CS` — except here the types genuinely *are* dereferenced (not opaque), so
"leave alone" means every wrapper keeps reading their fields with ordinary Fortran dot-notation
exactly as the original code did, and no shadow gets built for any of them, in any tree, for now.

**Why this is safe, not just convenient:** a shadow only matters once a subroutine's actual
C++/AMReX bridge path runs and needs to read/write that type's data on the GPU side — for a type
whose payload is always empty/false under every config this campaign currently targets, there is
nothing yet to bridge. Building the shadow now would be marshalling machinery for data that cannot
be exercised or verified today. Deferring costs nothing but the (currently unusable) ability to run
these fields through the AMReX path immediately; revisit when a config that actually turns on the
relevant physics package (open boundaries, shelf, waves, MEKE, active thermodynamics, variable
mixing) comes into scope.

**Net effect: the combined shared-infrastructure PR is now completely empty.** With `OBC` deferred
too, there is no `create_shadow_container_type` work left for the combined PR to do at all — every
tree's remaining dependency on it is gone. `BT_cont_type`'s wholesale conversion (done) and the
`tracer_registry_type`/`tracer_type` hand-authored decomposition (still genuinely needed, directly,
by `advect_tracer`/`tracer_hordiff` — not just as an `OBC%segment%tr_Reg` prerequisite, so this one
doesn't go away) are the only pieces of "shared infrastructure" with any remaining status at all,
and neither is part of the `create_shadow_container_type` mechanism this section is about.

**Cascading effect on every entry-point plan's blockers** (detailed in each plan's own file, this
is the summary): removing all seven types as things to wait on for a shadow leaves only each tree's
own independent, unrelated blockers — `BTCL_u`/`BTCL_v` for `btstep`, `Reg`/`Tr` for
`advect_tracer`/`tracer_hordiff` — as real remaining dependencies:

| Tree | Combined-PR types before this session | Remaining after all deferrals |
|---|---|---|
| `btstep` | `ADp`, `OBC` | **none** from this mechanism — only its own `BTCL_u`/`BTCL_v` gap remains |
| `CorAdCalc` | `OBC`, `ADp`, `Waves`, `pbv` | **none** — fully clear; `Waves`'s optional-struct-status blocker is also moot |
| `horizontal_viscosity` | `ADp`, `MEKE`, `VarMix` (already `OBC`-free from an earlier redo) | **none** — fully clear |
| `PressureForce` | `tv`, `ADp` | **none** — fully clear |
| `vertvisc_family` | `tv`, `OBC`, `ADp`, `VarMix`, `Waves` | **none** from this mechanism — `Waves`'s optional-struct-status blocker is also moot |
| `set_viscosity_family` | `tv`, `OBC` | **none** — fully clear |
| `tracer_hordiff` | `MEKE`, `VarMix`, `tv` | **none** from this mechanism — `Reg`/`Tr` array-of-struct decomposition remains, unrelated; `MEKE`'s cross-tree field-reconciliation question is also moot |
| `advect_tracer` | `OBC` | **none** from this mechanism — `Reg`/`Tr` array-of-struct decomposition remains, unrelated |

Every tree in the campaign is now clear of `create_shadow_container_type` dependencies entirely
**for the double_gyre_unsplit base and the double_gyre patch.** This is a real change to
near-term scheduling, not just bookkeeping: `horizontal_viscosity`, `PressureForce`, `CorAdCalc`,
`vertvisc_family`, and `set_viscosity_family` have **no remaining shared-infrastructure blocker of
any kind** at those two tiers — only `btstep` (`BTCL_u`/`BTCL_v`) and `advect_tracer`/
`tracer_hordiff` (`Reg`/`Tr`) still have a real blocker there, and both are independent
array-of-struct-decomposition gaps, not shared-type shadow gaps.

**This does not hold for a third tier, `benchmark`.** `tv` and `VarMix` specifically re-activate
there (`ENABLE_THERMODYNAMICS=True`, `USE_VARIABLE_MIXING=True` — confirmed via coverage, real
fields now computed, not just guard-checked) — see their own sections below and
`plan/calltree_patch_summary_benchmark.md` for the full breakdown. `OBC`/`ADp`/`Waves`/`pbv`/`MEKE`
stay deferred even under `benchmark` — none of their gating flags change.

### Stages within the combined PR (now just `OBC` + its prerequisite — see "Mechanism decision 2" above)

One branch, one PR — though with only one shadow type left, "combined" is now legacy framing (kept
so the stage numbers below still line up with what earlier sessions call "Stage 1"). Same
commit/verify/push/CI-check/stop discipline as every entry-point plan's own Phase 2 still applies
whenever this picks back up. (`forces`/`vertvisc_type` were pulled out earlier — see "Mechanism
decision" above; `OBC`/`ADp`/`tv`/`VarMix`/`Waves`/`pbv`/`MEKE` — all seven remaining
`create_shadow_container_type` types — were deferred this session — see "Mechanism decision 2"
above. Their old stage slots are removed below, not renumbered-and-kept, since none of them are
scheduled at all right now.)

1. **`BT_cont_type` — wholesale conversion. ✅ Done.** The only stage with any live status.
   Independent of everything else in this file (its own mechanism, its own five files —
   `MOM_variables.F90`, `MOM_continuity_PPM.F90`, `MOM_barotropic.F90`,
   `MOM_dynamics_split_RK2.F90`, `MOM_dynamics_split_RK2b.F90`). See `btstep.md`'s "BLOCKING
   PREREQUISITE" section for the full field list and reasoning.

**No `create_shadow_container_type` stage is currently scheduled — this PR has nothing left to
do.** `OBC`'s shadow (previously "Stage 3") is deferred along with the other six types (see
"Mechanism decision 2" above). The `tracer_registry_type`/`tracer_type` hand-authored decomposition
(previously "Stage 2," ordered ahead of `OBC`'s shadow specifically for the `segment(:)%tr_Reg`
nesting) is **not deferred** — it's still genuinely needed, directly, by `advect_tracer` and
`tracer_hordiff` for their own `Reg`/`Tr` dummies, independent of whether `OBC`'s shadow ever gets
built. Track it as those two trees' own blocker (see their plan files and the blocker summary),
not as a stage of this now-empty PR — it never needed the "combined, one-PR" treatment in the
first place, since it's a single hand-authored decomposition, not multiple types needing
coordinated ownership.

**If `OBC`/`ADp`/`tv`/`VarMix`/`Waves`/`pbv`/`MEKE` are ever un-deferred** (a config that actually
turns on open boundaries, shelf, wave, MEKE, thermodynamics, or variable-mixing physics comes into
scope), each type's own section below still has its full field list preserved — pick this back up
as new stages appended after Stage 1, not by reinserting the old numbering. Re-evaluate whether a
"combined PR" framing is even still warranted at that point — with `forces`/`vertvisc_type` gone to
local shadows already, un-deferring even a few of the remaining seven might be better handled the
same way (scoped to exactly the trees that need each one) rather than automatically reconstituting
a multi-type bundle.

Each stage: do the work, verify, commit, push, check CI, stop and report — then wait, same rule
as every entry-point plan's own Phase 2 (never start the next stage in the same turn, never
proceed past a failed stage or unresolved verification problem).

Trees covered so far: `continuity()`, `btstep`/`btcalc`/`bt_mass_source`/`set_dtbt`,
`horizontal_viscosity`, `vertvisc`/`vertvisc_coef`/`vertvisc_remnant`, `CorAdCalc`,
`PressureForce`, `set_viscous_BBL`/`set_viscous_ML`, `advect_tracer`, `tracer_hordiff`.
(`btcalc`/`bt_mass_source`/`set_dtbt` don't touch `ADp`/`OBC`/`forces` at all — no union growth
from them, just `barotropic_CS` field additions, recorded in `btstep.md`.)

## `BT_cont_type` — blocking prerequisite, not a shadow

See `btstep.md`'s "BLOCKING PREREQUISITE" section (full reasoning retained there, not migrated
— it's a wholesale-conversion decision, not a union shadow, and only concerns `continuity()`+
`btstep`). `horizontal_viscosity` and `vertvisc`/`vertvisc_coef`/`vertvisc_remnant` do not touch
`BT_cont_type` at all — no update needed here.

## `ADp` (`accel_diag_ptrs`) — DEFERRED until needed (see "Mechanism decision 2" above)

**Not being built now.** Confirmed PASSED-BUT-INERT under both double_gyre configs (every
`present(ADp)` guard covered-true, but every `diag_*` field's ID gate is false since the relevant
diagnostics aren't requested in `double_gyre`'s `diag_table` — see the runtime exercise audit
above). Reclassified to "leave alone — view-marshal at call site" in every tree below: each
wrapper keeps dereferencing `ADp%field` directly via plain Fortran, no shadow, until a config that
actually requests these diagnostics comes into scope. Field list below preserved as reference for
whenever this gets picked back up.

Shared (15 files outside any conversion campaign), confirmed dereferenced (not opaque) by every
tree below.

| Field | Needed by |
|---|---|
| `bt_pgf_u`, `bt_pgf_v` | btstep |
| `bt_cor_u`, `bt_cor_v` | btstep |
| `bt_lwd_u`, `bt_lwd_v` | btstep |
| `diag_hfrac_u`, `diag_hfrac_v` | btstep, horizontal_viscosity |
| `diag_hu`, `diag_hv` | btstep, horizontal_viscosity |
| `visc_rem_u`, `visc_rem_v` | btstep, horizontal_viscosity, vertvisc (via `vertvisc_limit_vel`, opaque there — see note) |
| `du_dt_visc`, `dv_dt_visc` | vertvisc |
| `du_dt_str`, `dv_dt_str` | vertvisc |
| `du_dt_visc_gl90`, `dv_dt_visc_gl90` | vertvisc |
| `rv_x_u`, `rv_x_v` | CorAdCalc |
| `gradKEu`, `gradKEv` | CorAdCalc |
| `sal_u`, `sal_v` | PressureForce (FV form only) |
| `tides_u`, `tides_v` | PressureForce (FV form only) |

Note: `vertvisc_limit_vel` and `write_u_accel`/`write_v_accel` also receive `ADp` but only
forward it opaquely (never dereference `ADp%field` themselves) — per the `write_u_accel`/
`write_v_accel` classification decision (infra, leave alone — see the `vertvisc` plan), this
opaque forwarding never needs the shadow at all; only `vertvisc`'s own top-level body (which
does dereference the fields above directly) needs it.

## `OBC` (`ocean_OBC_type`/`OBC_segment_type`) — DEFERRED until needed (see "Mechanism decision 2" above)

**Not being built now — corrected this session.** Confirmed PASSED-BUT-INERT under both
double_gyre configs: `OBC_NUMBER_OF_SEGMENTS=0` (closed basin) means the pointer stays null all
run, and every `associated(OBC)` guard downstream is covered-false (see the runtime exercise audit
above). Reclassified to "leave alone — view-marshal at call site" in every tree below, same
treatment `continuity()` already gave this exact type historically (see below) — extended here to
`btstep`/`CorAdCalc`/`horizontal_viscosity`/`vertvisc_family`/`set_viscosity_family`/
`advect_tracer` too, not just `continuity()`. This is the type that originally justified the whole
combined-PR mechanism (widest cross-tree sharing, 44 files); deferring it rather than building its
shadow removes the last live reason for that mechanism to exist at all. Field list below preserved
as reference for whenever this gets picked back up — e.g. a config with actual open boundaries.

Shared (44 files outside any conversion campaign, 13 of which deeply dereference it — see
`btstep.md` for why wholesale conversion isn't tractable here, unlike `BT_cont_type`).

**Top-level fields:**

| Field | Needed by | Type |
|---|---|---|
| `number_of_segments` | continuity, btstep, hor_visc, vertvisc, advect_tracer | scalar integer |
| `specified_u_BCs_exist_globally`, `specified_v_BCs_exist_globally` | btstep, advect_tracer | scalar logical |
| `open_u_BCs_exist_globally`, `open_v_BCs_exist_globally` | advect_tracer (new) | scalar logical |
| `exterior_OBC_bug` | advect_tracer (new) | scalar logical |
| `Flather_u_BCs_exist_globally`, `Flather_v_BCs_exist_globally` | btstep, hor_visc | scalar logical |
| `OBC_pe`, `strain_config`, `zero_biharmonic` | hor_visc, advect_tracer (`OBC_pe` only) | scalar (logical/integer/logical) |
| `u_E_OBCs_on_PE`, `u_W_OBCs_on_PE`, `v_N_OBCs_on_PE`, `v_S_OBCs_on_PE` | vertvisc_coef, set_viscous_BBL | scalar logical |
| `segnum_u`, `segnum_v` | vertvisc_coef, set_viscous_BBL | allocatable integer array (top-level, not per-segment) |
| `vorticity_config` | CorAdCalc | scalar (character/integer — confirm exact type) |
| `Js_v_N_obc`, `Je_v_N_obc`, `is_v_N_obc`, `ie_v_N_obc` | set_viscous_BBL | scalar integer — index range where `v_N_OBCs_on_PE` |
| `Js_v_S_obc`, `Je_v_S_obc`, `is_v_S_obc`, `ie_v_S_obc` | set_viscous_BBL | scalar integer — index range where `v_S_OBCs_on_PE` |
| `js_u_E_obc`, `je_u_E_obc`, `Is_u_E_obc`, `Ie_u_E_obc` | set_viscous_BBL | scalar integer — index range where `u_E_OBCs_on_PE` |
| `js_u_W_obc`, `je_u_W_obc`, `Is_u_W_obc`, `Ie_u_W_obc` | set_viscous_BBL | scalar integer — index range where `u_W_OBCs_on_PE` |

**Per-segment fields (`segment(:)`, itself an array-of-struct — see decomposition note below):**

| Field | Needed by | Type |
|---|---|---|
| `segment(:)%specified` | continuity, btstep, advect_tracer | scalar logical |
| `segment(:)%open`, `segment(:)%direction` | continuity, hor_visc (`direction` only), vertvisc (`specified`, `direction`(?) — confirm exact set when vertvisc's own top-level `OBC%segment` access is fully itemized), set_viscous_BBL/set_viscous_ML (`direction` only), advect_tracer (`direction` only) | scalar logical/integer |
| `segment(:)%Flather`, `segment(:)%gradient` | btstep | scalar logical |
| `segment(:)%is_N_or_S`, `segment(:)%is_E_or_W` | hor_visc, set_viscous_BBL/set_viscous_ML, advect_tracer | scalar logical |
| `segment(:)%normal_trans` | continuity, btstep | allocatable real array |
| `segment(:)%normal_vel` | continuity, vertvisc | allocatable real array |
| `segment(:)%SSH` | btstep | allocatable real array |
| `segment(:)%tangential_vel`, `segment(:)%tangential_grad` | hor_visc, CorAdCalc | allocatable real array |
| `segment(:)%on_pe` | CorAdCalc, set_viscous_BBL/set_viscous_ML | scalar logical |
| `segment(:)%HI%jsd`, `%jed` | btstep (`jsd` only), advect_tracer (both — new) | scalar integer |
| `segment(:)%HI%IsdB` | continuity, hor_visc, set_viscous_BBL/set_viscous_ML, advect_tracer | scalar integer |
| `segment(:)%HI%JsdB`, `%isd`, `%ied` | hor_visc, vertvisc (`JsdB` confirmed, `isd`/`ied` not yet confirmed for vertvisc — treat as already covered by hor_visc's need either way), CorAdCalc, set_viscous_BBL/set_viscous_ML (`JsdB` only), advect_tracer (`JsdB`, `isd`, `ied`) | scalar integer |
| `segment(:)%HI%IedB`, `%JedB` | CorAdCalc, set_viscous_BBL/set_viscous_ML, advect_tracer | scalar integer |
| `segment(:)%tr_Reg` | advect_tracer (new field *shape* — pointer to a nested `tracer_registry_type`, itself array-of-struct; see `tracer_registry_type`/`tracer_type` union below) | pointer to `tracer_registry_type` |

`HI` (`hor_index_type`) itself stays unshadowed — plain bounds-carrier, same treatment as `G`.
`segment(:)` remains an array-of-struct needing the same per-field-container decomposition
decided for `local_BT_cont_u_type`/`v_type` in `btstep.md` — still a hand-authored gap, no
sibling skill covers it natively. `segment(:)%tr_Reg` compounds this: a registry nested inside a
segment nested inside the array-of-struct itself — flagged in `advect_tracer.md`, not resolved.

**`vertvisc_coef`'s `segnum_u`/`segnum_v` are a new field *shape* for this union** — top-level
allocatable arrays on `ocean_OBC_type` itself, not nested under `segment(:)`. They map grid
points to a segment index and don't need the array-of-struct decomposition treatment —
ordinary `convert_array_containers` once the shadow exposes them. `advect_tracer` reuses both,
plus two new top-level scalar logicals (`open_u_BCs_exist_globally`, `open_v_BCs_exist_globally`,
siblings of the already-listed `specified_*_BCs_exist_globally` below) and one new top-level
scalar logical, `exterior_OBC_bug`.

## `forces` (`mech_forcing`) — split into a shared cross-cluster shadow plus tree-local fields (not a combined-PR union — see "Mechanism decision" above)

Shared (15 files outside any conversion campaign; `taux`/`tauy` specifically span 12 files — see
"Mechanism decision" above for the full file list and why that rules out wholesale conversion).

| Field | Needed by | Shadow scope | Notes | Runtime tier (double_gyre / double_gyre_unsplit) |
|---|---|---|---|---|
| `taux`, `tauy` | btstep, vertvisc, **set_viscous_ML (corrected, this session — `MOM_set_viscosity.F90:2286-2288,2563-2565`)** | **Shared cross-cluster shadow** (btstep + vertvisc-family cluster) — the only `forces` fields needing this treatment | `pointer`, no `associated()` guard in any of the three — plain container view, no check added (see `btstep.md`'s reasoning) | **Tier 1 — live** (millions of hits, `MOM_vert_friction.F90`) |
| `rigidity_ice_u`, `rigidity_ice_v` | btstep only | btstep's own tree-local shadow | `pointer`, `associated()`-guarded — `%associated()`-checked container | Tier 2 — inert (`ICE_SHELF=False`, guard false, never allocated) |
| `frac_shelf_u`, `frac_shelf_v` | vertvisc_coef, set_viscous_ML (both in the vertvisc-family cluster) | vertvisc-family cluster's local shadow | not yet confirmed pointer-vs-allocatable-vs-guarded; check before finalizing this field's shadow treatment | Tier 2, **but flagged** — coverage shows these as covered with `taux`-sized hit counts despite `ICE_SHELF=False`; likely a coverage-tool line-attribution artifact (see audit above), not confirmed live. Verify directly (not via this coverage report) before relying on either reading |
| `omega_w2x` | vertvisc only | vertvisc-family cluster's local shadow | not yet confirmed pointer-vs-allocatable-vs-guarded; same caveat | Tier 2 — inert (wave-coupling only, `USE_WAVES=False`) |
| `p_surf` | set_viscous_ML only | vertvisc-family cluster's local shadow | not yet confirmed pointer-vs-allocatable-vs-guarded; same caveat | Tier 2 — inert here (this field *is* live elsewhere, e.g. `MOM_dynamics_unsplit_RK2.F90`'s pressure-gradient path, but not in `set_viscous_ML`'s own use of it under this config) |

**Tier 1 = capture-fixture-validatable with real double_gyre/double_gyre_unsplit data today. Tier
2 = the shadow's build/copy-back logic for that field is still needed (the Fortran code genuinely
dereferences it) but can't be checked against non-trivial data without a shelf/wave-coupling
config.** See the runtime exercise audit above for the full 23-field breakdown this table's subset
is drawn from. Only the `taux`/`tauy` row needs cross-tree coordination outside the vertvisc-family
cluster (with `btstep`); every other row is either single-tree or already inside the cluster that
owns `vertvisc_type`'s own local shadow (next section) — no combined PR involvement for any `forces`
field anymore.

## `VarMix` (`VarMix_CS`) — DEFERRED for double_gyre/double_gyre_unsplit, UN-DEFERRED for the benchmark patch

**Not being built for the double_gyre_unsplit base or the double_gyre patch.** Confirmed
PASSED-BUT-INERT under both double_gyre configs — its `use_variable_mixing` guard is genuinely
true (force-enabled by an unrelated default), but every real numeric field (`Res_fn_*`, `SN_*`,
etc.) is never computed (`calc_resoln_function`/`calc_slope_functions` return early or aren't
called at all — see the runtime exercise audit above). Reclassified to "leave alone — view-marshal
at call site" for those two tiers. **Un-deferred for the `benchmark` patch**, which sets
`USE_VARIABLE_MIXING=True` (vs. `False` under both double_gyre configs) — coverage confirms real
fields now computed (`MOM_lateral_mixing_coeffs.F90`: 13.5%→34.9%). See
`plan/calltree_patch_summary_benchmark.md` for the full tree-level breakdown. Field list below
was already complete before the deferral — no re-survey needed to re-activate it.

~89 fields total, shared 12 files. Was tree-scoped to `horizontal_viscosity` alone; now a
3-tree union with `vertvisc_coef` (via `find_coupling_coef_gl90`) and `tracer_hordiff`
(substantial new growth — 8 new fields against 2 already-unioned).

| Field | Needed by |
|---|---|
| `use_variable_mixing` | horizontal_viscosity, vertvisc_coef, tracer_hordiff |
| `Resoln_scaled_Kh`, `Res_fn_q`, `BS_struct` | horizontal_viscosity |
| `Res_fn_h` | horizontal_viscosity, tracer_hordiff |
| `kdgl90_struct` | vertvisc_coef |
| `Resoln_scaled_KhTr`, `khtr_struct`, `SN_u`, `SN_v`, `L2u`, `L2v`, `Rd_dx_h`, `ebt_struct` | tracer_hordiff (all new) |

Still a modest fraction of the type's ~89 fields (10 of 89) — narrow shadow remains the right
call, no Step 3 quantification needed even as a 3-tree union.

## `Waves` (`wave_parameters_CS`) — DEFERRED until needed (see "Mechanism decision 2" above)

**Not being built now.** Confirmed PASSED-BUT-INERT under both double_gyre configs
(`USE_WAVES=False`; guard covered-false, body never runs — the unsplit dynamics core doesn't even
pass a `Waves` argument into `CorAdCalc` at all — see the runtime exercise audit above).
Reclassified to "leave alone — view-marshal at call site" for `vertvisc`/`CorAdCalc`. This also
makes the "optional struct dummy" open item below **moot for `Waves` specifically** — there's no
shadow being built, so there's no "how does the shared build/copy-back API signal not-present"
question to resolve for it right now. Field list preserved as reference for whenever this gets
picked back up.

`vertvisc` and `CorAdCalc` both need this now. **Correction to the file count**: `vertvisc`'s
own survey said 14 files repo-wide; `CorAdCalc`'s survey, done more carefully (case-insensitive,
since the type is actually spelled `wave_parameters_CS` lowercase at its definition), found
**10 files**. Use 10 going forward, not 14.

| Field | Needed by |
|---|---|
| `us_x`, `us_y` | vertvisc, CorAdCalc |
| `Stokes_VF`, `Passive_Stokes_VF` | CorAdCalc |

`Waves` is `optional, pointer` in both signatures — extends the optional-struct open item below.

## `pbv` (`porous_barrier_type`) — DEFERRED until needed (see "Mechanism decision 2" above)

**Not being built now, for `CorAdCalc`/`set_viscous_BBL` either** — extending the same treatment
`continuity()` already gave this type (see below: `continuity()` left it fully raw from the
start, never building a shadow at all). Confirmed PASSED-BUT-INERT under both double_gyre configs:
fields are dereferenced unconditionally, but `USE_POROUS_BARRIER=False` means the values are
always the trivial "fully open" default — the real geometry calculation in
`MOM_porous_barriers.F90` never runs (see the runtime exercise audit above). Reclassified to
"leave alone — view-marshal at call site" everywhere. Field list preserved as reference.

4 fields (`MOM_variables.F90:355-362`, all public allocatable 3-D real arrays):
`por_face_areaU`, `por_face_areaV`, `por_layer_widthU`, `por_layer_widthV`. Shared 10 files.
**`continuity_PPM.F90`'s `zonal_mass_flux`/`meridional_mass_flux`/`zonal_BT_mass_flux`/
`continuity_adjust_vel` family already dereferences `pbv%por_face_areaU`/`por_face_areaV`
directly** (confirmed: `pbv` arrives as `type(porous_barrier_type), intent(in)`, its two area
fields extracted once and passed onward as plain real array dummies) — still fully raw, never
converted in the original hand-done `continuity()` campaign, same leftover-shared-type situation
`BT_cont_type`/`OBC` were in. `CorAdCalc` touches the same two fields
(`por_face_areaU`/`por_face_areaV`), not `por_layer_widthU/V`. `set_viscous_BBL` is the first
tree to need all 4 fields (`set_viscous_ML` doesn't take `pbv` at all).

| Field | Needed by |
|---|---|
| `por_face_areaU`, `por_face_areaV` | continuity, CorAdCalc, set_viscous_BBL |
| `por_layer_widthU`, `por_layer_widthV` | set_viscous_BBL |

Narrow enough (all 4 of 4 fields, still just one small type) that building a union shadow would
have been mechanical, no Step 3 needed — but per "Mechanism decision 2" above, it's deferred
instead, same reasoning as `OBC`: `continuity()` never converted the type itself, not a candidate
for wholesale conversion the way `BT_cont_type` was, and `continuity()` (or any other tree)
adopting a shadow later remains fully optional/non-blocking.

## `tv` (`thermo_var_ptrs`) — DEFERRED for double_gyre/double_gyre_unsplit, UN-DEFERRED for the benchmark patch

**Not being built for the double_gyre_unsplit base or the double_gyre patch.** Confirmed
PASSED-BUT-INERT under both double_gyre configs — `ENABLE_THERMODYNAMICS=False` means
`tv%eqn_of_state` is never `associated`, `T`/`S` never populated (see the runtime exercise audit
above and `EOS_bridge_design.md`'s corrected caveat). Reclassified to "leave alone —
view-marshal at call site" for `PressureForce`, `tracer_hordiff`, `set_viscosity_family`, and the
vertvisc-family cluster (`vertvisc_coef`/`vertvisc_remnant`) alike, for those two tiers only.
**Un-deferred for the `benchmark` patch**, which sets `ENABLE_THERMODYNAMICS=True` — coverage
confirms real EOS kernel execution now (`MOM_EOS.F90`: 0.3%→13.5%; the actual resolved form,
`MOM_EOS_Wright_full.F90`: 0.0%→31.3% — the first real runtime validation of
`EOS_bridge_design.md`'s tier-1 claim for this form). See `plan/calltree_patch_summary_benchmark.md`
for the full tree-level breakdown. Field list below was already complete before the deferral — no
re-survey needed to re-activate it.

Shared 101 files repo-wide — the widest-shared type in the whole campaign. Every tree through
`CorAdCalc` treated `tv` as purely opaque (0 field dereferences); `vertvisc_coef`/
`vertvisc_remnant` were the first to need any shadow at all (just `SpV_avg`, narrow, tree-scoped
at the time). `PressureForce` is a different order of magnitude — every one of its 6 subroutines
genuinely dereferences `tv` directly, not just forwards it, so this is now a real union, not a
one-field convenience shadow.

| Field | Needed by |
|---|---|
| `SpV_avg` | vertvisc_coef, vertvisc_remnant (via `find_coupling_coef`/`_k`) |
| `T`, `S` | PressureForce (all forms), tracer_hordiff (own body + `tracer_epipycnal_ML_diff`) |
| `P_Ref` | PressureForce (all forms), tracer_hordiff (via `tracer_epipycnal_ML_diff`) |
| `eqn_of_state` | PressureForce (all forms), tracer_hordiff (via `tracer_epipycnal_ML_diff`) — the EOS
  dispatch handle itself; see the EOS blocking-prerequisite section below, this field is
  forwarded opaquely into `MOM_EOS.F90` calls, never dereferenced further by either tree |
| `varT` | PressureForce (`PressureForce_FV_Bouss` — Stanley SGS-variance diagnostics) |
| `p_surf` | tracer_hordiff (new — `associated()`-guarded, forwarded into `neutral_diffusion_calc_coeffs`) |

## EOS runtime polymorphism — blocking prerequisite, planned (see `EOS_bridge_design.md`)

`MOM_EOS.F90` holds a `class(EOS_base), allocatable` component dispatched across 9 concrete
implementations (`linear_EOS`, `UNESCO_EOS`, `buggy_Wright_EOS`, `Wright_full_EOS`,
`Wright_red_EOS`, `Jackett06_EOS`, `TEOS10_EOS`, `Roquet_rho_EOS`, `Roquet_SpV_EOS`), used by
**59 files** repo-wide. Reached (at least) by `continuity()` (already fully converted, EOS
untouched), `horizontal_viscosity`'s QG-Leith branch (bounded at `calc_QG_slopes`), `MOM.F90`'s
main step and `MOM_MEKE.F90` (side-effect discoveries, not campaign entry points), and
`PressureForce` (pervasively, ~32 call sites, central to every branch).

**No longer just deferred — a full design now exists in `.claude/calltree-plans/EOS_bridge_design.md`.**
Summary: the form is chosen once at init (2 call sites total, never re-dispatched per-timestep),
8 of the 9 implementations are small self-contained closed-form kernels (only `TEOS10_EOS` pulls
in the vendored ~16,478-line GSW-Fortran toolbox), and every elemental kernel is `elemental`
(=`pure`) — no parallelism obstacle. Decisions recorded there: bridge all 8 self-contained forms
now (`TEOS10_EOS` deferred to its own porting effort), shim seam at `MOM_EOS.F90`'s
generic-interface concrete routines (`calculate_density_1d`/`_2d`, etc. — ordinary module
subroutines, fits the existing `cpp_bridge_lessons` shim pattern directly), plus one new
one-time init-time bridge call to resolve which form's C++ implementation to use, mirroring
`EOS_init` exactly since the choice never changes mid-run. **Still planning only — no
implementation yet.** Every "leave EOS alone, view-marshal" classification already recorded in
`btstep.md`/`horizontal_viscosity.md`/`PressureForce.md`/`vertvisc_family.md` stays valid and
unchanged once this lands — the bridge's default mode is Fortran-truth, bit-identical, so those
plans need no revision.

## `vertvisc_type` (the `visc` dummy) — vertvisc-family local shadow, not part of the combined PR (see "Mechanism decision" above)

25 fields (`MOM_variables.F90:258-313`), shared 20 files outside the campaign — too wide for a
BT_cont_type-style wholesale conversion, but all 15 non-`h_ML` fields are shared *only* among
`vertvisc`/`vertvisc_coef`/`vertvisc_remnant`/`set_viscous_BBL`/`set_viscous_ML`, one family
already surveyed and converted together in `vertvisc_family.md` — not five independent efforts, so
this needs a local shadow scoped to that cluster, not the 9-type combined PR. First needed by
`vertvisc`/`vertvisc_coef`/`vertvisc_remnant` (tree-scoped at the time: `Ray_u/v`,
`taux_shelf`/`tauy_shelf`, `Kv_bbl_u/v`, `bbl_thick_u/v`, `tbl_thick_shelf_u/v`,
`Kv_tbl_shelf_u/v`, `Kv_slow`, `nkml_visc_u/v`). `set_viscous_BBL` (`Ray_u/v`, `bbl_thick_u/v`,
`Kv_bbl_u/v`) and `set_viscous_ML` (`Kv_tbl_shelf_u/v`, `nkml_visc_u/v`, `taux_shelf`/`tauy_shelf`,
`tbl_thick_shelf_u/v`) need nothing beyond what's already there — the cluster's local shadow can be
built with zero field-list changes from what `vertvisc_family.md` already specifies, by whichever
of the five entry points reaches Phase 2 Stage 2 first, and consumed by the rest.

**`h_ML` is not part of this cluster shadow.** Needed by `tracer_hordiff`'s own in-tree callees
`hor_bnd_diffusion` and `neutral_diffusion_calc_coeffs` — not by `tracer_hordiff`'s own body,
which forwards the `visc` dummy opaquely (same "only the true consumer needs the shadow" pattern
already noted above for `ADp`/`write_u_accel`) — and unrelated to the vertvisc-family cluster
beyond sharing the same underlying Fortran type. Track it as `tracer_hordiff`'s own single-tree
local shadow field, built independently whenever that tree's Phase 2 runs.

**Runtime tier, double_gyre / double_gyre_unsplit (see the runtime exercise audit above for the
full 25-field breakdown):** of the vertvisc-family cluster's 15 fields, **Tier 1 — live**:
`Ray_u`, `Ray_v`, `Kv_bbl_u`, `Kv_bbl_v` (its own assignment line is a coverage-attribution
artifact — treat as live, symmetric with `Kv_bbl_u`), `bbl_thick_u`, `bbl_thick_v` (same artifact
caveat). **Tier 2 — inert**: `taux_shelf`, `tauy_shelf`, `tbl_thick_shelf_u`, `tbl_thick_shelf_v`,
`Kv_tbl_shelf_u`, `Kv_tbl_shelf_v` (all ice-shelf-only, `ICE_SHELF=False`), `Kv_slow`
(CVMix-shear off), `nkml_visc_u`, `nkml_visc_v` (`BULKMIXEDLAYER=False`). So this shadow's Tier
1/Tier 2 split lines up almost exactly with the physical BBL-friction vs. ice-shelf/bulk-mixed-layer
boundary already visible in how the fields were grouped by consuming subroutine above.
`tracer_hordiff`'s separately-tracked `h_ML` is Tier 1 but init-only (not live-loop) — see the
runtime exercise audit above.

## `MEKE` (`MEKE_type`) — DEFERRED until needed (see "Mechanism decision 2" above)

**Not being built now.** Confirmed PASSED-BUT-INERT under both double_gyre configs —
`USE_MEKE=False`; `allocated(MEKE%mom_src/Ku/Au)` guards covered-false, `step_forward_MEKE` never
invoked (see the runtime exercise audit above). Reclassified to "leave alone — view-marshal at
call site" for `horizontal_viscosity`/`tracer_hordiff`. This also makes the cross-tree
field-reconciliation open item below **moot for now** — no shadow is being built, so there's
nothing to reconcile `tracer_hordiff`'s `Kh`/`KhTr_fac` against yet. Field list preserved as
reference for whenever a MEKE-enabled config comes into scope.

15 fields, shared 11 files. `horizontal_viscosity` dereferences most/all 15 (`Ku`/`Au` feed
`Kh`/`Ah` directly, `mom_src` written) — exact field-by-field list not itemized in
`horizontal_viscosity.md`, only "most/all". `tracer_hordiff` needs `Kh` (`allocated()`-guarded
real array) and `KhTr_fac` (real scalar) — **not yet confirmed against `horizontal_viscosity`'s
"most/all"**; likely already covered given the high touch fraction there, but treat as
unconfirmed overlap, not assumed, until itemized.

| Field | Needed by |
|---|---|
| `Ku`, `Au`, `mom_src` | horizontal_viscosity |
| `Kh`, `KhTr_fac` | tracer_hordiff (overlap with horizontal_viscosity's "most/all" unconfirmed) |

## `tracer_registry_type`/`tracer_type` (`Reg`/`Tr`) — new union (first appearance this session,
already a 2-tree union at first survey)

`tracer_registry_type%Tr` is a **fixed-size** array (`Tr(MAX_FIELDS_)`, not allocatable) of
`tracer_type`, ~40 fields per element, shared 45 files repo-wide (`tracer_registry_type` itself)
— the widest-shared array-of-custom-derived-type situation found this session, wider than `OBC`
(44 files). Same hand-authored per-field decomposition gap as `BTCL_u`/`BTCL_v` (`btstep.md`) and
`OBC%segment` — no sibling skill covers it. First surveyed for `advect_tracer`, immediately also
needed by `tracer_hordiff` — union from the start, not a later promotion.

| Field | Needed by |
|---|---|
| `t` | advect_tracer, tracer_hordiff (own body + `tracer_epipycnal_ML_diff`) |
| `ad_x`, `ad_y`, `ad2d_x`, `ad2d_y`, `advection_xy` | advect_tracer |
| `advect_scheme` | advect_tracer |
| `df_x`, `df_y`, `df2d_x`, `df2d_y` | tracer_hordiff (own body + `tracer_epipycnal_ML_diff`) |
| `name` | tracer_hordiff |
| `conc_underflow` | tracer_hordiff (own body + `tracer_epipycnal_ML_diff`) |
| `conc_scale` | tracer_hordiff (via `hor_bnd_diffusion`) |
| `id_hbd_dfx`, `id_hbd_dfy`, `id_hbd_dfx_2d`, `id_hbd_dfy_2d`, `id_hbdxy_cont`, `id_hbdxy_cont_2d`, `id_hbdxy_conc` | tracer_hordiff (via `hor_bnd_diffusion`) — diagnostic handles; **exclude these from any container decomposition**, same "exclude `id_*`" precedent as every private CS this session, now shown to apply *inside* an array-of-struct field list too, not just at top-level CS scope |

`OBC%segment(:)%tr_Reg` (see the `OBC` union above) is itself a pointer to a nested
`tracer_registry_type` — this union's fields apply recursively there too, compounding rather than
separate from the `OBC%segment` decomposition gap.

## Not yet unions — tree-scoped shadows to watch

`STOCH` (horizontal_viscosity only). Promote to this file if/when a second tree needs it.

## Open item — optional struct dummies (cross-referenced, not resolved)

First flagged in `horizontal_viscosity.md` (`BT`/`TD`/`ADp`/`STOCH` all optional structs, `OBC`
optional+pointer combo). **`ADp`'s and `OBC`'s instances are now moot** — both deferred (see
"Mechanism decision 2" above), no shadow being built for either, so there's no presence-semantics
to design right now; `BT`/`TD`/`STOCH` are unrelated config-bundle/tree-scoped types, unaffected.
`vertvisc`'s and `CorAdCalc`'s `Waves` (`optional, pointer` in both) was the same category — **also
now moot**, same reason (deferred). `set_dtbt`'s `BT_cont` (`optional, pointer`, confirmed opaque
— see `btstep.md`) is the **only instance still live** now, since `BT_cont_type` itself is
wholesale-converted, not deferred. No existing sibling skill covers "optional struct dummy →
bind(C)-ready" — still unresolved for this one live instance, still deliberately not guessed
through. Resolve whenever `set_dtbt`'s Phase 2 picks it up, and update this note if any deferred
type (`OBC` especially, given `horizontal_viscosity`'s combo) comes back into scope.
