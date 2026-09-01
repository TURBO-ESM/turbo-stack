# Call-tree conversion plan: `btstep`, `btcalc`, `bt_mass_source`, `set_dtbt`

Four entry points, all `submodules/MOM6/src/core/MOM_barotropic.F90`, all sharing the same private
`barotropic_CS`. `btstep` was surveyed and planned first (hence the filename); `btcalc`,
`bt_mass_source`, and `set_dtbt` were added in a later session, mirroring the
`vertvisc_family`/`set_viscosity_family` pattern of surveying same-file siblings together rather
than in isolation. Kept the original filename rather than renaming to something like
`barotropic_family.md` — a rename would require updating every cross-reference to this file
across `shared_type_unions.md` and elsewhere for no functional benefit.
Produced by Phase 1 of `convert_calltree`. Read by Phase 2 and Phase 3.

## BLOCKING PREREQUISITE — RESOLVED (verified against source, this session)

**`BT_cont_type`'s wholesale conversion has landed.** Checked all 5 named files directly: `MOM_variables.F90`
defines all 14 array fields as `type(RealArray_t)` (`MOM_variables.F90:319-354`) and `alloc_BT_cont_type`
uses `%alloc(...)`; `MOM_continuity_PPM.F90` passes `BT_cont` fields straight to the container-native
`rec%add(...)` capture calls; `MOM_barotropic.F90` has 18 real `%view(...)` call sites on `BT_cont` fields
and zero raw dereferences; `MOM_dynamics_split_RK2.F90`/`MOM_dynamics_split_RK2b.F90` both use
`%associated()`/`%view()` for `h_u`/`h_v`. Everything below this notice that referred to this as blocking
is now historical context, not a live blocker — see "Other blockers, current as of this check" further down
for what's still actually open.

## BLOCKING PREREQUISITE (historical — see resolution notice above) — must land before Phase 2 Stage 1 of *either* `btstep`'s or `continuity()`'s campaign touches `BT_cont`

`BT_cont_type` (defined `submodules/MOM6/src/core/MOM_variables.F90:317-352`, 16 fields: 12 allocatable
2-D real arrays `FA_u_EE/FA_u_E0/FA_u_W0/FA_u_WW/uBT_WW/uBT_EE/FA_v_NN/FA_v_N0/FA_v_S0/FA_v_SS/vBT_SS/vBT_NN`,
2 allocatable 3-D real arrays `h_u`/`h_v`, 2 `group_pass_type` handles `pass_polarity_BT`/`pass_FA_uv`)
is dereferenced directly by **both** `MOM_continuity_PPM.F90` (the `continuity()` tree) and
`MOM_barotropic.F90` (this tree), and its `h_u`/`h_v` fields are also dereferenced directly
(not just forwarded opaquely) by `MOM_dynamics_split_RK2.F90` and `MOM_dynamics_split_RK2b.F90`.

A shadow (`BT_cont_container_type`) was previously built for the `continuity()` campaign, but it
lives only on `origin/MOD-continuity2`, a branch that diverged from this branch's history at
`dfbc8996` and has not been merged here. On this branch (`MOD-bstep`), `BT_cont_type` is still
100% raw in every consumer.

**Decision (user, this session):** since `BT_cont_type` is now needed, container-based, by two
call trees that are *both* being actively converted by this same effort, building a second
per-tree shadow for `btstep` (duplicating `MOD-continuity2`'s approach) doesn't make sense.
Instead, convert `BT_cont_type` itself wholesale — its 14 array fields become
`RealArray_t`/`IntArray_t` containers, once, propagating through every file that touches it:
`MOM_variables.F90` (type definition + `alloc_BT_cont_type`/`dealloc_BT_cont_type`),
`MOM_continuity_PPM.F90`, `MOM_barotropic.F90`, `MOM_dynamics_split_RK2.F90`,
`MOM_dynamics_split_RK2b.F90`. This supersedes `MOD-continuity2`'s shadow approach — that
branch's work is not being ported or reused.

This wholesale conversion is **not** one of `btstep`'s own 9 Phase-2 stages below — it's an
external, blocking dependency, completed before Stage 1 of this plan begins. It is **Stage 1 of
the combined shared-infrastructure PR** (`shared_type_unions.md`'s "Stages within the combined
PR" section), not a separately-scheduled piece of work — that PR is where this actually gets
executed, gated by its own commit/verify/CI discipline. No existing sibling skill is named for
"wholesale-convert a shared derived type across multiple files" — the closest fit is
`convert_array_containers`'s own field-conversion mechanics, applied to the type's field list and
every accessor rather than to one subroutine's dummy list; scope that work by hand when it's
picked up.

Once this lands, `BT_cont` arrives at every `btstep`-tree subroutine already container-based;
none of Stage 2 (shadow container types) is needed for it.

## Other blockers, current as of this check (verified against source and `shared_type_unions.md`, this session)

Three real items still stand between here and a Phase 2 start, none of them resolved by the
`BT_cont_type` work landing:

1. **The combined shared-infrastructure PR (`ADp`/`OBC`/`forces`/`VarMix`/`Waves`/`pbv`/`tv`/
   `vertvisc_type`/`MEKE` shadow types) has not landed.** Checked directly: `accel_diag_ptrs`
   (`ADp`) in `MOM_variables.F90` is still 100% raw Fortran pointers (`real, pointer, dimension(:,:,:)`),
   and no shadow container type for any of these 9 types exists anywhere in the source tree — grepped
   repo-wide for the obvious naming pattern, zero matches. Per `shared_type_unions.md`'s own
   sequencing note, `btstep`'s Stage 1 (TreeRoot split) doesn't need to wait for this — but Stage 2
   does, and `btstep` needs both `ADp` and `OBC` as union shadows per its own Step 2/3 table above.
   This blocks Phase 2 from getting past Stage 1.
2. **`BTCL_u`/`BTCL_v` array-of-struct decomposition is still a genuine skill-catalog gap.** No
   sibling skill decomposes a derived-type array into N field containers — the 11 subroutines
   listed in the Step 2/3 table (`find_uhbt`, `find_duhbt_du`, `uhbt_to_ubt`, `find_vhbt`,
   `find_dvhbt_dv`, `vhbt_to_vbt`, `set_local_BT_cont_types`, `adjust_local_BT_cont_types`,
   `set_up_BT_OBC`, `btloop_eta_predictor`, `apply_u_velocity_OBCs`, `apply_v_velocity_OBCs`) need
   hand-authored signature restructuring (flattening `BTCL_u`/`BTCL_v` into 10 separate field
   containers each) before `convert_array_containers`'s downward pass can reach them. Nothing built
   this capability this session — confirmed the same gap is still open for `tracer_type`/
   `tracer_registry_type` in `advect_tracer.md` and `OBC%segment` in `shared_type_unions.md`, none
   of which have been resolved either.
3. **The "optional struct dummy" mechanism is still unresolved**, confirmed still open in
   `shared_type_unions.md`'s own tracking note, which explicitly names `set_dtbt`'s `BT_cont`
   parameter (`optional, pointer`) as one of the instances. Blocks Step 8
   (`convert_present_to_associated`) for `set_dtbt` specifically — the other three entry points
   (`btstep`, `btcalc`, `bt_mass_source`) aren't affected by this particular gap.

Item 1 is the one actually blocking *all four* entry points in this plan from reaching Stage 2;
items 2 and 3 block specific subroutines/entry points within the plan once Stage 2 is reachable.

## Hard precondition checks

- `btstep`'s external signature (26 dummies, listed below) is fixed by the dynamics-core
  callers (`MOM_dynamics_split_RK2.F90:726,1023`, `MOM_dynamics_split_RK2b.F90:703,937`) and must
  not change. `btcalc`, `bt_mass_source`, `set_dtbt` each have their own frozen signatures — see
  their own sections below.
- Shared-descendant check (repo-wide, exact-word grep): **every one of `btstep`'s 24 descendants
  is module-private to `MOM_barotropic.F90` and has zero callers outside this file.**
  `btcalc`/`bt_mass_source` are confirmed fully self-contained w.r.t. `btstep`'s descendant
  set — zero overlap, only infra calls (`MOM_error`, checksums) beyond their own bodies.
  **`set_dtbt` is the one genuine shared-descendant case**: it calls `find_face_areas` and
  `BT_cont_to_face_areas`, both already `btstep_TR`'s own descendants. Since `set_dtbt` is now in
  scope in this same plan, this resolves the same way `Set_pbce_Bouss`/`set_v_at_u` did for other
  multi-entry-point families — both subroutines convert **once** and get called from **both**
  `btstep_TR`'s tree and `set_dtbt`'s own tree, not planned or converted twice. Updated in the
  descendant list and Phase 3 wave order below.
- All four entry points share `barotropic_CS` — bundled once, per the union of all four's field
  usage (see the updated bundle section below), not per-entry-point.

## Step 1d — wrapper cases (four separate Case-3 splits)

All four are **Case 3** — distinct subroutines, called directly, no wrapper/alias.
1. `btstep` → `btstep_TR`, new `btstep` wrapper.
2. `btcalc` → `btcalc_TR`, new `btcalc` wrapper.
3. `bt_mass_source` → `bt_mass_source_TR`, new `bt_mass_source` wrapper.
4. `set_dtbt` → `set_dtbt_TR`, new `set_dtbt` wrapper.
Each wrapper is a pure pass-through matching its own current external signature exactly, no
`bind(C)`. None of the four wrappers is ever bridged.

## External signatures (frozen — do not change)

- **`btstep`**: `btstep(U_in, V_in, eta_in, dt, bc_accel_u, bc_accel_v, forces, pbce, eta_PF_in,
  U_Cor, V_Cor, accel_layer_u, accel_layer_v, eta_out, uhbtav, vhbtav, G, GV, US, CS, visc_rem_u,
  visc_rem_v, SpV_avg, ADp, OBC, BT_cont, eta_PF_start, taux_bot, tauy_bot, uh0, vh0, u_uh0,
  v_vh0, etaav)` — `MOM_barotropic.F90:479-483`. Only `etaav` is `optional`;
  `ADp`/`OBC`/`BT_cont`/`eta_PF_start`/`taux_bot`/`tauy_bot`/`uh0`/`u_uh0`/`vh0`/`v_vh0` are
  `pointer` (checked via `associated()`, already bridge-friendly — not `present()`/`optional`).
- **`btcalc`**: `btcalc(h, G, GV, CS, h_u, h_v, may_use_default, OBC)` —
  `MOM_barotropic.F90:4650-4676`. `h_u`, `h_v` (arrays), `may_use_default` (scalar logical) are
  plain `optional`; `OBC` is `optional, pointer`. **`OBC` is confirmed dead code** — declared but
  never referenced anywhere in the body. Since the campaign convention never changes a target's
  own signature, it's carried through unused in the bridge, not dropped.
- **`bt_mass_source`**: `bt_mass_source(h, eta, set_cor, G, GV, CS)` —
  `MOM_barotropic.F90:5594-5604`. No optional or pointer dummies at all.
- **`set_dtbt`**: `set_dtbt(G, GV, US, CS, pbce, gtot_est, BT_cont, eta, SSH_add)` —
  `MOM_barotropic.F90:3794-3810`. `pbce`, `gtot_est`, `eta`, `SSH_add` are plain `optional`;
  `BT_cont` is `optional, pointer`. `BT_cont` is confirmed **opaque** here — only
  `associated(BT_cont)` is tested, then the whole pointer is forwarded into
  `BT_cont_to_face_areas`; `set_dtbt` never dereferences a `BT_cont_type` field itself.

## Full descendant list

**`btstep`'s own 24 descendants** (all module-private to `MOM_barotropic.F90`, zero external
callers):

| Subroutine/function | Direct in-tree callees | Notes |
|---|---|---|
| `btstep_ubt_from_layer` (3668) | none | leaf |
| `btstep_find_Cor` (3156) | none | leaf |
| `btstep_layer_accel` (3720) | none | leaf |
| `set_local_BT_cont_types` (5213) | none (infra only) | leaf |
| `find_face_areas` (5500) | none | leaf, pure arithmetic. **Shared with `set_dtbt`'s tree** — see below, converts once. |
| `adjust_local_BT_cont_types` (5364) | none | leaf, pure arithmetic |
| `swap` (5491) | none | leaf, trivial scalar swap, no derived types |
| `BT_cont_to_face_areas` (5461) | none | leaf, pure arithmetic. **Shared with `set_dtbt`'s tree** — see below, converts once. |
| `find_uhbt` (4947, pure function) | none | leaf; called directly by `btstep` (1300-1694), `btstep_timeloop`, `btloop_eta_predictor`, `apply_u_velocity_OBCs` |
| `find_duhbt_du` (4972, pure function) | none | leaf; called directly by `btstep` only (1373-1402) |
| `find_vhbt` (5081, pure function) | none | leaf; called directly by `btstep`, `btstep_timeloop`, `btloop_eta_predictor`, `apply_v_velocity_OBCs` |
| `find_dvhbt_dv` (5105, pure function) | none | leaf; called directly by `btstep` only (1399-1402) |
| `truncate_velocities` (3234) | none | leaf; called from `btstep_timeloop`, gated by `CS%clip_velocity` |
| `btloop_find_PF` (3369) | none | leaf; called from `btstep_timeloop` |
| `btloop_add_dyn_PF` (3453) | none | leaf; called from `btstep_timeloop` |
| `btloop_update_v` (3504) | none | leaf; called from `btstep_timeloop` |
| `btloop_update_u` (3593) | none | leaf; called from `btstep_timeloop` |
| `uhbt_to_ubt` (4997, function) | none (self-contained Newton iteration) | leaf; called only from `set_up_BT_OBC` |
| `vhbt_to_vbt` (5130, function) | none (self-contained Newton iteration) | leaf; called only from `set_up_BT_OBC` |
| `btloop_eta_predictor` (3272) | `find_uhbt`, `find_vhbt` | called from `btstep_timeloop` |
| `apply_u_velocity_OBCs` (3929) | `find_uhbt` | called from `btstep_timeloop` |
| `apply_v_velocity_OBCs` (4115) | `find_vhbt` | called from `btstep_timeloop` |
| `set_up_BT_OBC` (4464) | `uhbt_to_ubt`, `vhbt_to_vbt` | called from `btstep` directly |
| `btstep_timeloop` (2373) | `truncate_velocities`, `btloop_eta_predictor`, `btloop_find_PF`, `btloop_add_dyn_PF`, `btloop_update_v`, `btloop_update_u`, `find_face_areas`, `apply_u_velocity_OBCs`, `apply_v_velocity_OBCs`, `find_uhbt`, `find_vhbt` | called from `btstep` directly |
| **`btstep_TR`** (root, post-rename) | `btstep_ubt_from_layer`, `btstep_find_Cor`, `btstep_timeloop`, `btstep_layer_accel`, `set_local_BT_cont_types`, `find_face_areas`, `set_up_BT_OBC`, `adjust_local_BT_cont_types`, `swap`, `BT_cont_to_face_areas`, `find_uhbt`, `find_duhbt_du`, `find_vhbt`, `find_dvhbt_dv` | root |

**`btcalc`'s descendants**: none beyond infra (`MOM_error`, `uvchksum`/`hchksum`, debug-gated).
Confirmed zero overlap with `btstep`'s descendant set. `btcalc_TR` is a leaf from Phase 3's own
perspective.

**`bt_mass_source`'s descendants**: none beyond `MOM_error` (infra). Confirmed zero overlap.
`bt_mass_source_TR` is a leaf.

**`set_dtbt`'s descendants**: `find_face_areas` and `BT_cont_to_face_areas` — **both already in
`btstep`'s own descendant list above.** Also calls `scalar_SAL_sensitivity` (infra,
`CS%SAL_CSp` forwarded opaquely, same treatment as `btstep`'s own use of it), plus
`cpu_clock_begin/end`, `min_across_PEs`, `chksum0` (all infra). `set_dtbt_TR` depends on
`find_face_areas`/`BT_cont_to_face_areas`, same as `btstep_TR` does — both roots share these two
leaves; neither plan re-converts them independently.

**Confirmed out of scope** (siblings in the same module/file, reached from neither `btstep` nor
`btcalc`/`bt_mass_source`/`set_dtbt`): `barotropic_init`, `barotropic_end`, `initialize_BT_OBC`,
`destroy_BT_OBC` (reached only from `barotropic_init`/`barotropic_end`), `barotropic_get_tav`
(reached only from `MOM_hor_visc.F90`'s `horizontal_viscosity` — a tiny accessor with a single
external caller, already accounted for as a leaf dependency there; not pursued as its own entry
point), `register_barotropic_restarts` (reached only from restart-registration, init-time). Note
`btcalc` and `set_dtbt` each also have exactly one in-file call site, both confirmed inside
`barotropic_init` (`MOM_barotropic.F90:6598` and `:6578` respectively) — init-time-only uses of
these two entry points, not additional descendants to worry about.

Infra calls confirmed opaque/irrelevant (plain scalars/strings, no derived types, or derived
types forwarded whole with no field dereference of interest): `cpu_clock_begin/end`,
`MOM_error`/`MOM_mesg`, `scalar_SAL_sensitivity`, `Filt_accum`, `wave_drag_calc`,
`uvchksum`/`hchksum`/`Bchksum`, `post_data`, `HA_accum` — leave alone.

**Halo-exchange calls (`create_group_pass`/`start_group_pass`/`do_group_pass`/
`complete_group_pass`/`pass_vector`, ~74 in-tree call sites) — the routines are left alone
(external `MOM_domains` infra, out of scope), but their array arguments are not uniformly
opaque.** `pass_var` does **not** appear in-tree at all — its only call site (`line 6374`) is
inside `barotropic_init`, out of scope. `pass_vector` has exactly 2 in-tree call sites, both at
`btstep:1283-1284`, on `ubt`/`vbt`/`uhbt`/`vhbt` — locals declared inside `btstep`'s own body
(distinct from same-named dummies elsewhere in the tree). Several `create_group_pass`/
`do_group_pass` calls pass tree-owned dummies directly (`etaav`, `uhbtav`, `vhbtav`) or locals
that Step 7 containerizes. `CS%pass_*` (the `group_pass_type` handles) and `CS%BT_Domain`/
`G%Domain` are not array data and stay exactly as-is (already excluded from the `barotropic_CS`
bundling work, above). **Handling: once an argument is a container, pass it by `%view` (a live
pointer into the container's own backing storage) rather than copying** — `array_container_lessons`'
documented in-place pattern for any still-raw external callee sitting inside an otherwise-
containerized body; `%view` means no `%copy2F` copy-back is needed afterward. This is automatic
behavior of `convert_array_containers` (Stages 5-7), not a separate target decision. **Flag for
Stage 9 whole-tree verification, not assumed safe by default:** the two `pass_vector` calls at
1283-1284 use `complete=.false.`/`complete=.true.` to overlap two halo exchanges for latency
hiding — correct only if the `%view` pointer for `ubt`/`vbt` stays valid across the window
between the two calls (true as long as the container isn't reallocated in between, but confirm
explicitly rather than assume).

## Step 2/3 — target classification

| Target | Classification | Skill | Settings / notes |
|---|---|---|---|
| Every raw `real`/`integer` array dummy across all 25 subroutines (dozens: `U_in`, `V_in`, `ubt`, `vbt`, `eta`, `f_4_u`/`f_4_v`, `gtot_E/W/N/S`, `wt_vel`/`wt_eta`/`wt_accel`/`wt_trans`/`wt_accel2`, etc.) | raw array dummy | `convert_array_containers` | Standard treatment. Note two non-grid-macro shapes for the sub-skill to handle: `f_4_u`/`f_4_v` have a fixed leading dim of 4; `wt_vel`/`wt_eta`/`wt_accel`/`wt_trans`/`wt_accel2` are 1-D, sized by runtime scalars `nstep+nfilter`(+1), not `SZI_`/`SZJ_` macros. |
| `etaav` (btstep, array, optional) | optional array dummy | `convert_array_containers` (default direction) then `convert_present_to_associated` | Confirmed **not** forwarded to any callee — does not cascade, so the default direction applies, not `convert_optional_args_to_containers`. **Deviates from `skill_workflow.md`'s suggestion** to run `convert_optional_args_to_containers` at the root — that doc predates this survey; the cascading-branch risk it warns about does not materialize for `etaav` specifically. |
| `dt_baroclinic` (scalar, optional; `set_local_BT_cont_types`, `adjust_local_BT_cont_types`) | optional scalar | `convert_present_to_associated` | No containerization needed (scalar). |
| `eta`, `add_max` (`find_face_areas`; `eta` is array, `add_max` scalar, both optional) | optional array/scalar | `convert_array_containers` (for `eta`) then `convert_present_to_associated` (both) | Neither forwarded further — leaf subroutine. |
| `halo` (scalar, optional; `BT_cont_to_face_areas`) | optional scalar | `convert_present_to_associated` | — |
| `Cor_bracket_bug` (scalar, optional; `btloop_update_v`) | optional scalar | `convert_present_to_associated` | — |
| `G` (`ocean_grid_type`), `GV` (`verticalGrid_type`), `US` (`unit_scale_type`) | shared, ubiquitous grid/scaling types | handled by `convert_array_containers`'s own G/GV/US-drop mechanism (Phase 2 item 6) | Not a separate target skill decision. Note: `US` is declared but **never dereferenced** in `set_local_BT_cont_types`, `find_face_areas`, `set_up_BT_OBC`, `adjust_local_BT_cont_types`, `btloop_eta_predictor`, `btloop_find_PF`, `btloop_add_dyn_PF`, `btloop_update_v`, `btloop_update_u`, `apply_u_velocity_OBCs`, `apply_v_velocity_OBCs`, `BT_cont_to_face_areas` — flag all of these for the upward-pass drop decision. `G` is likewise unused in `btloop_update_v`/`btloop_update_u`/`btloop_eta_predictor`/`btloop_add_dyn_PF`. |
| `MS` (`memory_size_type`, private, 4 int fields `isdw/iedw/jsdw/jedw`) | private, unshared, bounds-carrier only (no array fields) | leave alone | Confirmed zero external callers/references (grep repo-wide). Same treatment class as G/GV during the upward pass — not a shadow or bundle target; already minimal. |
| `local_BT_cont_u_type` / `local_BT_cont_v_type` (private, 10 real scalar fields each; used as arrays-of-struct `BTCL_u`/`BTCL_v`) | array-of-custom-struct, no fixed rule covers it | **decompose into per-field containers** (user decision) | Flatten each into 10 separate `RealArray_t` containers, matching `BT_cont_type`'s own struct-of-arrays shape — needed because AMReX has no array-of-custom-struct equivalent (only per-field contiguous arrays); every consumer (`find_uhbt`, `find_duhbt_du`, `uhbt_to_ubt`, `find_vhbt`, `find_dvhbt_dv`, `vhbt_to_vbt`, `set_local_BT_cont_types`, `adjust_local_BT_cont_types`, `set_up_BT_OBC`, `btloop_eta_predictor`, `apply_u_velocity_OBCs`, `apply_v_velocity_OBCs`) reads the whole tuple together, so no computational-performance loss, only more arguments at call sites. **No existing sibling skill natively decomposes a derived-type array into N field containers** — this requires hand-authored signature restructuring (rewrite these 11 subroutines to take 10 separate real arrays/containers instead of one `BTCL_u`/`BTCL_v` dummy) before/alongside the normal `convert_array_containers` passes; verify carefully, this is a gap in the existing skill catalog. |
| `BT_cont_type` (`BT_cont`) | shared with `continuity()` tree + `MOM_dynamics_split_RK2[b].F90` | **wholesale conversion — see Blocking Prerequisite above**, not `create_shadow_container_type` | By the time Phase 2 Stage 1 of this plan runs, `BT_cont` should already arrive container-based; Stage 2 has nothing to do for it. |
| `ADp` (`accel_diag_ptrs`) | shared, confirmed dereferenced, not opaque | `create_shadow_container_type` — **union shadow** | See `shared_type_unions.md`. |
| `OBC` (`ocean_OBC_type`) | shared, confirmed dereferenced | `create_shadow_container_type` — **union shadow** | See `shared_type_unions.md`. |
| `forces` (`mech_forcing`) | shared, confirmed dereferenced (`forces%taux`, `forces%tauy`, `forces%rigidity_ice_u/v` in `btstep`) | `create_shadow_container_type` — **union shadow** | See `shared_type_unions.md` for the full field list and the per-field `associated()`-vs-unchecked treatment this file originally established. |
| `CS` (`barotropic_CS`, private, 173 fields, confirmed opaque outside `MOM_barotropic.F90`) | private control structure, fields recur together | `create_config_bundle_type` — **physics fields only** (user decision) | Cluster the fields that feed actual computation (grid-derived arrays `IdxCu`/`IdyCv`/`IDatu`/`IDatv`/`dy_Cu`/`dx_Cv`/`bathyT`/`OBCmask_u`/`OBCmask_v`/`IareaT_OBCmask`, physics/config scalars `vel_underflow`/`clip_velocity`/`linear_wave_drag`/`CFL_trunc`/`maxCFL_BT_cont`/`Sadourny`/`use_filter`/`calculate_SAL`/`linear_freq_drag`, accumulator arrays `frhatu`/`frhatv`/`frhatu1`/`frhatv1`/`ubtav`/`vbtav`/`eta_cor`/`q_D`, wide-halo bounds `isdw`/`iedw`/`jsdw`/`jedw`) into a few purpose-built bundle types nested back into `barotropic_CS`, mirroring `continuity_PPM_CS`'s `reconstruction_opts_type`/`transport_adjust_opts_type` precedent. **Additional fields found when `btcalc`/`bt_mass_source`/`set_dtbt` were added to this plan** (all scalars, bundle alongside the above): `debug`, `hvel_scheme`, `module_is_initialized`, `Rho_BT_lin`, `split` (from `btcalc`/`bt_mass_source`); `bebt`, `BT_Coriolis_scale`, `dtbt`, `dtbt_fraction`, `dtbt_max`, `G_extra`, `Nonlinear_continuity`, `tidal_sal_bug` (from `set_dtbt` — note `dtbt`/`dtbt_max` are **outputs**: `set_dtbt` computes and writes them, `btstep`/`btstep_TR` presumably reads them back later purely through the shared, now-bundled `CS`). **Exclude from bundling**: the 64 `id_*` diagnostic-ID scalars (drive `post_data` only, never cross to C++), the 12 `pass_*` halo-pass handles, and the nested CS pointers (`SAL_CSp`, `HA_CSp`, `Drag_CS`, `Filt_CS_u`/`Filt_CS_v`, `BT_OBC`, `Time`, `diag`, `BT_Domain`, `debug_BT_HI`) — these stay direct fields of `barotropic_CS`, untouched. Exact clustering into named bundle types is `create_config_bundle_type`'s own call at execution time, done **once**, informed by the union of all four entry points' usage — no reconciliation risk since all four are decided together in this same plan. |
| `btcalc`'s own dummies (`h`, `h_u`, `h_v` optional, `may_use_default` optional scalar) | raw/optional array dummies | `convert_array_containers` (+ `convert_present_to_associated` for `h_u`/`h_v`/`may_use_default`) | `h_u`/`h_v` are plain raw arrays with **zero dependency on `BT_cont_type`'s identity** — even though some callers pass `CS%BT_cont%h_u`/`h_v` as the actual arguments, `btcalc` itself only ever sees a generic `intent(in)` 3-D array. `btcalc`'s own conversion does not need to wait on the `BT_cont_type` blocking prerequisite above. |
| `bt_mass_source`'s own dummies (`h`, `eta`, `set_cor`) | raw array dummies + plain scalar logical | `convert_array_containers` | No optionals, no pointers — the simplest signature of the four entry points. |
| `set_dtbt`'s own dummies (`pbce`, `gtot_est`, `eta`, `SSH_add` — all optional; `BT_cont` optional+pointer) | optional array/scalar dummies + opaque struct | `convert_array_containers` (`pbce`/`eta`) + `convert_present_to_associated` (all five) for the arrays/scalars; `BT_cont` needs no shadow, confirmed opaque | `BT_cont` extends the optional-struct open item (`shared_type_unions.md`) — same unresolved category as `horizontal_viscosity`'s `BT`/`TD`/`ADp`/`STOCH`. |
| `BT_OBC_type` (private, 32 fields: 10 real + 2 int allocatable arrays, 2 logical scalars, 16 int scalars, 2 `group_pass_type` handles; confirmed zero external references) | private control structure, fields recur together across `set_up_BT_OBC`/`apply_u_velocity_OBCs`/`apply_v_velocity_OBCs` | `create_config_bundle_type` | Unlike `barotropic_CS`, essentially all fields are genuine OBC state feeding computation — no diagnostic-ID dead weight — so the fixed rule applies directly without a scale-driven Step 3 decision. Keep `u_OBCs_on_PE`/`v_OBCs_on_PE` and the 2 `group_pass_type` handles as plain fields; cluster the arrays (wave-speed/column-extent `Cg_u`/`Cg_v`/`dZ_u`/`dZ_v`, OBC-state `uhbt`/`vhbt`/`ubt_outer`/`vbt_outer`/`SSH_outer_u`/`SSH_outer_v`/`u_OBC_type`/`v_OBC_type`, index-range integers) — exact grouping is that skill's own call. |
| `swap`'s two scalar `real` dummies | plain scalars, no derived type | nothing to do | Bridges directly in Phase 3 wave 1 with a trivial signature. |

## `ADp`, `OBC`, `forces` shadows — see `shared_type_unions.md`

All three are needed, container-based, by more than one entry point now (as of surveying
`horizontal_viscosity` and `vertvisc`/`vertvisc_coef`). Their authoritative union field lists
and reasoning (including why `OBC` gets a union shadow rather than a `BT_cont_type`-style
wholesale conversion — the same 13-file blast-radius argument, not re-duplicated here) now live
in `.claude/calltree-plans/shared_type_unions.md`. This file's own contribution to those unions
was: `ADp`'s original field list (`bt_pgf_u/v`, `bt_cor_u/v`, `bt_lwd_u/v`, `diag_hfrac_u/v`,
`diag_hu/hv`, `visc_rem_u/v`), `OBC`'s original 2-tree field list (with `continuity()`), and
`forces`'s `taux`/`tauy`/`rigidity_ice_u/v` treatment (including the "preserve the source's
existing `associated()`-vs-unchecked behavior exactly" reasoning, which still applies and is
carried into the shared file).

## Phase 2 execution order (for all four entry points)

1. **TreeRoot split** — four separate rename+wrapper pairs (see Step 1d above).
2. **`create_shadow_container_type`** — `ADp`/`OBC`/`forces`'s type definitions are built once by
   the combined shared-infrastructure PR (`shared_type_unions.md`), not here. This stage's own
   work is just the wrapper-side glue — instantiate each shadow and copy back, in each of the
   four wrappers that needs them (`btstep`: all three; `set_dtbt`: none directly, `BT_cont` stays
   opaque; `btcalc`/`bt_mass_source`: neither takes any of these). *(`BT_cont` is excluded here —
   handled by the external blocking prerequisite below, a different kind of dependency than the
   shared-infrastructure PR: that PR only needs to land before this stage runs; `BT_cont_type`'s
   wholesale conversion must land before this entire plan's Phase 2 Stage 1 runs at all, for
   `btstep`/`set_dtbt` specifically.)*
3. **`create_config_bundle_type`** — `barotropic_CS` (physics-fields-only scope, informed by the
   union of all four entry points' usage) and `BT_OBC_type` (full scope). Two invocations total,
   not four — the bundle is shared infrastructure, built once.
4. **Optional-array containerization** — `etaav` (btstep), `eta` (find_face_areas, `pbce`
   (set_dtbt), `eta`/`SSH_add`/`gtot_est` (set_dtbt), `h_u`/`h_v`/`may_use_default` (btcalc);
   default direction throughout (confirmed non-cascading for every one of these).
5. **`convert_array_containers` — downward pass**, each of the four roots to its own leaves.
   **Before this pass reaches `btloop_eta_predictor`, `find_uhbt`, `find_duhbt_du`,
   `uhbt_to_ubt`, `find_vhbt`, `find_dvhbt_dv`, `vhbt_to_vbt`, `set_local_BT_cont_types`,
   `adjust_local_BT_cont_types`, `set_up_BT_OBC`, `apply_u_velocity_OBCs`,
   `apply_v_velocity_OBCs`**, the `BTCL_u`/`BTCL_v` decomposition (see target table) must already
   be done — those 11 subroutines' signatures need the 10-field flattening first. `find_face_areas`/
   `BT_cont_to_face_areas` get converted once, reachable from both `btstep_TR`'s downward pass and
   `set_dtbt_TR`'s — do not convert them twice or let the two passes disagree on the result.
6. **`convert_array_containers` — upward pass**, leaves to root, G/GV/US/MS-drop decisions
   (including the flagged never-dereferenced `US`/`G` instances above) and Step 2b promotions.
7. **`convert_locals_to_containers`**, per subroutine, once dummies are stable.
8. **`convert_present_to_associated`** — `etaav`, `dt_baroclinic` (×2 call sites), `add_max`,
   `halo`, `Cor_bracket_bug` (all `btstep`-tree); `h_u`, `h_v`, `may_use_default` (`btcalc`);
   `pbce`, `gtot_est`, `eta`, `SSH_add` (`set_dtbt`).
9. **`hoist_container_marshalling`**, once per entry point (four invocations: `btstep_TR`,
   `btcalc_TR`, `bt_mass_source_TR`, `set_dtbt_TR`).

## Phase 3 wave order (leaf-to-root, across all four entry points)

- **Wave 1** (no in-tree callees): `btstep_ubt_from_layer`, `btstep_find_Cor`,
  `btstep_layer_accel`, `set_local_BT_cont_types`, `find_face_areas`,
  `adjust_local_BT_cont_types`, `swap`, `BT_cont_to_face_areas`, `truncate_velocities`,
  `btloop_find_PF`, `btloop_add_dyn_PF`, `btloop_update_v`, `btloop_update_u`, `find_uhbt`,
  `find_duhbt_du`, `find_vhbt`, `find_dvhbt_dv`, `uhbt_to_ubt`, `vhbt_to_vbt`. Also wave 1 (no
  in-tree callees of their own, independent of `btstep`'s tree): `btcalc_TR`, `bt_mass_source_TR`
  (both roots, but leaves from Phase 3's perspective — their only calls are infra, already
  excluded).
- **Wave 2** (callees all in wave 1): `btloop_eta_predictor`, `apply_u_velocity_OBCs`,
  `apply_v_velocity_OBCs`, `set_up_BT_OBC`.
- **Wave 3** (callees in waves 1-2): `btstep_timeloop`.
- **Wave 4 (roots, last)**: `btstep_TR` (calls wave-1/2/3 descendants) and `set_dtbt_TR` (calls
  `find_face_areas`/`BT_cont_to_face_areas`, both wave 1 — ready at the same point `btstep_TR`
  is, but bridged as its own independent root, not part of `btstep_TR`'s own tree). None of the
  four wrappers (`btstep`, `btcalc`, `bt_mass_source`, `set_dtbt`) is ever bridged.

## Branch

`claude_btstep_calltree`, created once before Phase 2 Stage 1 — one branch for all four entry
points, same deliberate multi-entry-point choice already made for `vertvisc_family`/
`set_viscosity_family`.
