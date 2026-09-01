# Call-tree conversion plan: `CorAdCalc`

Entry point: `CorAdCalc`, `submodules/MOM6/src/core/MOM_CoriolisAdv.F90:142-1350`.
Produced by Phase 1 of `convert_calltree`. Read by Phase 2 and Phase 3.
Cross-reference: `.claude/calltree-plans/shared_type_unions.md`, the authoritative source for
`OBC`, `ADp`, `Waves`, and `pbv` (all grown or newly added by this tree).

No pre-existing audit doc existed for this entry point (unlike `btstep`/`horizontal_viscosity`/
`vertvisc`) — this plan's inventory was surveyed fresh.

## Hard precondition checks

- Callers confirmed: same 4 dynamics-core files as every other entry point in this campaign
  (`MOM_dynamics_unsplit.F90` x3, `MOM_dynamics_unsplit_RK2.F90` x2, `MOM_dynamics_split_RK2b.F90`
  x2, `MOM_dynamics_split_RK2.F90` x4 — 11 call sites total). No other file calls `CorAdCalc`.
- Shared-descendant check: `gradKE`, `UP3_reconstruction`, `UP3_Koren_limiter_reconstruction`,
  `fac_fn`, and every `weno_three/five/seven_*` helper (22 procedures total) confirmed zero
  callers anywhere outside `MOM_CoriolisAdv.F90`. `CoriolisAdv_init`/`CoriolisAdv_end`/
  `CoriolisAdv_stencil` are init/teardown/introspection, out of scope, same pattern as every
  other entry point's `_init`/`_end` siblings.
- `OBC`, `AD` (`accel_diag_ptrs`), `Waves`, `pbv` are all shared with other actively-converted or
  already-converted trees — see `shared_type_unions.md`, not a wholesale-conversion situation for
  any of them (same reasoning as `OBC`/`BT_cont_type` in `btstep.md`).

## Step 1d — wrapper case

**Case 3.** `CorAdCalc` is one subroutine, called directly under its own name —
`public CorAdCalc, CoriolisAdv_init, CoriolisAdv_end, CoriolisAdv_stencil` — no wrapper, no
alias. Phase 2 Stage 1 must rename `CorAdCalc` → `CorAdCalc_TR` and author a new `CorAdCalc`
wrapper (pure pass-through, matching the current external signature exactly, no `bind(C)`).
`CorAdCalc_TR` is bridged in Phase 3's last wave; the wrapper is never bridged.

**Also part of Stage 1 (see "Split into per-scheme subroutines" below):** like
`horizontal_viscosity`, this entry point's body gets restructured into named subroutines as part
of Stage 1, not just renamed.

## External signature (frozen — do not change)

`CorAdCalc(u, v, h, uh, vh, CAu, CAv, OBC, AD, G, GV, US, CS, pbv, Waves)` —
`MOM_CoriolisAdv.F90:142-165`. Only `Waves` is optional (`optional, pointer` — extends the
optional-struct open item in `shared_type_unions.md`). `OBC` is `pointer`, not `optional`. `AD`
is `intent(inout)`, not optional or pointer — different from `horizontal_viscosity`'s `ADp`
(which was `optional`).

## Loop-nesting decision — no k-fold, this subroutine only (user decision)

`CorAdCalc` has one `do k=1,nz` loop (line 362, spans nearly the entire body) with
`do concurrent (J=...,I=...)` blocks nested inside for the horizontal work — i.e. today's
parallelism is "serial over k, parallel over i/j within each k." Investigated folding k into a
single `do concurrent(k,J,I)` construct to expose 3D parallelism, since that's directly relevant
to this campaign's GPU/AMReX goal. Quantified finding:

- Zero cross-layer (`k-1`/`k+1`) dependencies anywhere in the k-loop body — physically expected,
  since Coriolis/PV-advection and the KE-gradient at layer k only need layer-k's horizontal
  neighbors.
- Of 31 declared 2D scratch locals, **zero are single-pass** — the code's authors already
  scalarized every temporary that's genuinely write-then-immediately-read at one point (e.g.
  `fv1..4`, `Heff1..4`, `uhc`). What's left as 2D arrays are, by construction, exactly the ones
  that cross a `do concurrent` construct boundary within one k-iteration: 2 are k-invariant
  (`Area_h`, `Area_q`, computed once outside the loop), 11 are cross-pass at the *same* index
  (could in principle be fused to scalars with further restructuring), and **18 have a genuine
  neighbor-index dependency** (up to a ±4-point WENO stencil) that cannot be eliminated by any
  loop reorganization, only by allocating real storage.
- If k folds into the `do concurrent` set, every non-k-invariant 2D local needs a k dimension
  (else different "concurrent" k-iterations race on the same 2D storage) — costing, per the
  subroutine's own 7 3-D state arrays (`u`,`v`,`h`,`uh`,`vh`,`CAu`,`CAv`) as the reference unit,
  **≈2.4× that memory in the default configuration, up to ≈4× with every optional feature
  (Stokes, WENO, `Coriolis_En_Dis`, diagnostics) enabled.**

**Decision (user, this session): do not fold k into the `do concurrent` construct for
`CorAdCalc`.** The horizontal domain (`nx·ny`) is almost certainly already large enough to
saturate GPU occupancy on its own for a global-ocean grid, so the marginal parallelism gain from
also parallelizing over k is low-value against a real, quantified memory cost. Keep k as the
outer loop, `(i,j)` as the parallel dimension, exactly as today — Phase 2's container conversion
of locals (Step 7) should keep these 2D scratch arrays 2D (or `RealArray_t` containers matching
their actual 2D shape, reused once per k-iteration exactly as now), not attempt any 3D promotion.

**Explicitly not a general rule** — record this as scoped to `CorAdCalc` only. Every other/future
entry point in this campaign needs its own k-loop dependency analysis before any k-fold decision
(or non-decision) is made for it; do not carry this "no" forward by default.

**Separate, smaller, optional opportunity (not required by this campaign):** the 11
same-index cross-pass locals (`rel_vort`, `dvdx`, `dudy`, `dvSdx`, `duSdy`, `stk_vort`, `KE`,
`KEx`, `KEy`, `uh_center`, `vh_center`) could be fused to scalars with further internal loop
reorganization, independent of the k-fold question — this would shrink today's already-2D
memory footprint too, not just a hypothetical 3D-promoted one. Noted for awareness, not
scheduled as part of this plan.

## Split into per-scheme subroutines (user decision: Option B)

`CorAdCalc` dispatches on `CS%Coriolis_Scheme` across 9 discretization choices
(`SADOURNY75_ENERGY`, `SADOURNY75_ENSTRO`, `ARAKAWA_HSU90`, `ARAKAWA_LAMB81`, `AL_BLEND`,
`ROBUST_ENSTRO`, `wenovi7th/5th/3rd_PV_ENSTRO`), each `if`/`elseif` branch selected once via a
control-structure field (invariant across i/j/k for a given run — not a per-gridpoint runtime
branch). `gradKE` (called once per k, unconditionally) has its own separate, smaller dispatch on
`CS%KE_Scheme` (`KE_ARAKAWA`/`KE_SIMPLE_GUDONOV`/`KE_GUDONOV`/`KE_UP3`).

**Decision (user, this session): split, for readability** — same organizational choice as
`horizontal_viscosity`, made for a different reason here (readability, not scope/blast-radius,
since every branch is already confirmed self-contained with zero shared descendants regardless
of split-or-not).

**Structure is 3-part, not a flat list of 9 independent subroutines** — worth being explicit
about, since it's a different shape from `horizontal_viscosity`'s GME/QG-Leith/ZB2020 (which
really were independent). Every `Coriolis_Scheme` branch shares:
- A **common setup stage** (lines ~283-636, before the first `if (CS%Coriolis_Scheme==...)` at
  line 642): computes `q`, `qS`, `Ih_q`, `h_q`, `Area_q`, `Area_h`, `rel_vort`, `abs_vort`,
  `stk_vort`, `hArea_u`, `hArea_v`, and others — potential vorticity and related diagnostics
  every scheme consumes.
- A **common finalization/diagnostics stage** (lines ~1243+): `post_data`/`post_product_*` calls
  gated by `CS%id_*` fields, consuming whichever scheme's `CAu`/`CAv`/`KEx`/`KEy` results.

Suggested resulting structure (names illustrative, Stage 1 may refine): `CorAdv_setup` (shared
precompute), `CorAdv_sadourny` (`SADOURNY75_ENERGY`/`ENSTRO`), `CorAdv_arakawa`
(`ARAKAWA_HSU90`/`LAMB81`/`AL_BLEND`), `CorAdv_robust_enstro` (`ROBUST_ENSTRO`), `CorAdv_weno`
(all three `wenovi*_PV_ENSTRO` variants together — note these already share internal fallback
logic to narrower stencils near boundaries, e.g. the `wenovi7th` branch calls `weno_five_...`/
`weno_three_...` near masked points, so keep all three orders in one subroutine rather than
three separate ones — and gets the `pure`/`do concurrent` fix described below), `CorAdv_finalize_diagnostics`
(shared post-processing). **Exact interface
between these — which of setup's ~15 outputs each per-scheme subroutine actually needs as a new
dummy — was not fully enumerated in this survey; confirmed necessary at minimum: `q`, `abs_vort`
(read by multiple scheme branches per the loop-nesting analysis above); Stage 1's own execution
needs to work out the complete interface once it's actually splitting the code.**

`gradKE`'s own `CS%KE_Scheme` dispatch is much smaller (~150 lines total) — **default: leave
`gradKE` as one subroutine, don't force the same split treatment**, since the readability
motivation that justified splitting `CorAdCalc` is far weaker at this size (already just 4
branches, 2 of which reuse the existing `UP3_reconstruction`/`UP3_Koren_limiter_reconstruction`
leaves). Flagged for confirmation rather than assumed silently — revisit if the user wants full
consistency with `CorAdCalc`'s split.

## The WENO/UP3 kernel family — not container targets (new classification precedent)

22 procedures (`fac_fn`, `weno_three/five/seven_h_weight_reconstruction` drivers and their
internal weight/reconstruction helpers, `UP3_reconstruction`, `UP3_Koren_limiter_reconstruction`)
operate on **fixed-size stencil arrays** (`q4(4)`, `q6(6)`, `q8(8)`, etc.) — not
`SZI_`/`SZJ_`-macro-dimensioned grid arrays. Confirmed: zero external callers anywhere, all
leaves except the three `_h_weight_reconstruction` drivers (which call their own weight/
reconstruction helpers + `fac_fn`), none declared `pure`/`elemental` despite being pure functions
in effect.

**Classification: these dummies are not `RealArray_t`/`IntArray_t` targets — leave as plain
Fortran fixed-size arrays.** `RealArray_t` containers exist for dynamically-sized, grid-shaped
arrays where alloc/view/copy semantics and a runtime shape descriptor earn their cost at a
`bind(C)` boundary; a compile-time-fixed `dimension(4)` array has none of that — it's passed by
ordinary array-section slicing at the call site (e.g. `q4 = q(i-1:i+2)`) and lives on the
stack/in registers. Converting these to containers would be actively counterproductive. **First
time this pattern has appeared in the campaign — flagging clearly as a new precedent rather than
silently assuming it, but resolved by the same reasoning that already governs `RealArray_t`'s
scope, not a fresh Step 3 question.**

**Open item this creates for Phase 3, not resolved here:** `generate_cpp_bridge`'s own Step 0
precondition (every array dummy already a container) is written with grid-shaped arrays in mind.
A fixed-size array dummy doesn't need that precondition at all — `bind(C)` supports plain
fixed-size arrays natively (`real(c_double), intent(in) :: q4(4)` is a valid interop
declaration with no container wrapping needed). Whether/how `generate_cpp_bridge` accommodates
this is that skill's own call, informed by `cpp_bridge_lessons` (not loaded in this session) —
flag it explicitly when Phase 3 reaches this family rather than assuming either "exclude these
from bridging" or "bridge them directly, no container needed" silently.

## Make the WENO/UP3 kernel family `pure`; convert the WENO branches' loops to `do concurrent`
(user decision)

Investigated whether the fixed-size-array classification above forces any change to how the
WENO calculations are performed (user question) — it doesn't, but reading the actual branches
turned up a real, separate parallelism gap worth fixing. All three WENO branches
(`wenovi7th_PV_ENSTRO` line 836, `wenovi5th_PV_ENSTRO` line 886, `wenovi3rd_PV_ENSTRO` line 922)
consistently use a **plain serial `do j=js,je ; do I=Isq,Ieq`**, preceded by
**`!$omp target update from(u, vh, abs_vort, h_q, q)`** — unlike every other `Coriolis_Scheme`
branch (Sadourny, Arakawa, `ROBUST_ENSTRO`), which all use `do concurrent (j=js:je, I=Isq:Ieq)`
with no host data pull. No comment explains this. Confirmed: none of the 22 WENO/UP3 procedures
is declared `pure`/`elemental`, and Fortran's `do concurrent` generally cannot call an impure
procedure — this fully explains the serial loop and the host round-trip, independent of anything
about the fixed-size arrays themselves (the per-grid-point calling pattern, small local slices
`abs_vort(I,J-4:J+3)` etc., is identical in shape to how `do concurrent` branches use their own
2D arrays elsewhere in this subroutine).

**Decision (user, this session): make the fix.**
1. Declare `weno_three_h_weight_reconstruction`, `weno_five_h_weight_reconstruction`,
   `weno_seven_h_weight_reconstruction`, and every internal helper they call (`fac_fn`,
   `weno_three_weight`, `weno_three_reconstruction_0/1`, `weno_five_weight_0/1/2`,
   `weno_five_reconstruction_0/1/2`, `weno_seven_weight_0/1/2/3`,
   `weno_seven_reconstruction_0/1/2/3`) `pure` — they already have no side effects, no I/O,
   nothing that should block it. Also declare `UP3_reconstruction`/
   `UP3_Koren_limiter_reconstruction` `pure` for the same reason and consistency, even though
   `gradKE`'s own loop isn't part of this specific fix (see below).
2. Convert each of the three WENO branches' `do j=js,je ; do I=Isq,Ieq` to
   `do concurrent (j=js:je, I=Isq:Ieq)`, matching the sibling branches' style. The per-point body
   (masking-stencil checks, small-array slicing, kernel calls) is otherwise unchanged — this is
   purely a loop-construct change, not a data-structure or calculation change.
3. Remove the now-unnecessary `!$omp target update from(u, vh, abs_vort, h_q, q)` directives
   preceding each of the three branches, once they're `do concurrent` and no longer need a host
   round-trip.

**Scope note, consistent with the no-k-fold decision's framing:** this is a targeted fix for a
specific, diagnosed obstacle (missing `pure`) in `CorAdCalc` specifically, not a general
"always add `pure` and hope" policy — the same reasoning (check whether an impure-procedure-call
is actually the blocker, verify against the real code) should be applied fresh to any other
entry point where a similar serial-loop-next-to-a-subroutine-call pattern shows up.

**Where this lands in the split:** since this only affects the WENO branches, it's scoped to
whatever subroutine ends up containing them post-split — `CorAdv_weno`, per the structure below.
Do this as part of Stage 1, when `CorAdv_weno` is authored, not as a separate later pass.

## `CoriolisAdv_CS` — bundle by precedent (no fresh Step 3 needed)

33 fields (`MOM_CoriolisAdv.F90:34-100`, private): 11 scalar config/physics fields
(`initialized`, `Coriolis_Scheme`, `KE_Scheme`, `KE_use_limiter`, `PV_Adv_Scheme`,
`F_eff_max_blend`, `wt_lin_blend`, `no_slip`, `bound_Coriolis`, `Coriolis_En_Dis`,
`weno_velocity_smooth`), **zero allocatable arrays**, 2 nested pointers (`Time`, `diag`), and 20
`id_*` diagnostic handles. 20/33 = 61% diagnostic-ID dead weight, same shape as
`barotropic_CS`/`vertvisc_CS` — **applying that precedent directly**: `create_config_bundle_type`,
physics fields only (the 11 scalars), excluding the 20 `id_*` handles and the 2 nested pointers
(`Time`, `diag` stay direct fields). Given only 11 fields, this is likely a single small bundle
rather than several purpose-built ones — `create_config_bundle_type`'s own call. Shared 5 files
repo-wide, all opaque outside `MOM_CoriolisAdv.F90` (4 dynamics drivers holding/passing it, plus
the definer) — confirmed private, not a union candidate.

## `OBC`, `AD`, `Waves`, `pbv` — see `shared_type_unions.md`

This tree's contributions to the shared unions:
- **`OBC`**: `number_of_segments` (already unioned), plus new top-level `vorticity_config` and
  new per-segment fields `on_pe`, and `HI%IedB`/`%JedB` (beyond the `IsdB`/`JsdB`/`isd`/`ied`
  already unioned from other trees) — `is_N_or_S`/`is_E_or_W`/`direction`/`tangential_vel`/
  `tangential_grad` were already unioned from `horizontal_viscosity`/`continuity`/`vertvisc`, no
  new fields there.
- **`AD`** (`accel_diag_ptrs`): new fields `rv_x_u`/`rv_x_v`, `gradKEu`/`gradKEv` — genuine
  computational output storage (written directly, not just forwarded), same treatment as every
  other tree's `ADp`/`AD` usage.
- **`Waves`**: promoted from tree-scoped (`vertvisc` only) to a union — see
  `shared_type_unions.md` for the corrected 10-file count (not 14) and full field list
  (`us_x`/`us_y` shared with `vertvisc`; `Stokes_VF`/`Passive_Stokes_VF` new from this tree).
- **`pbv`** (`porous_barrier_type`): new union entry — shared with `continuity_PPM.F90`'s
  `zonal_mass_flux`/`meridional_mass_flux`/`zonal_BT_mass_flux`/`continuity_adjust_vel` family,
  which already dereferences `pbv%por_face_areaU`/`por_face_areaV` directly but never converted
  the type (same leftover-shared-type situation as `BT_cont_type`/`OBC` before them). `CorAdCalc`
  touches the same two fields, not `por_layer_widthU`/`V`. Narrow (2 of 4 fields) — resolves as a
  union shadow directly, no Step 3 needed.

## Blockers, current as of this check (verified against source and `shared_type_unions.md`, this session)

Two real external-dependency blockers, plus unfinished survey work the doc itself already flags:

**Blocking (external dependencies):**

1. **The combined shared-infrastructure PR hasn't landed — same blocker as `btstep`.** `CorAdCalc`
   needs `OBC`/`AD`/`Waves`/`pbv` as union shadows. Verified directly: `pbv`
   (`porous_barrier_type`, `MOM_variables.F90:357-364`) is still 100% raw allocatable arrays
   (`por_face_areaU`/`por_face_areaV`/`por_layer_widthU`/`por_layer_widthV`); no shadow container
   type exists anywhere in the source tree for any of the four (grepped repo-wide for the obvious
   naming pattern, zero matches); `MOM_CoriolisAdv.F90` itself still has 141 raw `OBC%`/`AD%`/
   `Waves%`/`pbv%` dereferences. This is the same combined PR `btstep.md` is also waiting on, not
   an independent piece of work — landing it unblocks both plans' Stage 2 at once.
2. **`Waves`'s optional-struct status is separately unresolved, even once the shadow lands.**
   `shared_type_unions.md`'s own tracking note explicitly names "`vertvisc`'s and `CorAdCalc`'s
   `Waves` (`optional, pointer` in both)" as one of the still-open "optional struct dummy →
   `bind(C)`-ready" instances — no sibling skill covers this. A second, independent gap on top of
   item 1, specific to `Waves`.

**Not external blockers, but real unfinished work — Stage 1 can't just mechanically execute
without these being settled first (both already flagged in this doc, restated here so they're
not missed alongside the blockers above):**

3. **The setup→per-scheme subroutine interface isn't fully enumerated** — "which of setup's ~15
   outputs each per-scheme subroutine actually needs as a new dummy" is explicitly left for
   Stage 1 to work out, not resolved by this survey (only `q`/`abs_vort` confirmed necessary so
   far).
4. **`gradKE`'s split-or-not is flagged for confirmation, not decided** — default is "leave
   unsplit," but the doc says this needs explicit confirmation rather than being assumed.

**Downstream, Phase-3-stage item, not a Phase-2 blocker:** whether/how `generate_cpp_bridge`
handles the WENO/UP3 family's fixed-size (non-container) array dummies is still unresolved — see
"The WENO/UP3 kernel family — not container targets" above. Doesn't block Phase 2 on this tree.

## Step 2 — target classification (fixed-rule items)

| Target | Classification | Skill | Notes |
|---|---|---|---|
| `u`, `v`, `h`, `uh`, `vh`, `CAu`, `CAv` (`CorAdCalc`'s own, 3-D `SZI_`/`SZJ_`/`SZK_`-shaped) | raw array dummies | `convert_array_containers` | Standard. Note `gradKE` receives 2-D *slices* of these (`u(:,:,k)`, etc.) — once containerized, this array-section-passing pattern needs the container's `%view` to support slicing; flag for Stage 1/5 execution to handle carefully, not a new decision. |
| `gradKE`'s own `u`, `v`, `h`, `KE`, `KEx`, `KEy` (2-D) | raw array dummies | `convert_array_containers` | Standard. |
| WENO/UP3 kernel family's fixed-size array dummies (`q4`, `q6`, `q8`, `h4`/`h6`/`h8`, `u4`/`u6`/`u8`, `w0`-`w3`, `p0`-`p3`, etc.) | fixed-size stencil arrays | **not a container target** — leave as plain Fortran arrays | See dedicated section above. |
| `G`, `GV` | shared grid/vertical-grid types | `convert_array_containers`'s own drop mechanism | Not a separate decision. |
| `US` | shared scaling type | same drop mechanism | Used directly in `CorAdCalc` itself (`US%m_to_L`, `US%m_s_to_L_T`); the WENO/UP3 kernel family takes no derived-type dummies at all (confirmed — plain reals/logicals/fixed arrays only). Check `gradKE`'s own `US` usage during execution. |
| `OBC`, `AD`, `Waves`, `pbv` | shared, union | `create_shadow_container_type`, union scope | See `shared_type_unions.md`. `Waves` blocked on the optional-struct open item. |
| `CS` (`CoriolisAdv_CS`) | private, 33 fields | `create_config_bundle_type`, physics-fields-only | See dedicated section above. |

## Phase 2 execution order

1. **TreeRoot split** — rename `CorAdCalc`→`CorAdCalc_TR`, author `CorAdCalc` wrapper, **and**
   split the body into `CorAdv_setup`/`CorAdv_sadourny`/`CorAdv_arakawa`/`CorAdv_robust_enstro`/
   `CorAdv_weno`/`CorAdv_finalize_diagnostics` per the split decision above. `gradKE` stays
   unsplit by default (flagged for confirmation). **While authoring `CorAdv_weno`**: declare the
   WENO/UP3 kernel family `pure`, convert its three `Coriolis_Scheme` branches' serial
   `do j; do I` loops to `do concurrent`, and drop the now-unnecessary
   `!$omp target update from(...)` directives — see the dedicated section above.
2. **`create_shadow_container_type`** — `OBC`/`AD`/`Waves`/`pbv`'s type definitions are built once
   by the combined shared-infrastructure PR (`shared_type_unions.md`), not here. This stage's own
   work is just the wrapper-side glue — instantiate each shadow from `CorAdCalc_TR`'s own
   dummies, use it, copy back.
3. **`create_config_bundle_type`** — `CoriolisAdv_CS`, once (informed by the union of fields
   touched across `CorAdCalc`'s new per-scheme subroutines and `gradKE`).
4. **Optional-array containerization** — none needed; `CorAdCalc`'s only optional dummy
   (`Waves`) is a struct, not an array, and the WENO/UP3 family's `u4`/`u6`/`u8`/`shelf`-style
   optionals are on fixed-size or scalar dummies outside this item's scope anyway.
5. **`convert_array_containers` — downward pass**, root to leaves, per the new per-scheme
   subroutine structure.
6. **`convert_array_containers` — upward pass**, leaves to root, G/GV/US-drop decisions.
7. **`convert_locals_to_containers`**, per subroutine once dummies are stable. **Do not
   3D-promote the 18 neighbor-dependent 2D scratch locals** per the no-k-fold decision — keep
   them 2D (or 2D containers), reused per k-iteration exactly as today.
8. **`convert_present_to_associated`** — none needed for arrays/scalars in this tree; `Waves`'s
   optional-struct status is the open item, not an ordinary present/associated conversion.
9. **`hoist_container_marshalling`**, once, at `CorAdCalc_TR`.

## Phase 3 wave order (provisional for the split subroutines, final for the pre-existing kernel
family)

**Final (unaffected by the split, modulo the fixed-size-array bridging open item above):**
- **Wave 1** (leaves): `fac_fn`, `weno_three_weight`, `weno_three_reconstruction_0/1`,
  `weno_five_weight_0/1/2`, `weno_five_reconstruction_0/1/2`, `weno_seven_weight_0/1/2/3`,
  `weno_seven_reconstruction_0/1/2/3`, `UP3_reconstruction`, `UP3_Koren_limiter_reconstruction`.
- **Wave 2**: `weno_three_h_weight_reconstruction`, `weno_five_h_weight_reconstruction`,
  `weno_seven_h_weight_reconstruction` (each calls wave-1 helpers + `fac_fn`); `gradKE` (calls
  `UP3_reconstruction`/`UP3_Koren_limiter_reconstruction`, both wave 1) — unless split, in which
  case `gradKE`'s own per-`KE_Scheme` pieces would need their own wave assignment.

**Provisional (depends on Stage 1's actual split):**
- **Wave 3 (est.)**: `CorAdv_setup` (no in-tree callees), `CorAdv_sadourny` (likely no in-tree
  callees), `CorAdv_arakawa` (likely none), `CorAdv_robust_enstro` (likely none).
- **Wave 4 (est.)**: `CorAdv_weno` (calls the wave-2 WENO drivers), `CorAdv_finalize_diagnostics`.
- **Wave 5 (est., root, last)**: `CorAdCalc_TR` (calls `CorAdv_setup`, the per-scheme dispatch,
  `gradKE`, and `CorAdv_finalize_diagnostics`). Wrapper never bridged.

## Branch

`claude_coradcalc_calltree`, created once before Phase 2 Stage 1.
