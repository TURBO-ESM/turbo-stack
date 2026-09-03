# Call-tree conversion plan: `tracer_hordiff`

Promoted mid-survey from a candidate descendant of `step_MOM_tracer_dyn` to its own entry point
(same user decision as `advect_tracer.md`, and for the same reason): `tracer_hordiff` is `public`
in `MOM_tracer_hor_diff` and called from 4 places (`MOM.F90`'s `step_MOM_tracer_dyn` and 3 sites
in `step_offline`) — a stronger externally-fixed contract than `step_MOM_tracer_dyn` itself had.
Every caller, including `step_MOM_tracer_dyn`'s own (still-deferred) plan, treats this as an
opaque call needing only call-site marshalling.

No pre-existing audit doc existed for this entry point.

**Base plan — double_gyre_unsplit**, but with a pre-existing gap independent of that choice.
`tracer_hordiff` is called unconditionally from `step_MOM_tracer_dyn`, outside the `CS%split`
branch — identical 7.0% file coverage under both `double_gyre` and `double_gyre_unsplit`, so no
patch is needed for the split/unsplit distinction. However, that identical 7.0% is coverage of
*other* code in `MOM_tracer_hor_diff.F90` — the subroutine's own three dispatch branches
(`CS%Diffuse_ML_interior`, `CS%use_hor_bnd_diffusion`, `CS%use_neutral_diffusion`) show **0 hits
in both** double_gyre variants. Neither config can validate this tree via capture fixtures today;
`benchmark` (71.1% coverage of the same file) is the config that would actually exercise it. This
is a separate, pre-existing problem — not something the base/patch resequencing fixes or causes.

## Hard precondition checks

- **Callers (repo-wide, confirmed by grep):** `MOM.F90:1648` (`step_MOM_tracer_dyn`),
  `MOM.F90:2213,2240,2297` (`step_offline`). Neither caller is a campaign entry point; this plan
  does not touch them.
- **Shared-descendant check, every descendant** (deep fork survey, not just the top-level calls):
  `tracer_epipycnal_ML_diff`, `hor_bnd_diffusion`, `neutral_diffusion_calc_coeffs`,
  `neutral_diffusion`, and every one of their own nested helpers (`compute_tapering_coeffs`,
  `interface_scalar`, `PLM_diff`, `find_neutral_surface_positions_continuous`,
  `find_neutral_surface_positions_discontinuous`, `mark_unstable_cells`, `increment_interface`,
  `calc_delta_rho_and_derivs`, `neutral_surface_flux`, `neutral_surface_T_eval`,
  `ppm_left_right_edge_values`, `fluxes_layer_method`) — **confirmed zero callers outside this
  tree**, fully tree-internal.
- **One cross-file, still-tree-internal exception**: `boundary_k_range` is defined in
  `MOM_hor_bnd_diffusion.F90:621` but called from *both* `hor_bnd_diffusion` (same file) and
  `neutral_diffusion_calc_coeffs` (`MOM_neutral_diffusion.F90`) — both callers are in-tree, so
  this is fan-in within the tree, not a conflict. Treat as a shared leaf between two in-tree
  subroutines, same as `set_v_at_u`/`set_u_at_v` were shared between `set_viscous_BBL`/`_ML`.
- **One genuinely external leaf**: `build_reconstructions_1d` (`src/ALE/MOM_remapping.F90:414`,
  used by 19 files repo-wide) is called from `neutral_diffusion_calc_coeffs` and
  `find_neutral_surface_positions_discontinuous`. Same shape as `thickness_to_dz`/`find_ustar` —
  **leave alone, view-marshal at the call site**, not owned by this tree.
- `MOM_EOS` (`calculate_density`, `calculate_density_derivs`) — called from
  `tracer_epipycnal_ML_diff` and `neutral_diffusion_calc_coeffs`/`mark_unstable_cells`. Governed
  by `EOS_bridge_design.md` — leave alone, view-marshal, same as every other EOS-touching tree.
- Not entry points, out of scope: `tracer_hor_diff_init`, `tracer_hor_diff_end`,
  `neutral_diffusion_init`, `neutral_diffusion_end`, `neutral_diffusion_unit_tests`,
  `hor_bnd_diffusion_init`, `hor_bnd_diffusion_end` (init/teardown/unit-test pattern excluded
  everywhere else this session).

## Step 1d — wrapper case

**Case 3** — plain subroutine, called directly, no existing alias/wrapper.
`tracer_hordiff` → `tracer_hordiff_TR`, new `tracer_hordiff` wrapper. Wrapper never bridged.

## External signature (frozen — do not change)

`tracer_hordiff(h, dt, MEKE, VarMix, visc, G, GV, US, CS, Reg, tv, do_online_flag, read_khdt_x, read_khdt_y)`
— `MOM_tracer_hor_diff.F90:122-150`. 11 mandatory dummies + 3 optional (`do_online_flag` logical
scalar; `read_khdt_x`/`read_khdt_y` real 2-D arrays — doc comment says these "do not appear to be
used anywhere," confirm during Phase 2 before deciding whether to still containerize them).

## Full descendant list

| Subroutine | File:lines | Direct in-tree callees | Notes |
|---|---|---|---|
| `tracer_epipycnal_ML_diff` | `MOM_tracer_hor_diff.F90:733-1667` | none in-tree (only `calculate_density`, external EOS) | gated `CS%Diffuse_ML_interior`; fully independent branch |
| `hor_bnd_diffusion` | `MOM_hor_bnd_diffusion.F90:178-352` | `fluxes_layer_method`, `hbd_grid`, `boundary_k_range` | gated `CS%use_hor_bnd_diffusion` |
| `neutral_diffusion_calc_coeffs` | `MOM_neutral_diffusion.F90:353-618` | `boundary_k_range`, `find_neutral_surface_positions_continuous`, `find_neutral_surface_positions_discontinuous`, `interface_scalar`, `mark_unstable_cells` (+ external `build_reconstructions_1d`, `calculate_density_derivs`) | gated `CS%use_neutral_diffusion` |
| `neutral_diffusion` | `MOM_neutral_diffusion.F90:621-1034` | `compute_tapering_coeffs`, `neutral_surface_flux` | gated `CS%use_neutral_diffusion`, called after `_calc_coeffs` |
| `fluxes_layer_method` | `MOM_hor_bnd_diffusion.F90:689-837` | none | leaf |
| `hbd_grid` | `MOM_hor_bnd_diffusion.F90` | none | leaf, grid helper |
| `boundary_k_range` | `MOM_hor_bnd_diffusion.F90:621` | none | leaf, shared in-tree by `hor_bnd_diffusion` + `neutral_diffusion_calc_coeffs` |
| `compute_tapering_coeffs` | `MOM_neutral_diffusion.F90:1038-1093` | none | leaf |
| `interface_scalar` | `MOM_neutral_diffusion.F90:1094-1227` | none | leaf |
| `PLM_diff` | `MOM_neutral_diffusion.F90:1228-1369` | none | leaf |
| `find_neutral_surface_positions_continuous` | `MOM_neutral_diffusion.F90:1370-1625` | `increment_interface`, `PLM_diff` | |
| `find_neutral_surface_positions_discontinuous` | `MOM_neutral_diffusion.F90:1626-1862` | `interface_scalar`, `ppm_left_right_edge_values`, `calc_delta_rho_and_derivs` (+ external `build_reconstructions_1d`) | |
| `mark_unstable_cells` | `MOM_neutral_diffusion.F90:1863-1953` | `calc_delta_rho_and_derivs` (+ external `calculate_density`) | |
| `increment_interface` | `MOM_neutral_diffusion.F90:1954-2199` | none | leaf |
| `calc_delta_rho_and_derivs` | `MOM_neutral_diffusion.F90:2200-2319` | none in-tree | leaf w.r.t. this tree |
| `neutral_surface_flux` | `MOM_neutral_diffusion.F90:2320-2500` | `calc_delta_rho_and_derivs`, `neutral_surface_T_eval` | |
| `neutral_surface_T_eval` | `MOM_neutral_diffusion.F90:2501-2563` | none | leaf |
| `ppm_left_right_edge_values` | `MOM_neutral_diffusion.F90:2564-3367` region | none | leaf |

**Organizational shape**: not a monolith needing a split-by-scheme decision (unlike
`horizontal_viscosity`/`CorAdCalc`) — the three gated branches (`hor_bnd_diffusion`,
`neutral_diffusion` family, `tracer_epipycnal_ML_diff`) are already separate named subroutines.
`tracer_hordiff`'s own body is a dispatcher plus one substantial default in-line Redi-diffusion
computation (roughly lines 200-514). Closer to `set_viscosity_family`'s "already factored, no
split needed" shape.

## `MEKE`, `VarMix`, `visc`, `tv`, `Reg`/`Tr` — see `shared_type_unions.md`

This tree's contributions (all recorded there already):
- **`MEKE`**: promotes tree-scoped→union. Needs `Kh` (allocated-guarded array), `KhTr_fac`
  (scalar) — overlap with `horizontal_viscosity`'s "most/all 15 fields" not yet itemized/confirmed.
- **`VarMix`**: 8 new fields (`Resoln_scaled_KhTr`, `khtr_struct`, `SN_u`, `SN_v`, `L2u`, `L2v`,
  `Rd_dx_h`, `ebt_struct`) against 2 already-unioned (`use_variable_mixing`, `Res_fn_h`).
- **`visc`** (`vertvisc_type`): free promotion, but **not** dereferenced by `tracer_hordiff`'s own
  body — only by its in-tree callees `hor_bnd_diffusion`/`neutral_diffusion_calc_coeffs`, both of
  which need the new field `h_ML`. `tracer_hordiff` forwards the dummy opaquely.
- **`tv`**: adds `p_surf` (new, `associated()`-guarded) to the existing `T`/`S`/`P_Ref`/
  `eqn_of_state` set.
- **`Reg`/`Tr`** (`tracer_registry_type`/`tracer_type`, new union, first needed jointly with
  `advect_tracer`): needs `t`, `df_x`, `df_y`, `df2d_x`, `df2d_y`, `name`, `conc_underflow` (own
  body + `tracer_epipycnal_ML_diff`), plus `conc_scale` and 7 `id_hbd_*`/`id_hbdxy_*` diagnostic
  handles (via `hor_bnd_diffusion`) — the `id_*` fields excluded from any container
  decomposition, same precedent as top-level CS bundling.

## `tracer_hor_diff_CS` — bundle by precedent (no fresh Step 3 needed)

30 fields (`MOM_tracer_hor_diff.F90:43-101`, private): 20 physics scalars (`KhTr`,
`KhTr_Slope_Cff`, `KhTr_min`, `KhTr_max`, `KhTr_passivity_coeff`, `KhTr_passivity_min`,
`ML_KhTR_scale`, `max_diff_CFL`, `KhTr_use_vert_struct`, `full_depth_khtr_min`,
`Diffuse_ML_interior`, `check_diffusive_CFL`, `use_neutral_diffusion`, `use_hor_bnd_diffusion`,
`recalc_neutral_surf`, `limit_bug`, `answer_date`, `debug`, `show_call_tree`, `first_call`);
3 nested CS pointers (`neutral_diffusion_CSp`, `hor_bnd_diffusion_CSp`, `diag`); 6 `id_*`
diagnostic handles; 1 infra field (`pass_t`, `group_pass_type`). Standard bundle shape —
`create_config_bundle_type` on the 20 scalars, exclude the 3 nested pointers + 6 `id_*` + `pass_t`.

## `neutral_diffusion_CS` and `hbd_CS` — nested, genuinely dereferenced in-tree, bundle too

Neither is touched directly by `tracer_hordiff`'s own body (confirmed, zero `CS%neutral_diffusion_CSp%...`
or `CS%hor_bnd_diffusion_CSp%...` hits there) — but `neutral_diffusion_calc_coeffs`/
`neutral_diffusion` (in-tree) dereference `neutral_diffusion_CS` extensively, and
`hor_bnd_diffusion` (in-tree) dereferences `hbd_CS` similarly. Since both owning subroutines are
themselves in-tree with zero outside callers (confirmed above), these are **bundle candidates,
not shadow candidates** — one level down from the root CS, same treatment.

- **`neutral_diffusion_CS`** (`MOM_neutral_diffusion.F90:45-131`, private): 55 physics
  scalar/array fields, 2 `id_*` handles, 5 nested pointers/types (`diag`, `EOS`, `remap_CS`,
  `KPP_CSp`, `energetic_PBL_CSp`) — bundle the 55, exclude the rest.
- **`hbd_CS`** (`MOM_hor_bnd_diffusion.F90:43-70`, private): 17 fields total, 4 nested
  (`remap_CS`, `KPP_CSp`, `energetic_PBL_CSp`, `diag`), 0 `id_*` — bundle the remaining 13.

## Step 2 — target classification (fixed-rule items)

| Target | Classification | Skill | Notes |
|---|---|---|---|
| `h`, `Coef_x`/`Coef_y`, `Kh_u`/`Kh_v`/`Kh_h`, `khdt_x`/`khdt_y`, `khdt_epi_x`/`khdt_epi_y` | mandatory raw array dummies | `convert_array_containers` | Standard real arrays, various ranks. |
| `read_khdt_x`, `read_khdt_y` | optional raw array dummies, possibly dead | `convert_present_to_associated`, after containerizing | Confirm actually-dead status during Phase 2 before committing effort; if truly unused, still convert rather than special-case, per "never leave optional array raw on a bridged target." |
| `do_online_flag` | optional scalar | `convert_present_to_associated` | logical. |
| `stable_l`, `stable_r` (`find_neutral_surface_positions_discontinuous`), `stable_cell` (`mark_unstable_cells`) | mandatory raw **logical** array dummies | `convert_array_containers` | `LogicalArray_t` confirmed available (see `advect_tracer.md`'s corrected note) — ordinary classification. |
| `p_surf` (`neutral_diffusion_calc_coeffs`'s own optional, distinct from `tv%p_surf`) | optional raw array dummy | `convert_present_to_associated`, after containerizing | 2-D real. |
| `coeff_l`, `coeff_r` (deep leaves) | optional raw array dummies, small (`nk+1`) | `convert_present_to_associated`, after containerizing | |
| `MEKE`, `VarMix`, `tv` | shared, union (grow per above) | `create_shadow_container_type`, union scope | See `shared_type_unions.md`. |
| `visc` | shared, union, free promotion | `create_shadow_container_type`, union scope | Shadow only actually needed inside `hor_bnd_diffusion`/`neutral_diffusion_calc_coeffs`, not `tracer_hordiff`'s own body. |
| `Reg`/`Tr` | shared, new union, array-of-struct | hand-authored decomposition (no sibling skill) | See dedicated section above; combine with `advect_tracer`'s decomposition work — same type, same gap. |
| `G`, `GV`, `US` | shared grid/scaling types | `convert_array_containers`'s own drop mechanism | Not a separate decision. |
| `CS` (`tracer_hor_diff_CS`) | private, 30 fields | `create_config_bundle_type`, physics-fields-only | See dedicated section above. |
| `CS%neutral_diffusion_CSp` (`neutral_diffusion_CS`) | private, nested, 55 fields, genuinely dereferenced in-tree | `create_config_bundle_type`, physics-fields-only | See dedicated section above. |
| `CS%hor_bnd_diffusion_CSp` (`hbd_CS`) | private, nested, 13 fields, genuinely dereferenced in-tree | `create_config_bundle_type`, physics-fields-only | See dedicated section above. |
| `build_reconstructions_1d` | widely-shared external leaf (19 files) | leave alone — view-marshal at call site | Same treatment as `thickness_to_dz`/`find_ustar`. |
| EOS-family calls (`calculate_density`, `calculate_density_derivs`) | pervasive per `EOS_bridge_design.md` | leave alone — view-marshal via the shared marshalling helper | See `EOS_bridge_design.md`. Helper built once in the combined infrastructure PR, not authored here. |

## Phase 2 execution order

1. **TreeRoot split** — `tracer_hordiff` → `tracer_hordiff_TR` + wrapper (Step 1d).
2. **`create_shadow_container_type`** — `MEKE`/`VarMix`/`visc`/`tv`'s type definitions and `Reg`/
   `Tr`'s hand-authored decomposition (shared with `advect_tracer`) are all built once by the
   combined shared-infrastructure PR (`shared_type_unions.md`), not here. This stage's own work
   is just the wrapper-side glue — instantiate each shadow from `tracer_hordiff_TR`'s own dummies,
   use it, copy back.
3. **`create_config_bundle_type`** — three separate bundles: `tracer_hor_diff_CS` (root),
   `neutral_diffusion_CS` (nested, one level down), `hbd_CS` (nested, one level down).
4. **Optional-array containerization** — `read_khdt_x`/`read_khdt_y`, `p_surf`
   (`neutral_diffusion_calc_coeffs`'s own), `coeff_l`/`coeff_r`: containerize first (item 5),
   then `convert_present_to_associated` (item 8).
5. **`convert_array_containers` — downward pass**, root to leaves (`tracer_hordiff_TR` →
   `hor_bnd_diffusion`/`neutral_diffusion_calc_coeffs`/`neutral_diffusion`/
   `tracer_epipycnal_ML_diff` → their own leaves). Include `stable_l`/`stable_r`/`stable_cell`
   (logical arrays) in this pass — ordinary classification, no special handling needed.
6. **`convert_array_containers` — upward pass**, `G`/`GV`/`US`-drop decisions.
7. **`convert_locals_to_containers`**, per subroutine once dummies are stable.
8. **`convert_present_to_associated`** — the optional dummies listed above, ahead of Phase 3.
9. **`hoist_container_marshalling`**, once, at `tracer_hordiff_TR`.

## Phase 3 wave order

- **Wave 1** (leaves, no in-tree callees): `compute_tapering_coeffs`, `interface_scalar`,
  `PLM_diff`, `increment_interface`, `calc_delta_rho_and_derivs`, `neutral_surface_T_eval`,
  `ppm_left_right_edge_values`, `fluxes_layer_method`, `hbd_grid`, `boundary_k_range`,
  `tracer_epipycnal_ML_diff` (only external calls, no in-tree dependency).
- **Wave 2** (depend only on Wave 1): `find_neutral_surface_positions_continuous`,
  `find_neutral_surface_positions_discontinuous`, `mark_unstable_cells`, `neutral_surface_flux`.
- **Wave 3** (depend on Waves 1-2): `neutral_diffusion_calc_coeffs`, `neutral_diffusion`,
  `hor_bnd_diffusion`.
- **Wave 4 (root, last)**: `tracer_hordiff_TR`.

Wrapper (`tracer_hordiff`) never bridged.

## Branch

`claude_tracer_hordiff_calltree`, created once before Phase 2 Stage 1.
