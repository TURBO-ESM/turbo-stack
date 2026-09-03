# Call-tree conversion plan: `set_viscous_BBL`, `set_viscous_ML`

Two entry points, `src/parameterizations/vertical/MOM_set_viscosity.F90`, surveyed together
(user request, mirroring the `vertvisc_family` precedent) because both share one private module
control structure (`set_visc_CS`) and several derived types. Cross-reference:
`.claude/calltree-plans/shared_type_unions.md` for `tv`, `vertvisc_type`, `forces`, `OBC`, `pbv`
(all grown or promoted by this pair) and `EOS_bridge_design.md` for how the direct
`calculate_density`/`calculate_density_derivs` calls in this tree resolve.

No pre-existing audit doc existed for either entry point.

**Base plan — double_gyre_unsplit.** `set_viscous_BBL` is called from `MOM.F90`, before the
`CS%split` dispatch; `set_viscous_ML` is called identically from all 4 dynamics-core files
regardless of `SPLIT`. Confirmed exercised identically (identical 21.6% file coverage) under both
`double_gyre` and `double_gyre_unsplit` — only per-line hit counts differ. No patch needed.

## Hard precondition checks

- **Callers — asymmetric, unlike every prior sibling-entry-point family this session.**
  `set_viscous_BBL` is called **only from `MOM.F90`** (lines 1344, 1786) — not the usual 4
  dynamics-core files. `set_viscous_ML` is called from all 4 dynamics-core files
  (`MOM_dynamics_unsplit_RK2.F90:357`, `MOM_dynamics_split_RK2b.F90:622`,
  `MOM_dynamics_split_RK2.F90:640`, `MOM_dynamics_unsplit.F90:357`) and **not** from `MOM.F90` at
  all (confirmed — `MOM.F90` only imports the name, never calls it). Two entry points, two
  disjoint caller sets, one shared module.
- Shared-descendant check: `find_L_open_uniform_slope`, `find_L_open_concave_trigonometric`,
  `find_L_open_concave_iterative`, `find_L_open_convex`, `test_L_open_concave` — all confirmed
  zero callers outside `MOM_set_viscosity.F90`, all called only from `set_viscous_BBL`.
  **`set_v_at_u`/`set_u_at_v`** are `public` `pure function`s called from *both*
  `set_viscous_BBL` and `set_viscous_ML` (in-tree fan-in, fine since both are in scope) — **and**
  imported (`use MOM_set_visc, only : set_v_at_u, set_u_at_v`) into
  `src/parameterizations/vertical/MOM_vert_friction.F90:36`, but confirmed **never actually
  invoked there** (dead import). Not a live shared-descendant conflict, but flag this explicitly
  — if that import is ever exercised in the future, it would create a real conflict with the
  already-recorded `vertvisc_family.md` plan.
- `tv`, `vertvisc_type` (`visc`), `forces`, `OBC`, `pbv` are all shared with other actively-
  converted trees — see `shared_type_unions.md`. Good news: `vertvisc_type`'s entire footprint
  here is *already* covered by `vertvisc_family`'s existing shadow field list — this is a free
  promotion to a union, no new fields needed.
- `MOM_EOS.F90` — both entry points call it directly (`set_viscous_BBL`: `calculate_density`,
  `calculate_density_derivs`; `set_viscous_ML`: `calculate_density_derivs`,
  `calculate_specific_vol_derivs`/`calc_spec_vol_derivs`-family — confirm exact generic name
  during implementation). Resolved the same way as every other EOS-touching tree: leave every
  call raw, view-marshal at the call site, per `EOS_bridge_design.md`.
- `thickness_to_dz` (`MOM_interface_heights.F90`) — called by both `set_viscous_BBL`
  (unconditionally) and `set_viscous_ML`. Already classified "leave alone, widely shared" for
  `horizontal_viscosity`'s QG-Leith branch — this is now the *third* tree reaching it, same
  classification applies, doubly confirmed rather than newly decided.

## Step 1d — wrapper cases (two separate Case-3 splits)

Both **Case 3** — distinct subroutines, called directly, no wrapper/alias.
1. `set_viscous_BBL` → `set_viscous_BBL_TR`, new `set_viscous_BBL` wrapper.
2. `set_viscous_ML` → `set_viscous_ML_TR`, new `set_viscous_ML` wrapper.
Neither wrapper is ever bridged. `find_L_open_*`/`test_L_open_concave`/`set_v_at_u`/`set_u_at_v`
are not entry points and get no rename/wrapper of their own.

## External signatures (frozen — do not change)

- `set_viscous_BBL(u, v, h, tv, visc, G, GV, US, CS, pbv)` — `MOM_set_viscosity.F90:153-169`. All
  7 dummies mandatory, no `optional`, no bare `pointer` dummies (unlike several other entry
  points this session) — `G`/`GV`/`US` standard, `tv`/`visc`/`CS`/`pbv` all plain derived-type
  dummies.
- `set_viscous_ML(u, v, h, tv, forces, visc, dt, G, GV, US, CS)` — `MOM_set_viscosity.F90:2046-2064`.
  All 11 dummies mandatory, no optionals, no pointers.

## Full descendant list

| Subroutine/function | Owning entry point | Direct in-tree callees | Notes |
|---|---|---|---|
| `find_L_open_uniform_slope` (1239-1277) | `set_viscous_BBL` | none | leaf, `pure`; gated `crv==0.0` |
| `find_L_open_concave_trigonometric` (1281-1370) | `set_viscous_BBL` | none | leaf, `pure`; gated `crv>0.0 .and. CS%concave_trigonometric_L` (or the `CS%debug` side-by-side comparison) |
| `find_L_open_concave_iterative` (1376-1697) | `set_viscous_BBL` | none | leaf, `pure`; gated `crv>0.0 .and. .not. CS%concave_trigonometric_L` |
| `find_L_open_convex` (1786-1947) | `set_viscous_BBL` | none | leaf, `pure`; gated `crv<0.0`. Takes `CS`/`US` as dummies but only dereferences fields (`US%Z_to_m`, `CS%answer_date`) — never forwards them further |
| `test_L_open_concave` (1703-1780) | `set_viscous_BBL` | none | leaf, `pure`; only called inside `CS%debug` diagnostic block, alongside the iterative branch |
| `set_v_at_u` (1950-1993) | both | none | leaf, `pure function`; public, shared in-tree between both entry points (see dead-import flag above) |
| `set_u_at_v` (1996-2039) | both | none | leaf, `pure function`; same |

**Not entry points, out of scope**: `set_visc_register_restarts`, `remap_vertvisc_aux_vars`,
`set_visc_init`, `set_visc_end` (init/teardown/restart-registration, same pattern as every other
`_init`/`_end` pair this session).

**Gating logic for the `find_L_open_*` family** (fully confirmed, `set_viscous_BBL` only): a
curvature `crv` is computed per velocity point; `crv==0` → uniform-slope, `crv>0` → concave
(trigonometric or iterative, selected by `CS%concave_trigonometric_L`; iterative branch also
runs a `CS%debug`-gated side-by-side comparison against trigonometric), `crv<0` → convex. Unlike
`horizontal_viscosity`/`CorAdCalc`, **no monolith-split organizational decision is needed here**
— the geometry family is already factored into small `pure` leaf subroutines, much closer to
`btstep`'s shape than either of those two.

## `tv`, `vertvisc_type`, `forces`, `OBC`, `pbv` — see `shared_type_unions.md`

This pair's contributions:
- **`tv`**: both entry points genuinely dereference `T`/`S`/`SpV_avg`/`eqn_of_state`/`P_Ref`/
  `p_surf` directly (already in the union from `PressureForce`/`vertvisc_coef` — no new fields).
  Part of the 7-type combined shared-infrastructure PR.
- **`vertvisc_type`** (`visc`): **as of this session, a local shadow scoped to the whole
  vertvisc-family cluster** (`vertvisc`/`vertvisc_coef`/`vertvisc_remnant`/`set_viscous_BBL`/
  `set_viscous_ML`), not the combined PR — `set_viscous_BBL` needs `Ray_u/v`, `bbl_thick_u/v`,
  `Kv_bbl_u/v`; `set_viscous_ML` needs `Kv_tbl_shelf_u/v`, `nkml_visc_u/v`, `taux_shelf`/`tauy_shelf`,
  `tbl_thick_shelf_u/v`. Every one of these is already in `vertvisc_family.md`'s field list — zero
  new fields, and this pair can consume that cluster's local shadow directly, no combined-PR wait.
  See `shared_type_unions.md`'s "Mechanism decision" section.
- **`forces`**: also moved out of the combined PR this session. `set_viscous_ML` needs `p_surf`
  (its own tree-local field, not shared with anything else), `frac_shelf_u/v` (shared with
  `vertvisc_coef`, within this same vertvisc-family cluster), and `taux`/`tauy` — **corrected this
  session: confirmed a real, direct dereference at `MOM_set_viscosity.F90:2286-2288,2563-2565`**,
  not previously recorded in this pair's own field list — shared cross-cluster with `btstep`. See
  `shared_type_unions.md`'s "Mechanism decision" section for the full breakdown.
- **`OBC`**: `set_viscous_BBL` adds **16 new top-level scalar-integer index-bound fields** —
  `Js_v_N_obc`/`Je_v_N_obc`/`is_v_N_obc`/`ie_v_N_obc`, `Js_v_S_obc`/`Je_v_S_obc`/`is_v_S_obc`/
  `ie_v_S_obc`, `js_u_E_obc`/`je_u_E_obc`/`Is_u_E_obc`/`Ie_u_E_obc`, `js_u_W_obc`/`je_u_W_obc`/
  `Is_u_W_obc`/`Ie_u_W_obc` — one set of 4 per direction, giving the index range wherever the
  corresponding `*_OBCs_on_PE` flag (already unioned) is true. `set_viscous_ML` needs nothing
  beyond what's already in the union. **Both entry points receive `OBC` via `CS%OBC` (a nested
  pointer field of `set_visc_CS`), not as their own top-level dummy** — the first time in this
  campaign `OBC` arrives this way. The shadow-building logic still belongs in each wrapper, just
  sourced from `CS%OBC` (aliased to a local pointer at the top of each subroutine today) rather
  than a dummy argument — a mechanical variation on the established pattern, not a new one.
- **`pbv`**: `set_viscous_BBL` touches **all 4 fields** (`por_face_areaU/V` already unioned from
  `continuity()`/`CorAdCalc`; `por_layer_widthU/V` new). `set_viscous_ML` doesn't take `pbv` at
  all.

## `set_visc_CS` — bundle by precedent (no fresh Step 3 needed)

50 fields (`MOM_set_viscosity.F90:54-148`, private): 33 scalar config/physics, 2 nested pointers
(`OBC`, `diag`), 5 allocatable arrays (`cdrag_u`/`cdrag_v`/`tideamp` config arrays,
`bbl_u`/`bbl_v` diagnostic arrays), 10 `id_*` diagnostic handles. Same shape as
`barotropic_CS`/`vertvisc_CS`/`CoriolisAdv_CS`/`PressureForce_FV_CS` — `create_config_bundle_type`,
physics fields only (the 33 scalars + 5 arrays), excluding the 10 `id_*` handles and the 2
nested pointers (`OBC` stays a direct field per the shadow note above; `diag` opaque by the
established pattern). Since both entry points sharing this CS are being decided together, no
reconciliation risk — bundle based on the union of fields both touch (substantial overlap
already confirmed: `cdrag`, `linear_drag`, `drag_bg_vel`, `debug`, `BBL_use_tidal_bg`, `tideamp`,
`OBC`, `diag` are touched by both).

## Step 2 — target classification (fixed-rule items)

| Target | Classification | Skill | Notes |
|---|---|---|---|
| `u`, `v`, `h` (both), `pbv`'s implicit array fields via the shadow | raw array dummies | `convert_array_containers` | Standard. |
| `find_L_open_*`/`test_L_open_concave`'s own dummies (`vol_below`, `Dp`, `Dm`, `L`, `D_vel`, `vol_err`) | scalar reals, not arrays | nothing to do | Confirm during execution — these look like per-point scalars, not grid arrays, based on the naming; verify before assuming `convert_array_containers` even applies. |
| `set_v_at_u`/`set_u_at_v`'s own dummies (`v`/`u`, `h`, `mask2dCv`/`mask2dCu`) | raw array dummies, `pure function` | `convert_array_containers` | **Open item**: every bridged kernel so far in this campaign has been a `subroutine` (`cpp_bridge_lessons`' own worked examples too) — confirm `generate_cpp_bridge`'s shim pattern extends cleanly to a `pure function` with a scalar return value before assuming it does; flag for Phase 3, don't force it through unreviewed. |
| `G`, `GV` | shared grid/vertical-grid types | `convert_array_containers`'s own drop mechanism | Not a separate decision. |
| `US` | shared scaling type | same drop mechanism | Lightly used in both (`set_viscous_ML`: only 2 fields, `L_to_m`/`L_to_Z`) — flag for upward-pass drop consideration. |
| `tv`, `OBC` | shared, union | `create_shadow_container_type`, union scope | See `shared_type_unions.md`. |
| `vertvisc_type`, `forces` | shared, local shadow | `create_shadow_container_type`, **vertvisc-family cluster shadow (`vertvisc_type`, `frac_shelf_u/v`, `p_surf`) + cross-cluster shadow with `btstep` (`taux`/`tauy`)** — not the combined PR | See `shared_type_unions.md`'s "Mechanism decision" section. |
| `pbv` | shared, union | `create_shadow_container_type`, union scope (already exists from `continuity()`/`CorAdCalc`) | `set_viscous_BBL` needs all 4 fields — union grows to cover `por_layer_widthU/V`. |
| `CS` (`set_visc_CS`) | private, 50 fields | `create_config_bundle_type`, physics-fields-only | See dedicated section above. |
| EOS-family calls (`calculate_density`, `calculate_density_derivs`, `calculate_specific_vol_derivs`/`calc_spec_vol_derivs`) | pervasive per `EOS_bridge_design.md` | leave alone — view-marshal via the shared marshalling helper | See `EOS_bridge_design.md`; confirm exact generic-interface name for the specific-volume-derivatives call during implementation. Helper built once in the combined infrastructure PR, not authored here. |
| `thickness_to_dz`, `find_ustar` | widely-shared leaves | leave alone — view-marshal at call site | Same treatment as `horizontal_viscosity`/`vertvisc_coef`. |

## Phase 2 execution order

1. **TreeRoot split** — two separate rename+wrapper pairs (see Step 1d above).
2. **`create_shadow_container_type`** — `tv`/`vertvisc_type`/`forces`/`OBC`/`pbv`'s type
   definitions are built once by the combined shared-infrastructure PR (`shared_type_unions.md`),
   not here. This stage's own work is just the wrapper-side glue — instantiate each shadow and
   copy back, in each of the two entry points' wrappers that need them. `OBC`'s glue sources from
   `CS%OBC`, not a dummy — see note above.
3. **`create_config_bundle_type`** — `set_visc_CS`, once, informed by the union of both entry
   points' usage.
4. **Optional-array containerization** — none needed; neither entry point has any optional
   dummy.
5. **`convert_array_containers` — downward pass**, per entry point (two separate downward passes
   — `set_viscous_BBL_TR` and `set_viscous_ML_TR` are independent trees sharing infrastructure,
   not one tree).
6. **`convert_array_containers` — upward pass**, G/GV/US-drop decisions across both.
7. **`convert_locals_to_containers`**, per subroutine once dummies are stable.
8. **`convert_present_to_associated`** — not needed, no optional dummies anywhere in this pair.
9. **`hoist_container_marshalling`**, once per entry point (two invocations:
   `set_viscous_BBL_TR`, `set_viscous_ML_TR`).

## Phase 3 wave order

- **Wave 1** (leaves, shared by both trees where applicable): `find_L_open_uniform_slope`,
  `find_L_open_concave_trigonometric`, `find_L_open_concave_iterative`, `find_L_open_convex`,
  `test_L_open_concave`, `set_v_at_u`, `set_u_at_v`.
- **Wave 2 (roots, last)**: `set_viscous_BBL_TR` (calls the `find_L_open_*`/`test_L_open_concave`
  family + `set_v_at_u`/`set_u_at_v`, all wave 1; EOS and `thickness_to_dz` calls stay external),
  `set_viscous_ML_TR` (calls `set_v_at_u`/`set_u_at_v`, wave 1; `find_ustar`, `thickness_to_dz`,
  EOS calls all stay external).

Neither wrapper is ever bridged.

## Branch

`claude_set_viscosity_family_calltree`, created once before Phase 2 Stage 1 (deviating from the
skill's literal single-entry-point branch naming, same deliberate choice already made for
`vertvisc_family`).
