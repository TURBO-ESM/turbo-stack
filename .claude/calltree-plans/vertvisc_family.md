# Call-tree conversion plan: `vertvisc`, `vertvisc_coef`, `vertvisc_remnant`

Three entry points, `src/parameterizations/vertical/MOM_vert_friction.F90`, surveyed together in
one Phase 1 pass (user request) because all three share one private module control structure
(`vertvisc_CS`) and several derived types — doing them together avoids the exact
reconciliation problem (bundle/shadow decisions made in isolation, needing patching later when a
sibling entry point turns out to need the same type) that `btstep`/`horizontal_viscosity` hit
with `BT_cont_type`/`OBC`. Cross-reference: `.claude/calltree-plans/shared_type_unions.md` for
`OBC`, `ADp`, `forces`, `VarMix` (all grown by this tree too).

A fourth subroutine in this file, `vertvisc_limit_vel`, is **not** an independent entry point —
confirmed zero callers outside `MOM_vert_friction.F90`, called only from `vertvisc` itself. A
fifth, `vertFPmix`, is a genuine fourth public-ish entry point (uses the vendored CVMix library)
but was not requested and is confirmed **not called from any of the three trees below** — out of
scope, untouched.

## Hard precondition checks

- **Callers, corrected from the pre-existing audit.** `vertvisc` and `vertvisc_coef` are each
  called from all 4 dynamics-core files (`MOM_dynamics_unsplit_RK2.F90`,
  `MOM_dynamics_split_RK2b.F90`, `MOM_dynamics_unsplit.F90`, `MOM_dynamics_split_RK2.F90`) —
  matches the audit. **`vertvisc_remnant` is called from only 2 of the 4** —
  `MOM_dynamics_split_RK2b.F90` and `MOM_dynamics_split_RK2.F90` — the unsplit drivers never call
  it (makes sense: `visc_rem_u`/`visc_rem_v` are barotropic-remnant fractions, only meaningful
  for the split time-stepping schemes). The audit's claim of "same 4 files for all three" is
  wrong for `vertvisc_remnant` specifically — corrected here.
- No other file in the repo calls any of the three (confirmed, repo-wide grep).
- Shared-descendant check: `vertvisc_limit_vel`, `find_coupling_coef`, `find_coupling_coef_k`,
  `find_coupling_coef_gl90`, `write_u_accel`, `write_v_accel` all confirmed zero callers outside
  this file (the last two: zero callers outside `vertvisc_limit_vel` specifically). `find_ustar`
  (resolves to `find_ustar_mech_forcing`, `MOM_forcing_type.F90`) is **not** exclusive — called
  from 7+ other files (`MOM_mixed_layer_restrat.F90`, `MOM_bulk_mixed_layer.F90`,
  `MOM_diabatic_driver.F90` x3, `MOM_set_viscosity.F90`, `MOM.F90` x2) — see "leave alone" below,
  same treatment as `thickness_to_dz` in `horizontal_viscosity.md`.
- No runtime polymorphism anywhere (confirmed: zero `class(...)`/`select type` in the file).
- `vertFPmix`'s CVMix dependency (`cvmix_kpp_composite_Gshape`) doesn't touch any of these three
  trees — confirmed no call to `vertFPmix` from within `vertvisc`/`vertvisc_coef`/
  `vertvisc_remnant`'s bodies; it's called from a separate site in `MOM_dynamics_split_RK2.F90`.

## Step 1d — wrapper cases (three separate Case-3 splits)

All three are **Case 3** — distinct subroutines, called directly, no wrapper/alias. Phase 2
Stage 1 needs three separate rename+wrapper pairs:
1. `vertvisc` → `vertvisc_TR`, new `vertvisc` wrapper.
2. `vertvisc_coef` → `vertvisc_coef_TR`, new `vertvisc_coef` wrapper.
3. `vertvisc_remnant` → `vertvisc_remnant_TR`, new `vertvisc_remnant` wrapper.
None of the three wrappers are ever bridged. `vertvisc_limit_vel` is not an entry point and gets
no rename/wrapper of its own — it's an ordinary descendant of `vertvisc_TR`.

## External signatures (frozen — do not change)

- `vertvisc(u, v, h, forces, visc, dt, OBC, ADp, CDp, G, GV, US, CS, taux_bot, tauy_bot, fpmix, Waves)`
  — `MOM_vert_friction.F90:538-565`. Optional: `taux_bot`, `tauy_bot` (arrays), `fpmix` (plain
  scalar `logical`, not a struct), `Waves` (`optional, pointer` combo — extends the open item
  below). `OBC` is `pointer`, not `optional`, here (unlike `horizontal_viscosity`'s combo). `CS`
  has **no explicit `intent` at all** (bare `type(vertvisc_CS)`) — note for Stage 1, since every
  other dummy in this family does declare one.
- `vertvisc_coef(u, v, h, dz, forces, visc, tv, dt, G, GV, US, CS, OBC, VarMix)` —
  `MOM_vert_friction.F90:1301-1320`. **No optional dummies at all.** `OBC` is `pointer`, no
  `intent`. `CS` is `intent(inout)` here — inconsistent with `vertvisc`'s bare `CS`, flag for
  Stage 1 to normalize or preserve as-is (preserving is safer — don't change behavior not asked
  for).
- `vertvisc_remnant(visc, visc_rem_u, visc_rem_v, dt, G, GV, US, CS)` —
  `MOM_vert_friction.F90:1190-1204`. **No optional dummies.** `CS` again has no explicit `intent`.

## Full descendant list

| Subroutine | Owning entry point | Direct in-tree callees | Notes |
|---|---|---|---|
| `vertvisc_limit_vel` (3123-3300) | `vertvisc` | `write_u_accel`, `write_v_accel` — both excluded, see below | not itself an entry point |
| `write_u_accel` (`MOM_PointAccel.F90:68-404`) | `vertvisc` (via `vertvisc_limit_vel`) | none — only `open_ASCII_file`/`MOM_error`/`get_date`/`get_time` | **excluded from bridging** (user decision, see below) |
| `write_v_accel` (`MOM_PointAccel.F90:409-744`) | `vertvisc` (via `vertvisc_limit_vel`) | same infra only | **excluded from bridging** |
| `find_coupling_coef_k` (2100-2604, `pure`) | `vertvisc_coef` | none | leaf |
| `find_coupling_coef` (2610-3116) | `vertvisc_coef` | none | leaf; structurally identical to `_k` but exercises real `OBC` branches `_k` has commented out |
| `find_coupling_coef_gl90` (436-522) | `vertvisc_coef` | none | leaf; no `US`/`OBC` dummy at all |
| `find_ustar` → `find_ustar_mech_forcing` (`MOM_forcing_type.F90:1245-1305`) | `vertvisc_coef` | none (leaf, only `MOM_error`) | **excluded from bridging** — widely-shared leaf utility, same treatment as `thickness_to_dz` (`horizontal_viscosity.md`); marshal via container `%view` at the call site, never touch its own signature |

## Excluded from Phase 3 bridging (user decisions this session)

**`write_u_accel`/`write_v_accel` — classified as infra, leave alone.** Pure ASCII debug-log
writers for velocity-truncation events (open a file, write a formatted record, close it) — no
physics, and no plausible reason an AMReX/C++ kernel would need equivalent output. Same
treatment as `post_data` throughout this campaign: never containerized, never bridged. `ADp`/`CDp`
stay opaque pass-throughs into these two calls (matching `vertvisc_limit_vel`'s existing
behavior — it doesn't dereference either itself, just forwards them). `PointAccel_CS`
(`CS%PointAccel_CSp`, forwarded opaquely into both) needs no shadow of its own as a result —
nothing in the converted part of the tree ever dereferences its fields directly.

**`find_ustar`/`find_ustar_mech_forcing` — leave alone**, same reasoning as `thickness_to_dz` in
`horizontal_viscosity.md`: a leaf, but genuinely shared with 7+ unrelated files. `vertvisc_coef`'s
own call site marshals `forces`/`tv`/`Ustar_2d` via container `%view`; the routine itself is
never touched, never bridged.

## `CDp` (`cont_diag_ptrs`) — confirmed opaque, leave alone

First appearance of this type in the campaign. Shared 12 files repo-wide (`MOM_dynamics_*`,
`MOM.F90`, `MOM_diagnostics.F90`, `MOM_PointAccel.F90`, `MOM_interface_filter.F90`,
`MOM_thickness_diffuse.F90`, `MOM_diabatic_driver.F90`, etc.) — but within this entire family,
confirmed **zero `CDp%field` dereferences anywhere**: `vertvisc` forwards it whole into
`vertvisc_limit_vel`, which forwards it whole into `write_u_accel`/`write_v_accel` (excluded
above). Clean fixed-rule resolution, no shadow needed.

## `vertvisc_type` (the `visc` dummy) — promoted to `shared_type_unions.md`

25 fields (`MOM_variables.F90:258-313`: 15 allocatable arrays across two blocks, 8 pointer
arrays kept as restart-registry targets), shared 20 files repo-wide. Genuinely dereferenced
throughout this family — not opaque anywhere it appears. This family's own contribution to the
union: `Ray_u/v` (vertvisc, vertvisc_remnant), `taux_shelf`/`tauy_shelf` (vertvisc, vertvisc_coef),
`Kv_bbl_u/v`/`bbl_thick_u/v` (vertvisc_coef), `tbl_thick_shelf_u/v`/`Kv_shear`/`Kv_shear_Bu`/
`Kv_tbl_shelf_u/v`/`nkml_visc_u/v` (vertvisc_coef, `find_coupling_coef`/`_k`), `Kv_slow`
(vertvisc_coef). Not touched at all by `vertvisc_limit_vel` (confirmed unused despite being a
dummy there) or `find_coupling_coef_gl90` (no `visc` dummy). Promoted to a full union once
`set_viscous_BBL`/`set_viscous_ML` also needed it — see `shared_type_unions.md` for the current
field list (no new fields were needed for that promotion — everything those two entry points
touch was already covered here).

## `tv` (`thermo_var_ptrs`) — promoted to `shared_type_unions.md`

First tree in this campaign where `tv` needed any shadow at all — every earlier tree
(`continuity()`, `btstep`, `horizontal_viscosity`) treated it as purely opaque. This tree's own
footprint is narrow: exactly one field, `tv%SpV_avg`, dereferenced in `find_coupling_coef`/
`find_coupling_coef_k` (8 hits each, gated by `allocated(tv%SpV_avg)`, feeds an averaged
inverse-density into the dynamic-mixed-layer viscosity branch). `vertvisc_coef`'s own top-level
body has zero `tv%` dereferences (purely opaque there, forwarded into the callees).
`find_ustar_mech_forcing` also touches `tv%SpV_avg`/`tv%valid_SpV_halo`, but that routine is
excluded from bridging (above) so its usage doesn't enter this shadow's scope. Promoted from
tree-scoped to a full union once `PressureForce` needed a much larger footprint of the same
type (`T`, `S`, `P_Ref`, `eqn_of_state`, `varT`) — see `shared_type_unions.md` for the current
full field list.

## `Waves` (`wave_parameters_CS`) — promoted to `shared_type_unions.md`

First shadow needed for this type; now also needed by `CorAdCalc`, so it's tracked as a union in
`shared_type_unions.md` rather than tree-scoped here (10 files shared repo-wide, corrected from
an earlier 14-file estimate). Dereferenced directly in `vertvisc`: `Waves%us_x`, `Waves%us_y`
(Stokes-drift velocity components). `optional, pointer` together — the same combination flagged
as the open item in `horizontal_viscosity.md` (`BT`/`TD`/`ADp`/`STOCH`/`OBC`).

## `OBC`, `ADp`, `forces`, `VarMix` — union shadows grown by this tree

See `shared_type_unions.md` for the full, current field lists. This tree's contributions:
- **`OBC`**: `vertvisc` touches `number_of_segments`, `segment(:)%specified`,
  `segment(:)%HI%JsdB`, `segment(:)%normal_vel` — all already in the union from other trees, no
  new fields from `vertvisc` itself. `vertvisc_coef`/`find_coupling_coef`/`find_coupling_coef_k`
  add **new top-level fields** `u_E_OBCs_on_PE`, `u_W_OBCs_on_PE`, `v_N_OBCs_on_PE`,
  `v_S_OBCs_on_PE` (scalar logical) and `segnum_u`, `segnum_v` (allocatable integer arrays) —
  note `segnum_u`/`segnum_v` are a **new field shape** for this union: top-level arrays on
  `ocean_OBC_type` itself, not nested under `segment(:)`, so they don't need the
  array-of-struct decomposition treatment — ordinary `convert_array_containers` once exposed by
  the shadow. `find_coupling_coef_gl90` touches no `OBC` fields (no `OBC` dummy).
- **`ADp`**: `vertvisc` adds `du_dt_visc`/`dv_dt_visc`, `du_dt_str`/`dv_dt_str`,
  `du_dt_visc_gl90`/`dv_dt_visc_gl90` (new) alongside `diag_hfrac_u/v`, `visc_rem_u/v` (already
  in the union). Not touched by `vertvisc_coef`/`vertvisc_remnant`/their callees.
- **`forces`**: `vertvisc` adds `omega_w2x` (new) alongside `taux`/`tauy` (already in the
  union, same unconditional-dereference/no-`associated()`-check treatment as `btstep`).
  `vertvisc_coef` adds `frac_shelf_u`/`frac_shelf_v` (new) — **not yet confirmed** whether these
  are `pointer`+guarded or unconditional; check before finalizing the shadow's per-field
  treatment, same care taken for `taux`/`tauy` vs. `rigidity_ice_u/v` in `btstep.md`.
- **`VarMix`**: `find_coupling_coef_gl90` adds `kdgl90_struct` (new) alongside
  `use_variable_mixing` (already in the union from `horizontal_viscosity`).

## `vertvisc_CS` — bundle by precedent (no fresh Step 3 needed)

90 fields (`MOM_vert_friction.F90:56-196`, private): 38 scalar config/physics, 7 allocatable
arrays, 2 pointer arrays (`a1_shelf_u/v`), 2 nested pointers (`diag`, `PointAccel_CSp`), and 41
`id_*` diagnostic handles. This is the same shape as `barotropic_CS` (large diagnostic-ID block
alongside genuine physics/config fields), not `hor_visc_CS`'s shape (no dead weight to exclude)
— **applying the `barotropic_CS` precedent directly**: `create_config_bundle_type`, physics
fields only (~49 fields: the 38 scalars + 7 arrays + 2 pointer arrays), excluding the 41 `id_*`
handles and the 2 nested pointers (`diag`, `PointAccel_CSp` stay direct fields, same as
`barotropic_CS`'s `SAL_CSp`/`HA_CSp`/etc.). Since all three entry points sharing this CS are
being decided together in this same session, there's no reconciliation risk the way there was
for `hor_visc_CS`/hypothetically deferring `vertvisc` — bundle based on the union of fields
confirmed touched across all three trees combined (partial list, not necessarily exhaustive —
`create_config_bundle_type`'s own execution does the final sweep): `initialized`,
`direct_stress`, `h_u`, `h_v`, `a_u`, `a_v`, `a_u_gl90`, `a_v_gl90`, `diag`, `pass_KE_uv`,
`PointAccel_CSp`, `StokesMixing`, `Hmix_stress`, `a1_shelf_u`, `a1_shelf_v`, `vel_underflow`,
`CFL_report`, `CFL_trunc`, `ntrunc`, `u_trunc_file`, `v_trunc_file`, `debug`, `harm_BL_val`,
`answer_date`, `Kv`, `use_GL90_N2`, `alpha_gl90`, `read_kappa_gl90`, `kappa_gl90`,
`kappa_gl90_2d`, plus whichever of the remaining ~20 scalar fields `find_coupling_coef`/
`find_coupling_coef_k`'s fuller dereference set touches beyond what was itemized by name.

## Open item — optional struct dummies (extends `horizontal_viscosity.md`'s item)

`vertvisc`'s `Waves` (`optional, pointer`) is the same unresolved category as
`horizontal_viscosity`'s `BT`/`TD`/`ADp`/`STOCH`/`OBC`. Still no sibling skill covers this. Note
also that `vertvisc_coef` and `vertvisc_remnant` have **zero optional dummies** in their own
signatures — this open item only affects `vertvisc` within this family.

## Step 2 — target classification (fixed-rule items)

| Target | Classification | Skill | Notes |
|---|---|---|---|
| `u`, `v`, `h` (all three subroutines), `dz` (vertvisc_coef), `visc_rem_u/v` (vertvisc_remnant), `taux_bot`/`tauy_bot` (vertvisc, optional) | raw/optional array dummies | `convert_array_containers` (+ `convert_present_to_associated` for the two optionals) | Standard. |
| `a_cpl`, `hvel`, `h_harm`, `z_i`, `Ustar_2d` (`find_coupling_coef`/`_k`); `a_cpl_gl90`, `hvel`, `z_i` (`find_coupling_coef_gl90`) | raw array dummies | `convert_array_containers` | Standard, all three confirmed leaves. |
| `fpmix` (vertvisc, scalar logical, optional) | optional scalar | `convert_present_to_associated` | Not a struct — ordinary case, no open-item concern. |
| `shelf` (`find_coupling_coef`/`_k`, scalar logical, optional) | optional scalar | `convert_present_to_associated` | — |
| `G`, `GV` | shared grid/vertical-grid types | `convert_array_containers`'s own drop mechanism | Not a separate decision. |
| `US` | shared scaling type | same drop mechanism | **Inconsistently used across this family** — unused in `vertvisc_remnant`, `find_coupling_coef`, `find_coupling_coef_k`, `find_ustar_mech_forcing`; used in `vertvisc_limit_vel` (`US%m_s_to_L_T`) and presumably `vertvisc_coef`/`vertvisc` themselves. Flag every unused instance for the upward-pass drop decision, same as `btstep`/`horizontal_viscosity`. |
| `visc` | shared, dereferenced | `create_shadow_container_type`, tree-scoped | See dedicated section above. |
| `tv` | shared, union (promoted) | `create_shadow_container_type`, union scope | See `shared_type_unions.md`. |
| `OBC`, `ADp`, `forces`, `VarMix`, `Waves` | shared, union | `create_shadow_container_type`, union scope | See `shared_type_unions.md`. `Waves` blocked on the optional-struct open item for the wrapper-side "is it present" handling. |
| `CDp` | confirmed opaque throughout | leave alone | No shadow needed. |
| `PointAccel_CS` (`CS%PointAccel_CSp`) | confirmed opaque (only reaches excluded infra) | leave alone | No shadow needed. |
| `CS` (`vertvisc_CS`) | private, 90 fields | `create_config_bundle_type`, physics-fields-only | See dedicated section above. |

## Phase 2 execution order (for this family)

1. **TreeRoot split** — three separate rename+wrapper pairs (see Step 1d above).
2. **`create_shadow_container_type`** — every one of `visc`/`tv`/`OBC`/`ADp`/`forces`/`VarMix`/
   `Waves`'s type definitions is built once by the combined shared-infrastructure PR
   (`shared_type_unions.md`), not here. This stage's own work is just the wrapper-side glue —
   instantiate each shadow from this tree's own dummies, use it, copy back — in each of the three
   entry points' wrappers that need them.
3. **`create_config_bundle_type`** — `vertvisc_CS`, once, informed by the union of all three
   entry points' usage (no per-entry-point repeats needed since they share one CS and one
   bundle).
4. **Optional-array containerization** — `taux_bot`/`tauy_bot` (vertvisc); default direction
   (neither cascades — both are outputs, never forwarded).
5. **`convert_array_containers` — downward pass**, root to leaves, per entry point (three
   separate downward passes, since they're three separate trees sharing infrastructure, not one
   tree).
6. **`convert_array_containers` — upward pass**, leaves to root, G/GV/US-drop decisions
   (including the flagged inconsistent `US` usage above).
7. **`convert_locals_to_containers`**, per subroutine once dummies are stable.
8. **`convert_present_to_associated`** — `taux_bot`/`tauy_bot`, `fpmix`, `shelf`. **Blocked on
   the optional-struct open item for `Waves`** — resolve before this stage touches it.
9. **`hoist_container_marshalling`**, once per entry point (three invocations: `vertvisc_TR`,
   `vertvisc_coef_TR`, `vertvisc_remnant_TR`).

## Phase 3 wave order

Three independent sequences (separate entry points), but sharing wave 1's leaves where
applicable:

- **Wave 1** (leaves, no in-tree callees needing bridging first): `find_coupling_coef_k`,
  `find_coupling_coef`, `find_coupling_coef_gl90`, `vertvisc_limit_vel` (its only in-tree calls,
  `write_u_accel`/`write_v_accel`, are excluded from bridging), **`vertvisc_remnant_TR`** (no
  in-tree callees at all beyond excluded infra — root and leaf at once for its own trivial tree).
- **Wave 2**: `vertvisc_coef_TR` (callees `find_coupling_coef_k`/`find_coupling_coef`/
  `find_coupling_coef_gl90` all wave 1; `find_ustar` excluded from bridging), `vertvisc_TR`
  (callee `vertvisc_limit_vel` wave 1).

None of the three wrappers (`vertvisc`, `vertvisc_coef`, `vertvisc_remnant`) are ever bridged.

## Branch

Three entry points, one Phase 1 pass, one branch: `claude_vertvisc_family_calltree` (deviating
from the skill's literal `claude_<lowercased-entry-point>_calltree` naming, which assumes one
entry point per run — recorded here as the deliberate choice for this multi-entry-point session),
created once before Phase 2 Stage 1.
