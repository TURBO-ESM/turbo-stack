# Shared derived-type unions across `convert_calltree` campaigns

Authoritative source for every derived type needed, container-based, by more than one actively-
converted entry point. Extracted from `btstep.md`/`horizontal_viscosity.md` when a third tree
(`vertvisc`/`vertvisc_coef`) needed the same types and per-file cross-referencing started
straining. **Every per-entry-point plan file references this file for these types instead of
duplicating or pointing at each other.** Update this file, not a per-entry-point plan, when a
new tree needs one of these types.

## Execution: one combined infrastructure PR, ahead of every entry point (user decision)

Every shadow type in this file — `ADp`, `OBC`, `forces`, `VarMix`, `Waves`, `pbv`, `tv`,
`vertvisc_type`, `MEKE` via `create_shadow_container_type`; `tracer_registry_type`/`tracer_type`
via its own hand-authored decomposition (no sibling skill covers it, see its section above);
`BT_cont_type` via its own wholesale-conversion route (see below) — gets built **once**, on **one
dedicated branch, landing as one combined PR**, before any entry point's own Phase 2 runs, not as
a side effect of whichever entry point happens to reach Phase 2 Stage 2 first. Same principle
across all three mechanisms, just different tooling per type.

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

### Stages within the combined PR

One branch, one PR, but **not** one unstaged commit — same commit/verify/push/CI-check/stop
discipline as every entry-point plan's own Phase 2, applied here because ~10 types across 3
different mechanisms is too much surface to verify in one shot, and because a real dependency
exists between two of them (below).

1. **`BT_cont_type` — wholesale conversion.** Independent of everything else in this file (its
   own mechanism, its own five files — `MOM_variables.F90`, `MOM_continuity_PPM.F90`,
   `MOM_barotropic.F90`, `MOM_dynamics_split_RK2.F90`, `MOM_dynamics_split_RK2b.F90`). See
   `btstep.md`'s "BLOCKING PREREQUISITE" section for the full field list and reasoning — that
   section's "track it as its own piece of work" now means "Stage 1 here," not a separately
   scheduled effort.
2. **`tracer_registry_type`/`tracer_type` — hand-authored decomposition.** Must land **before**
   Stage 3, not just before entry points — `OBC`'s `segment(:)%tr_Reg` field is a pointer to a
   nested `tracer_registry_type`, so `OBC`'s shadow can't marshal that field until `tracer_type`'s
   own per-field container decomposition already exists. This is the one genuine ordering
   dependency in this file; every other stage is independent of every other.
3. **`OBC` — union shadow.** Depends on Stage 2 (above). Confirm the full current field list
   (top-level + per-segment, including the `tr_Reg` nesting) against this file's `OBC` section
   before building, since it has grown substantially across trees.
4. **`ADp` — union shadow.** Mutually independent of every other remaining type. ~20 fields
   across 5 trees (`btstep`, `horizontal_viscosity`, `vertvisc`, `CorAdCalc`, `PressureForce`) —
   confirm the current full list against this file's `ADp` section before building.
5. **`tv` — union shadow.** Independent. 7 fields touched (`SpV_avg`, `T`, `S`, `P_Ref`,
   `eqn_of_state`, `varT`, `p_surf`) out of the widest-shared type in the campaign (101 files) —
   `eqn_of_state` stays an opaque handle, no EOS-specific work needed here.
   *(`ADp` and `tv` ordered first among the remaining types since `PressureForce` — the
   recommended next entry-point plan to execute — needs both and nothing else in this group.)*
6. **`forces` — union shadow.** Independent, 5 fields, no open items.
7. **`vertvisc_type` — union shadow.** Independent, free promotion (no new fields beyond what
   `vertvisc_family` already fully specified) — the most mechanical stage in this group.
8. **`pbv` — union shadow.** Independent, 4 fields, no open items.
9. **`VarMix` — union shadow.** Independent. Moderate care needed: only ~14 of the underlying
   type's ~89 fields are touched — confirm the current list (grown substantially from
   `tracer_hordiff`) before carving out the shadow's field subset.
10. **`Waves` — union shadow.** Independent, but **not mechanical like 4-9** — still carries the
    unresolved "optional struct dummy" open item (`Waves` is `optional, pointer` in every
    consuming tree). Building this shadow means resolving, at least for this one type, how the
    shared build/copy-back API signals "not present" — genuine design work, not just authorship.
    Isolated in its own stage precisely so it doesn't hold up 4-9 while that gets worked out.
11. **`MEKE` — union shadow.** Independent, but has its own pre-check: `tracer_hordiff`'s 2 needed
    fields (`Kh`, `KhTr_fac`) haven't been confirmed against `horizontal_viscosity`'s "most/all 15
    fields" — itemize `horizontal_viscosity`'s exact field list first, so this shadow is built
    complete on this pass rather than needing a later widening. Isolated in its own stage for the
    same reason as `Waves`.
12. **Whole-package verification, before the final commit.** Cross-check every shadow's field list
   against what every entry-point plan (`btstep.md`, `horizontal_viscosity.md`,
   `vertvisc_family.md`, `CorAdCalc.md`, `PressureForce.md`, `set_viscosity_family.md`,
   `advect_tracer.md`, `tracer_hordiff.md`) actually records needing — confirm nothing is missing,
   confirm each shadow's build/copy-back API is documented well enough for an entry-point's own
   wrapper-side glue to consume it without re-deriving anything.

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

## `ADp` (`accel_diag_ptrs`) — union shadow

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

## `OBC` (`ocean_OBC_type`/`OBC_segment_type`) — union shadow

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

## `forces` (`mech_forcing`) — union shadow

Shared (15 files outside any conversion campaign).

| Field | Needed by | Notes |
|---|---|---|
| `taux`, `tauy` | btstep, vertvisc | `pointer`, no `associated()` guard in either tree — plain container view, no check added (see `btstep.md`'s reasoning) |
| `rigidity_ice_u`, `rigidity_ice_v` | btstep | `pointer`, `associated()`-guarded — `%associated()`-checked container |
| `frac_shelf_u`, `frac_shelf_v` | vertvisc_coef, set_viscous_ML | not yet confirmed pointer-vs-allocatable-vs-guarded; check before finalizing this field's shadow treatment |
| `omega_w2x` | vertvisc | not yet confirmed pointer-vs-allocatable-vs-guarded; same caveat |
| `p_surf` | set_viscous_ML | not yet confirmed pointer-vs-allocatable-vs-guarded; same caveat |

## `VarMix` (`VarMix_CS`) — union shadow (upgraded from tree-scoped to union)

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

## `Waves` (`wave_parameters_CS`) — promoted to union (was tree-scoped to `vertvisc` only)

`vertvisc` and `CorAdCalc` both need this now. **Correction to the file count**: `vertvisc`'s
own survey said 14 files repo-wide; `CorAdCalc`'s survey, done more carefully (case-insensitive,
since the type is actually spelled `wave_parameters_CS` lowercase at its definition), found
**10 files**. Use 10 going forward, not 14.

| Field | Needed by |
|---|---|
| `us_x`, `us_y` | vertvisc, CorAdCalc |
| `Stokes_VF`, `Passive_Stokes_VF` | CorAdCalc |

`Waves` is `optional, pointer` in both signatures — extends the optional-struct open item below.

## `pbv` (`porous_barrier_type`) — new union (first appearance, already shared with a
pre-existing, already-converted campaign)

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

Narrow enough (all 4 of 4 fields, still just one small type) to resolve as a union shadow directly, no Step 3 needed — same
shape as `OBC`'s reasoning (shared with an already-completed campaign that never converted the
type itself, not a candidate for wholesale conversion the way `BT_cont_type` was, since
continuity() adopting this shadow later is optional/non-blocking, same as `OBC`).

## `tv` (`thermo_var_ptrs`) — promoted to union (was tree-scoped to `vertvisc_coef`/`vertvisc_remnant`)

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

## `vertvisc_type` (the `visc` dummy) — promoted to union (free — no new fields)

25 fields (`MOM_variables.F90:258-313`), shared 20 files. First needed by `vertvisc`/
`vertvisc_coef`/`vertvisc_remnant` (tree-scoped at the time: `Ray_u/v`, `taux_shelf`/`tauy_shelf`,
`Kv_bbl_u/v`, `bbl_thick_u/v`, `tbl_thick_shelf_u/v`, `Kv_tbl_shelf_u/v`, `Kv_slow`,
`nkml_visc_u/v`). `set_viscous_BBL` (`Ray_u/v`, `bbl_thick_u/v`, `Kv_bbl_u/v`) and
`set_viscous_ML` (`Kv_tbl_shelf_u/v`, `nkml_visc_u/v`, `taux_shelf`/`tauy_shelf`,
`tbl_thick_shelf_u/v`) need nothing beyond what's already there — a completely free promotion,
no field-list changes required, purely a bookkeeping move from tree-scoped to union.

**New field from `tracer_hordiff`**: `h_ML`, needed by that tree's own in-tree callees
`hor_bnd_diffusion` and `neutral_diffusion_calc_coeffs` — not by `tracer_hordiff`'s own body,
which forwards the `visc` dummy opaquely (same "only the true consumer needs the shadow" pattern
already noted above for `ADp`/`write_u_accel`).

## `MEKE` (`MEKE_type`) — promoted to union (was tree-scoped to `horizontal_viscosity` alone)

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
optional+pointer combo). `vertvisc`'s and `CorAdCalc`'s `Waves` (`optional, pointer` in both) is
the same category. `set_dtbt`'s `BT_cont` (`optional, pointer`, confirmed opaque — see
`btstep.md`) is another instance. No existing sibling skill covers "optional struct dummy →
bind(C)-ready" — still unresolved, still deliberately not guessed through. Resolve once,
wherever it's next picked up, and update this note for every plan file with an instance.
