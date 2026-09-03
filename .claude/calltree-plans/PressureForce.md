# Call-tree conversion plan: `PressureForce`

Entry point: `PressureForce`, `submodules/MOM6/src/core/MOM_PressureForce.F90:43-86`.
Produced by Phase 1 of `convert_calltree`. Read by Phase 2 and Phase 3.
Cross-reference: `.claude/calltree-plans/shared_type_unions.md` — `tv`, `ADp` grown by this
tree (both deferred as of this session — see "Mechanism decision 2" there); the EOS
runtime-polymorphism blocking prerequisite this tree makes unavoidable to face.

No pre-existing audit doc existed for this entry point — surveyed fresh, though the file
comparison tables in `hor_visc_call_tree_audit.md`/`vert_friction_call_tree_audit.md` had
already flagged `Set_pbce_Bouss`/the pressure solver as reaching the EOS layer.

**Base plan — double_gyre_unsplit.** The FV/Montgomery × Boussinesq dispatch inside
`PressureForce` isn't gated by `SPLIT` at all — same code path either way. Only the call
frequency differs: twice per step under the split dynamics core (predictor + corrector) vs. once
per step under unsplit RK2. Coverage confirms this is a wash, not a simplification
(`MOM_PressureForce_FV.F90`: 21.2% vs. 20.6%; the Montgomery-form physics subroutines are already
0%-covered under **both** configs, since `double_gyre` uses the FV form). No patch needed.

**Shared-infrastructure status, updated this session: fully clear.** `tv` and `ADp` — this tree's
only two ties to `shared_type_unions.md`'s combined PR — were both deferred (confirmed
PASSED-BUT-INERT under both double_gyre configs: `ENABLE_THERMODYNAMICS=False` means
`tv%eqn_of_state`/`T`/`S` are never populated; `ADp`'s diagnostics aren't requested — see that
file's "Mechanism decision 2"). This tree now has **zero remaining `create_shadow_container_type`
dependencies** — already wasn't blocked by EOS either (see below). Nothing left to wait on from
shared infrastructure at all. **This holds for double_gyre_unsplit and double_gyre only** — `tv`
re-activates under the `benchmark` patch (`ENABLE_THERMODYNAMICS=True` there), and this tree
genuinely dereferences it pervasively, so `benchmark` reintroduces a real `tv` shadow dependency.
See `plan/calltree_patch_summary_benchmark.md`.

## Hard precondition checks

- Callers confirmed: same 4 dynamics-core files as every other entry point (`MOM_dynamics_unsplit.F90`
  x3, `MOM_dynamics_unsplit_RK2.F90` x1, `MOM_dynamics_split_RK2b.F90` x2, `MOM_dynamics_split_RK2.F90`
  x2 — 8 call sites). No other file calls `PressureForce`.
- Shared-descendant check: `PressureForce_Mont_Bouss`/`_nonBouss`, `PressureForce_FV_Bouss`/
  `_nonBouss`, `Set_pbce_Bouss`/`_nonBouss` all confirmed zero callers outside this tree — but
  `Set_pbce_Bouss` has **two in-tree callers** (`PressureForce_Mont_Bouss` line 578 *and*
  `PressureForce_FV_Bouss` line 1944), same for `Set_pbce_nonBouss` (`PressureForce_Mont_nonBouss`
  line 328 and `PressureForce_FV_nonBouss` line 878) — an internal fan-in within the tree. Since
  both callers of each are in scope this phase (see below), this is not a complication —
  `Set_pbce_Bouss`/`_nonBouss` just each get converted once and called consistently from both.
- `tv`, `ADp` are shared with other actively-converted trees — see `shared_type_unions.md`. Both
  **deferred this session** (confirmed PASSED-BUT-INERT under both double_gyre configs) —
  reclassified to leave alone/view-marshal, no shadow built now.
  `ALE_CS`, `SAL_CS`, `tides_CSp`'s type are shared far more widely (11+ files) but confirmed
  fully opaque here — leave-alone, not a shadow candidate.
- `MOM_EOS.F90`/`MOM_density_integrals.F90` are the widest-shared subsystem touched by any tree
  in this campaign (59 files, 9 polymorphic EOS implementations) — see the blocking-prerequisite
  section below.

## Step 1d — wrapper case

**Case 3.** `PressureForce` is one subroutine, called directly under its own name —
`public PressureForce, PressureForce_init` — no wrapper, no alias. Unlike every other Case-3
entry point in this campaign, `PressureForce`'s own body is nearly empty: it's a **thin 4-way
dispatcher**, not a monolith:
```fortran
if (CS%Analytic_FV_PGF) then
  if (GV%Boussinesq) then ; call PressureForce_FV_Bouss(...)
  else                    ; call PressureForce_FV_nonBouss(...) ; endif
else
  if (GV%Boussinesq) then ; call PressureForce_Mont_Bouss(...)
  else                    ; call PressureForce_Mont_nonBouss(...) ; endif
endif
```
Phase 2 Stage 1 renames `PressureForce`→`PressureForce_TR` and authors a new `PressureForce`
wrapper (pure pass-through, matching the external signature exactly, no `bind(C)`).
`PressureForce_TR` retains the dispatch logic above. **Revised scope decision (below) means all
four branches convert together this phase** — so, unlike an earlier version of this plan that
scoped out the FV form, `PressureForce_TR`'s dispatcher calls uniformly-converted code on every
path; there's no runtime-conditional raw/bridged split to special-case in Phase 3.

## External signature (frozen — do not change)

`PressureForce(h, tv, PFu, PFv, G, GV, US, CS, ALE_CSp, ADp, p_atm, pbce, eta)` —
`MOM_PressureForce.F90:43-62`. Optional: `pbce`, `eta` (both arrays). `ALE_CSp`, `ADp`, `p_atm`
are all bare `pointer` dummies with no `intent`/`optional` keyword — presence emulated via
`associated()`, same idiom already established for `OBC` elsewhere in this campaign. `CS` is
`type(PressureForce_CS), intent(inout)` — a small wrapper type nesting `PressureForce_FV`
(`type(PressureForce_FV_CS)`) and `PressureForce_Mont` (`type(PressureForce_Mont_CS)`), plus
(presumably) the `Analytic_FV_PGF` dispatch flag — full field list not separately surveyed,
likely trivial; confirm during Stage 1.

## Scope decision — revised: both Montgomery and FV forms, together (user decision)

**Original decision (superseded): Montgomery now, FV deferred to a later pass.** Revisited and
reversed. The original rationale was that the FV form (`PressureForce_FV_Bouss`/`_nonBouss`,
1979 lines, 39-field private CS, ~23 EOS call sites woven throughout, plus `ALE`/
`calc_tidal_forcing_legacy` dependencies FV alone reaches) is far larger/more complex than the
Montgomery form (570 lines, 17-field CS, ~8 EOS call sites) — true, but deferring it created two
real complications that don't exist if both forms convert together:

1. **`Set_pbce_Bouss`/`Set_pbce_nonBouss` would have had to stay raw too**, purely because
   they're shared between the two forms — not because of anything about their own complexity.
   That's an artificial constraint, not a real scoping win.
2. **`PressureForce_TR`'s dispatcher would have ended up calling bridged code on some runtime
   paths and genuinely raw legacy code on others** (`Analytic_FV_PGF`-dependent) — a mixed
   converted/unconverted tree under one root, unlike every other entry point in this campaign,
   and a real headache for `generate_cpp_bridge`'s own precondition check in Phase 3.

**Decision (user, this session): convert/bridge all four branches — and `Set_pbce_Bouss`/
`Set_pbce_nonBouss` — together, in this same campaign.** More upfront work (the FV form
specifically), but it removes both complications above and matches the uniform-tree pattern
every other entry point in this campaign already follows. The EOS/`calc_SAL`/`ALE`
leave-external decisions below apply the same stopgap treatment regardless of which form a call
site sits in, so scope wasn't actually buying isolation from those decisions either — deferring
FV was mostly just deferring FV's own size, not deferring EOS exposure (Montgomery already
reaches EOS directly too).

## EOS runtime polymorphism — blocking prerequisite (see `shared_type_unions.md`)

**Decision (user, this session): stop deferring EOS tree by tree — it needs a real, dedicated
solution, tracked as its own piece of work, not resolved inside this plan.** Full reasoning,
scope (59 files, 9 implementations), and the list of every entry point that reaches it (including
ones outside this campaign entirely, discovered as a side effect — `MOM.F90`'s main step,
`MOM_MEKE.F90`) now live in `shared_type_unions.md`'s dedicated section — not duplicated here.

**What this means for *this* plan's immediate Phase 2/3, pending that solution:** every EOS-family
call anywhere in this tree — `calculate_density`/`calculate_density_derivs` (inside
`Set_pbce_Bouss`/`Set_pbce_nonBouss` and directly inside `PressureForce_Mont_Bouss`/`_nonBouss`),
plus `calculate_density`/`calculate_spec_vol`/`EOS_domain`/`int_density_dz`/
`int_density_dz_generic_plm/ppm`/`int_specific_vol_dp`/`int_spec_vol_dp_generic_plm`/
`diagnose_mass_weight_p/Z` (inside `PressureForce_FV_Bouss`/`_nonBouss`, ~23 call sites) —
stays completely untouched, raw Fortran, marshalled via container `%view` at the call site, the
same stopgap used everywhere else in the campaign, until the dedicated EOS work lands. Now that
both forms are in scope, this stopgap applies to the full ~32 call sites across the whole tree,
not just Montgomery's ~8. This is *not* the long-term answer, just what keeps this entry point's
own conversion moving without waiting on a separate, larger effort.

## `calc_SAL`/`calc_tidal_forcing`/`ALE` family — leave external, same reasoning as EOS

**Decision (user, this session): leave `calc_SAL`, `calc_tidal_forcing`/`calc_tidal_forcing_legacy`,
and the `TS_*_edge_values` family external/opaque, same as EOS — for both forms now.** Confirmed
exclusive to this tree (except `TS_PLM_edge_values`, also called from
`MOM_state_initialization.F90`), but not leaves — `calc_SAL` reaches into
`MOM_self_attr_load.F90`'s own spherical-harmonics transform (`spherical_harmonics_forward/
inverse`, `pass_var`, `order2index`); the `TS_*` family (relevant now that FV is in scope) reaches
into `MOM_ALE.F90`'s PLM/PPM/WLS reconstruction machinery (`ALE_CS` shared 11 files). Chasing
either would risk the same kind of far-reaching expansion as EOS — `MOM_self_attr_load.F90` also
holds `SAL_CS`, already forwarded opaquely by `btstep`'s tree into `scalar_SAL_sensitivity`;
touching `SAL_CS`'s own fields here would create a new shared-descendant conflict with that
already-recorded plan. Not pursued for the same reason EOS isn't: keep this already-large
campaign's scope bounded to the `PressureForce_*.F90` files themselves — bringing FV into scope
changes *how many* call sites get this treatment, not the treatment itself.

## Full descendant list (all six subroutines now in scope)

| Subroutine | Direct in-tree callees | Notes |
|---|---|---|
| `PressureForce_Mont_nonBouss` (70-376) | `Set_pbce_nonBouss` (in-tree, converts too) | `calc_SAL`/`calc_tidal_forcing` stay external |
| `PressureForce_Mont_Bouss` (385-647) | `Set_pbce_Bouss` (in-tree, converts too) | `calc_SAL`/`calc_tidal_forcing` stay external |
| `Set_pbce_nonBouss` (774-883) | none | EOS calls (`calculate_density`, `calculate_density_derivs`) stay external |
| `Set_pbce_Bouss` (651-770) | none | same |
| `PressureForce_FV_nonBouss` (134-949) | `Set_pbce_nonBouss` (in-tree, shared with Montgomery form) | EOS calls, `calc_SAL`, `calc_tidal_forcing`/`_legacy`, `TS_*_edge_values` all stay external |
| `PressureForce_FV_Bouss` (959-2121) | `Set_pbce_Bouss` (in-tree, shared with Montgomery form) | same |

## `tv`, `ADp` — see `shared_type_unions.md` (both DEFERRED this session)

Both grown by this tree, and both forms' full footprint mattered (not just Montgomery's) while
they were active — recorded here as reference, not current work. `tv` was the significant one:
**every subroutine in this tree genuinely dereferences `tv%T`/`tv%S`/`tv%P_Ref`/`tv%eqn_of_state`
directly** (plus `tv%varT` in `PressureForce_FV_Bouss` specifically) — the first tree in the whole
campaign where `tv` wasn't purely opaque or a one-field convenience shadow, which is what promoted
it from `vertvisc_coef`'s narrow tree-scoped shadow to a full union. `ADp` gained
`sal_u`/`sal_v`/`tides_u`/`tides_v` — used in `PressureForce_FV_Bouss`/`_nonBouss`'s
diagnostics-posting blocks. **Both confirmed PASSED-BUT-INERT under both double_gyre configs**
(`ENABLE_THERMODYNAMICS=False`; the `sal_u`/`tides_u`-feeding diagnostics aren't requested) — no
shadow being built now; the wrapper keeps dereferencing both types raw, exactly as today.

## `PressureForce_Mont_CS` and `PressureForce_FV_CS` — bundle by precedent (no fresh Step 3 needed)

**`PressureForce_Mont_CS`**: 17 fields (`MOM_PressureForce_Montgomery.F90:35-57`, private): 3
scalar logical (`initialized`/`calculate_SAL`/`tides`), 2 scalar real (`Rho0`/`GFS_scale`), 6
`id_*` diagnostic handles, 2 allocatable 3-D arrays (`PFu_bc`/`PFv_bc`), 4 nested pointers
(`Time`/`diag`/`SAL_CSp`/`tides_CSp`). Small and clean, same shape as `continuity_PPM_CS`.

**`PressureForce_FV_CS`**: 39 fields (`MOM_PressureForce_FV.F90:42-109`, private): 22 scalar
config/physics fields, 13 `id_*` diagnostic handles, 4 nested pointers (`Time`/`diag`/
`SAL_CSp`/`tides_CSp`), 0 allocatable arrays. Larger than the Montgomery CS but the same shape —
scalar-dominated, no arrays, a substantial `id_*` block.

Both: `create_config_bundle_type`, physics fields only (Mont: the 5 scalars + 2 arrays; FV: the
22 scalars), excluding every `id_*` handle and the 4 nested pointers in each (which stay direct
fields — `SAL_CSp`/`tides_CSp` confirmed fully opaque, `Time`/`diag` opaque by the established
pattern). Two separate `create_config_bundle_type` invocations, one per CS type.

## Step 2 — target classification (fixed-rule items, all six subroutines)

| Target | Classification | Skill | Notes |
|---|---|---|---|
| `h`, `PFu`, `PFv` (`PressureForce`'s own); `pbce`, `eta` (optional); `e` (`Set_pbce_Bouss`), `p` (`Set_pbce_nonBouss`); `rho_star`/`alpha_star` (optional, `Set_pbce_*`) | raw/optional array dummies | `convert_array_containers` (+ `convert_present_to_associated` for the optionals) | Standard. |
| `p_atm` (bare `pointer`, no `intent`/`optional`) | raw array dummy, pointer-presence idiom | `convert_array_containers` | Same pattern as several `btstep` dummies (`eta_PF_start`, `taux_bot`, etc.) — presence via `%associated()`, not `present()`. |
| `G`, `GV` | shared grid/vertical-grid types | `convert_array_containers`'s own drop mechanism | Not a separate decision. |
| `US` | shared scaling type | same drop mechanism | Confirmed **never dereferenced at all** in `Set_pbce_Bouss`/`Set_pbce_nonBouss`; lightly dereferenced elsewhere (one field in `PressureForce_Mont_Bouss`/`_nonBouss`, a handful of scale-factor keyword args in `PressureForce_FV_Bouss`/`_nonBouss`). Flag every unused instance for the upward-pass drop decision. |
| `tv`, `ADp` | shared, DEFERRED | **leave alone — view-marshal at call site** (not `create_shadow_container_type` — moved out this session) | See `shared_type_unions.md`'s "Mechanism decision 2." Both confirmed PASSED-BUT-INERT under both double_gyre configs. |
| `ALE_CSp` | confirmed opaque, shared 11 files | leave alone | Forwarded whole into `TS_*_edge_values` (itself left external) by `PressureForce_FV_Bouss`/`_nonBouss`; never dereferenced. |
| `SAL_CSp`, `tides_CSp` | confirmed opaque throughout the whole campaign (also opaque in `barotropic_CS`) | leave alone | No shadow needed anywhere. |
| `CS` (`PressureForce_Mont_CS`, `PressureForce_FV_CS`) | private, 17 and 39 fields respectively | `create_config_bundle_type`, physics-fields-only, two separate invocations | See dedicated section above. |
| EOS-family calls (`calculate_density`, `calculate_spec_vol`, `calculate_density_derivs`, `EOS_domain`, `int_density_dz*`, `int_specific_vol_dp`, `int_spec_vol_dp_generic_plm`, `diagnose_mass_weight_p/Z`) | pervasive, central to computation, ~32 sites across the whole tree | leave alone — view-marshal via the shared marshalling helper | Design now complete (`EOS_bridge_design.md`) rather than a stopgap: no changes to `MOM_EOS.F90` are required for this tree's Phase 2, and `PressureForce` is exactly where the shared marshalling helper's diff-reduction payoff matters most — ~32 call sites collapse to ~32 one-line helper calls instead of ~32 repeated unwrap/rewrap blocks. Helper is built once in the combined infrastructure PR, not authored here. |
| `calc_SAL`, `calc_tidal_forcing`/`_legacy`, `TS_PLM/PPM/PLM_WLS_edge_values` | exclusive (mostly) but not leaves | leave alone — view-marshal at call site | See dedicated section above. |

## Phase 2 execution order (all six subroutines)

1. **TreeRoot split** — rename `PressureForce`→`PressureForce_TR`, author `PressureForce`
   wrapper. Dispatch logic (4-way `if`) stays in `PressureForce_TR`'s body — now calls
   uniformly-converted code on every path, no special marshalling needed at the dispatch level
   itself.
2. **No `create_shadow_container_type` stage needed** — `tv`/`ADp` are deferred (see
   `shared_type_unions.md`'s "Mechanism decision 2"), so there's no shadow to build or wrapper-side
   glue to write for them; `PressureForce_TR` dereferences both types raw, exactly as the original
   code did.
3. **`create_config_bundle_type`** — `PressureForce_Mont_CS` and `PressureForce_FV_CS`, two
   separate invocations.
4. **Optional-array containerization** — `pbce`, `eta` (`PressureForce`/`Mont_*`/`FV_*` forms),
   `rho_star`/`alpha_star` (`Set_pbce_*`); default direction throughout — none of these cascade
   past this tree's own boundary.
5. **`convert_array_containers` — downward pass**, `PressureForce_TR` → all four
   `PressureForce_Mont_*`/`PressureForce_FV_*` subroutines → `Set_pbce_Bouss`/`Set_pbce_nonBouss`.
6. **`convert_array_containers` — upward pass**, G/GV/US-drop decisions across all six
   subroutines.
7. **`convert_locals_to_containers`**, per subroutine once dummies are stable.
8. **`convert_present_to_associated`** — `pbce`, `eta`, `rho_star`, `alpha_star`.
9. **`hoist_container_marshalling`**, once, at `PressureForce_TR`.

## Phase 3 wave order (all six subroutines)

- **Wave 1**: `Set_pbce_Bouss`, `Set_pbce_nonBouss` — leaves (their only calls are the
  externally-left EOS routines).
- **Wave 2**: `PressureForce_Mont_Bouss`, `PressureForce_Mont_nonBouss`, `PressureForce_FV_Bouss`,
  `PressureForce_FV_nonBouss` — each calls its respective wave-1 `Set_pbce_*` (everything else
  each of them calls is externally left, per the decisions above).
- **Wave 3 (root, last)**: `PressureForce_TR` — calls all four wave-2 subroutines, uniformly
  converted on every dispatch path. No mixed raw/bridged precondition concern this time.

The wrapper is never bridged.

## Branch

`claude_pressureforce_calltree`, created once before Phase 2 Stage 1.

## Follow-up work explicitly out of scope for this plan (tracked, not forgotten)

**The EOS dedicated solution is no longer open** — see `EOS_bridge_design.md`, now fully designed
(planning only, not yet implemented). "Leave alone, view-marshal via the shared helper" is the
*permanent* classification for every EOS call site in this tree, confirmed in that design's own
"Payoff" section: every shim's default mode is Fortran-truth, bit-identical, so nothing here needs
to change once the shared infrastructure PR and EOS's own bridging (a separate, not-yet-scheduled
effort) land. What's still genuinely out of scope for *this* plan: `TEOS10_EOS`'s own porting
effort, and the C++-side dispatch mechanism among the 8 bridged forms — neither affects how
`PressureForce` calls EOS.
