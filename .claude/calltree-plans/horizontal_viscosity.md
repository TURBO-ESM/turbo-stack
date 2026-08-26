# Call-tree conversion plan: `horizontal_viscosity`

Entry point: `horizontal_viscosity`, `src/parameterizations/lateral/MOM_hor_visc.F90:270-2451`.
Produced by Phase 1 of `convert_calltree`. Read by Phase 2 and Phase 3.

Cross-reference: `.claude/calltree-plans/shared_type_unions.md`, the authoritative source for
every derived-type union this plan touches (`ADp`, `OBC`, `VarMix`) — this file no longer
carries its own copies of those field lists.

## Hard precondition checks

- `horizontal_viscosity`'s external signature (21 dummies, listed below) is fixed by the
  dynamics-core callers: `MOM_dynamics_unsplit_RK2.F90:284`, `MOM_dynamics_split_RK2b.F90:577,887`,
  `MOM_dynamics_unsplit.F90:272`, `MOM_dynamics_split_RK2.F90:962,1752` — same 4 files as
  `continuity()`/vert-friction, 6 call sites total. No other file calls it (confirmed).
- Shared-descendant check: the 3 same-file helpers (`smooth_x9_h`, `smooth_x9_uv`, `smooth_GME`)
  and the GME leaves (`barotropic_get_tav`, `thickness_diffuse_get_KH`) have zero external
  callers of their own. `calc_QG_slopes` has zero external callers itself, but **what it calls
  does not** — `calc_isoneutral_slopes` is independently reached from `MOM.F90`'s main step
  (`calc_resoln_function`/`calc_slope_functions`) and from `MOM_MEKE.F90` — see "QG-Leith scope
  boundary" below for how this is handled. `ZB2020_lateral_stress`'s entire subtree (13 nodes,
  fully traced) has zero external callers anywhere — confirmed self-contained. `ADp`/`OBC` are
  shared derived types, not shared subroutines — handled separately below.

## Step 1d — wrapper case

**Case 3.** `horizontal_viscosity` is one subroutine, called directly under its own name —
`public horizontal_viscosity, hor_visc_init, hor_visc_end, hor_visc_vel_stencil` — no existing
wrapper, no alias. Phase 2 Stage 1 must:
1. Rename the current implementation `horizontal_viscosity` → `horizontal_viscosity_TR`.
2. Author a new `horizontal_viscosity` wrapper (pure pass-through call to
   `horizontal_viscosity_TR`), matching the current external signature exactly, no `bind(C)`.
`horizontal_viscosity_TR` is bridged in Phase 3's last wave; the wrapper is never bridged.

**Also part of Stage 1 (see "Monolith split" below):** unlike `continuity()`/`btstep`, this
entry point's body needs restructuring beyond the rename+wrapper — Stage 1 additionally splits
`horizontal_viscosity_TR`'s 2182-line body into named per-scheme subroutines it calls.

## `horizontal_viscosity`'s own external signature (frozen, from Step 1a — do not change)

```
horizontal_viscosity(u, v, h, uh, vh, diffu, diffv, MEKE, VarMix, G, GV, US, CS, tv, dt, OBC, BT,
TD, ADp, hu_cont, hv_cont, STOCH)
```
— `MOM_hor_visc.F90:270-306`. Optional dummies: `OBC` (`optional, pointer`), `BT`, `TD`, `ADp`,
`hu_cont`, `hv_cont`, `STOCH` (all plain `optional`) — **7 optional dummies, 4 of them full
derived-type structs** (`BT`, `TD`, `ADp`, `STOCH`), not just arrays/scalars. See "Open item —
optional struct dummies" below; this is new relative to `btstep`, which had only one true
`optional` (`etaav`, an array) plus several `pointer`-not-`optional` structs.

## Monolith split (Stage 1, user decision)

The pre-existing audit (`hor_visc_call_tree_audit.md`) recommended splitting the 2182-line body's
9+ internal `if (CS%use_*)` branches into named subroutines before container conversion.
**Decision (user, this session): do this**, as part of Stage 1, before any container work.

Confirmed major branches, each with its own external call dependencies (clear split
boundaries):
- **GME** (`CS%use_GME`) — calls `barotropic_get_tav`, `thickness_diffuse_get_KH`, `smooth_GME`.
  Two separate `if (CS%use_GME)` blocks exist in the current body (lines ~578-665 and
  ~1972-2032) — confirm both get folded into one new subroutine, not two.
- **QG-Leith** (`CS%use_QG_Leith_visc`) — calls `thickness_to_dz`, `calc_QG_slopes`,
  `calc_QG_Leith_viscosity`.
- **ZB2020** (`CS%use_ZB2020`) — calls `ZB2020_copy_gradient_and_thickness` (line ~1647),
  `ZB2020_lateral_stress` (line ~2447).
- **Leithy** (`CS%use_Leithy`) — calls `smooth_x9_h`, `smooth_x9_uv` (both additionally gated by
  `CS%smooth_Ah` for the former).

**Not yet mapped to precise line ranges — Stage 1's own job, not resolved in Phase 1:** the
remaining flags (`use_circulation`, `use_beta_in_Leith`, `use_cont_thick`,
`use_cont_thick_bug`, `use_land_mask`) and the anisotropic-tensor variant appear to be
finer-grained switches inside the core Smagorinsky/Leith/biharmonic computation rather than
separately-callable schemes with their own external dependencies — Phase 1's survey traced
external call dependencies, not every internal branch of the 2182-line body. Stage 1 execution
needs to read the full body to decide whether these stay inside one `hor_visc_core` subroutine
or warrant further splitting. Suggested resulting structure (names illustrative, Stage 1 may
refine): `hor_visc_core` (default Smagorinsky/Leith/biharmonic path plus the not-yet-mapped
flags), `hor_visc_GME`, `hor_visc_QG_Leith`, `hor_visc_ZB2020`, `hor_visc_Leithy` — all new
same-file private subroutines called from `horizontal_viscosity_TR`'s body under the same
`if (CS%use_*)` gates that exist today.

## QG-Leith scope boundary (user decision)

`calc_QG_slopes` (`MOM_lateral_mixing_coeffs.F90:1360`) has zero external callers itself — a
true descendant. But it calls `calc_isoneutral_slopes`, which is independently reached from
`MOM.F90`'s main step (via `calc_resoln_function`/`calc_slope_functions`, called at
`MOM.F90:807,2209,2236` and `MOM.F90:1296,1473,2211,2238`) and from `MOM_MEKE.F90:1883`'s
`ML_MEKE_calculate_features` — not just a big subtree, genuinely borrowed infrastructure.
Below that, `calculate_density_derivs`/`calculate_density_second_derivs`/`calculate_spec_vol`
dispatch through `EOS%type%...` on a `class(EOS_base), allocatable` polymorphic component (9
concrete implementations: `linear_EOS`, `UNESCO_EOS`, `buggy_Wright_EOS`, `Wright_full_EOS`,
`Wright_red_EOS`, `Jackett06_EOS`, `TEOS10_EOS`, `Roquet_rho_EOS`, `Roquet_SpV_EOS`), used by 59
files repo-wide.

**Decision (user, this session): the container/bridge boundary sits at `calc_QG_slopes` itself.**
As part of the monolith split, `calc_QG_slopes` becomes (or stays, if already separately
callable) a normal in-tree target — its own dummies (`h`, `tv`, `dt`, `G`, `GV`, `US`,
`slope_x`, `slope_y`, `CS`, `OBC`) get containerized and it gets bridged like any other leaf in
Phase 3. But its own call into `calc_isoneutral_slopes` (and everything below — `find_eta`,
`find_dz_for_eta`, `int_specific_vol_dp`, the EOS dispatch layer) **stays completely untouched,
raw Fortran** — marshalled at the call site via container `%view`, the same still-raw-external-
callee pattern already used for `pass_vector` in `btstep`'s plan. Never push containers or
bridging into `calc_isoneutral_slopes` or anything below it — out of bounds for this campaign,
shared with `MOM.F90` and `MOM_MEKE.F90`.

`calc_QG_Leith_viscosity` (leaf apart from one `post_data` call) and `thickness_to_dz` (leaf,
only calls `MOM_error`, `tv` forwarded opaquely) are both ordinary in-tree leaves — no boundary
concern, they don't reach the shared EOS layer.

## ZB2020 (user decision: include now)

Confirmed fully self-contained and tractable — zero shared descendants anywhere in its 13-node
subtree (verified node-by-node against the current repo state, not just trusted from the prior
audit). `ANN_CS` (the neural-net weights/config type `compute_stress_ANN_collocated` reaches via
`ANN_apply_array_sio` in `MOM_ANN.F90`) is effectively private to this path in production — its
only other consumers repo-wide are standalone unit/timing-test drivers
(`test_MOM_ANN.F90`/`time_MOM_ANN.F90`), not part of any model call tree.

**Decision (user, this session): include ZB2020 in this campaign now**, despite the original
audit ranking this whole file lowest priority — it's confirmed tractable, unlike QG-Leith.
Convert/bridge it as its own named subroutine (`hor_visc_ZB2020`, per the monolith split) with
its full descendant tree following the normal Phase 2/3 machinery. Full traced tree (all nodes
confirmed leaf-or-not by reading their bodies):

```
ZB2020_lateral_stress (424-485, MOM_Zanna_Bolton.F90)
  -> compute_c_diss (492-539)                        leaf
  -> filter_velocity_gradients (924-1017)
       -> filter_hq (1072-1106) [x3 call sites]
            -> filter_3D (1121-1182)                  leaf
  -> compute_stress_ANN_collocated (658-781) [if CS%use_ann]
       -> ANN_apply_array_sio (MOM_ANN.F90:383-445)
            -> layer_apply_sio (internal, 425-444)
                 -> activation_fn (MOM_ANN.F90:241-247, pure elemental)   leaf
     / compute_stress (556-643) [else]                leaf
  -> filter_stress (1023-1068)
       -> filter_hq (as above)
  -> compute_stress_divergence (792-915)
       -> compute_energy_source (1186-1258)            leaf (infra only)
ZB2020_copy_gradient_and_thickness (361-415)            leaf
```

## `hor_visc_CS` (user decision: bundle by scheme)

Private (`type, public :: hor_visc_CS ; private`, fields genuinely private to
`MOM_hor_visc.F90`), 132 fields, confirmed opaque outside this module (5 files hold/pass it, all
just `MOM_dynamics_*` drivers forwarding it whole). **130 of 132 fields are genuinely
dereferenced inside `horizontal_viscosity`** — unlike `barotropic_CS`, there's no large
diagnostic-ID block to carve out (39 `id_*` fields exist and should still be excluded from
bundling, same reasoning as `barotropic_CS`, but that only brings it down to ~91 fields, not a
small remainder).

**Decision (user, this session): bundle by scheme, deferring to the monolith split.** Once
Stage 1 splits the body into `hor_visc_core`/`hor_visc_GME`/`hor_visc_QG_Leith`/
`hor_visc_ZB2020`/`hor_visc_Leithy`, run `create_config_bundle_type` once per scheme, each
bundle covering just the `CS` fields that scheme's new subroutine touches, nested back into
`hor_visc_CS`. Exclude the 39 `id_*` diagnostic handles from every bundle. Fields genuinely used
by more than one scheme (e.g. shared grid-metric arrays like `dx2h`/`dy2h`/`dx2q`/`dy2q` — used
17x each per the survey, likely across several branches) may need to stay as direct
`hor_visc_CS` fields rather than being claimed by one scheme's bundle — `create_config_bundle_type`'s
own execution should decide this once the split's exact field-usage-per-subroutine is visible;
Phase 1 could not fully resolve which fields are single-scheme vs. cross-scheme without the split
already having happened.

## `ADp`, `OBC`, `VarMix` shadows — see `shared_type_unions.md`

`ADp` and `OBC` are needed, container-based, by `continuity()` and `btstep` too — see
`btstep.md`'s "BLOCKING PREREQUISITE" section for why `OBC` gets a union shadow rather than a
`BT_cont_type`-style wholesale conversion. `VarMix` was tree-scoped to just this tree until
`vertvisc_coef` also needed it (see the `vertvisc` plan). All three types' authoritative union
field lists now live in `.claude/calltree-plans/shared_type_unions.md` — this file's own
contribution was `ADp`'s subset-of-`btstep`'s-fields, `OBC`'s additions (`OBC_pe`,
`strain_config`, `zero_biharmonic`, `segment(:)%direction/is_N_or_S/is_E_or_W/tangential_vel/
tangential_grad`, more `HI` bounds fields), and `VarMix`'s original 5-field tree-scoped list.

## Open item — optional struct dummies (not resolved, flagging rather than guessing)

`horizontal_viscosity` has **4 dummies that are entire optional derived-type structs** — `BT`
(`barotropic_CS`), `TD` (`thickness_diffuse_CS`), `ADp` (`accel_diag_ptrs`), `STOCH`
(`stochastic_CS`) — plus `OBC` which is `optional, pointer` together (a combination not seen in
`btstep`'s signature, where every struct dummy was either plain `pointer` or plain mandatory).
`convert_present_to_associated`'s own scope is explicitly array/scalar dummies that are "already
a container" — it has no stated mechanism for an *entire optional struct* becoming
bind(C)-ready. Since `BT`/`TD` are used only as opaque whole-struct forwards (into
`barotropic_get_tav`/`thickness_diffuse_get_KH`) and are already excluded from the `ADp`/`OBC`
shadow-building concern, the likely resolution is: the GME per-scheme subroutine
(`hor_visc_GME`) simply keeps `BT`/`TD` as optional Fortran dummies, checked via `present()`,
and doesn't bridge past them the same way `calc_isoneutral_slopes` isn't bridged past — but this
hasn't been decided, only noticed. `ADp`'s optionality interacts with its shadow (does the
shadow itself need a "not built" state when `ADp` isn't present?) and `STOCH`'s optionality is
similarly unresolved. **Return to Phase 1 for this rather than letting Phase 2 guess**, once
Stage 1's split clarifies which new subroutines actually receive which of these four dummies.

## Step 2 — target classification (fixed-rule items)

| Target | Classification | Skill | Notes |
|---|---|---|---|
| `u`, `v`, `h`, `uh`, `vh`, `diffu`, `diffv`, `hu_cont`, `hv_cont` | raw/optional array dummies | `convert_array_containers` (`hu_cont`/`hv_cont` also need `convert_present_to_associated` after) | Standard treatment once the split settles which new subroutine owns each. |
| `G`, `GV`, `US` | shared grid/scaling types | `convert_array_containers`'s own drop mechanism | Not a separate decision. |
| `tv` (`thermo_var_ptrs`, 101 files) | confirmed 0 dereferences in `horizontal_viscosity` — purely opaque (forwarded whole into `thickness_to_dz`/`calc_QG_slopes`) | leave alone | Grep-confirmed, matches Step 2's opaque rule directly. |
| `BT` (`barotropic_CS`) | confirmed 0 dereferences — opaque (forwarded whole into `barotropic_get_tav`) | leave alone | Also the type `btstep`'s campaign bundles internally — irrelevant here since `horizontal_viscosity` never looks at its fields, only calls the accessor. |
| `TD` (`thickness_diffuse_CS`) | confirmed 0 dereferences — opaque (forwarded whole into `thickness_diffuse_get_KH`) | leave alone | — |
| `VarMix` (`VarMix_CS`, ~89 fields) | only 5 fields touched (`use_variable_mixing`, `Resoln_scaled_Kh`, `Res_fn_h`, `Res_fn_q`, `BS_struct`) | `create_shadow_container_type` — **union shadow**, see `shared_type_unions.md` | Disproportion (5/89) resolves this without a Step 3 measure-and-decide even as a union. |
| `MEKE` (`MEKE_type`, 15 fields, shared 11 files) | heavily dereferenced, both scalar and array (`MEKE%Ku`/`MEKE%Au` feed `Kh`/`Ah` directly; `MEKE%mom_src` written) | `create_shadow_container_type`, most/all fields | Small type, high touch fraction — straightforward. |
| `ADp`, `OBC` | shared | `create_shadow_container_type` — **union shadow** | See `shared_type_unions.md`. |
| `CS` (`hor_visc_CS`, 132 fields, private) | private, fields recur together, 130/132 touched | `create_config_bundle_type`, bundle-by-scheme | See dedicated section above. |
| `STOCH` (`stochastic_CS`, shared 9 files) | small, dereferenced (`skeb_use_frict`, `skeb_diss`, `skeb_frict_coef` — 1 scalar flag, 1 array, 1 scalar coefficient) | `create_shadow_container_type`, narrow scope | Clean fixed-rule resolution, no Step 3 needed. Optionality itself is the open item above, not the shadow scope. |
| `smooth_x9_h`/`smooth_x9_uv`/`smooth_GME`'s own dummies (`field_h`, `field_u`/`field_v`, `GME_flux_h`/`GME_flux_q`, `zero_land`) | raw/optional array and scalar dummies | `convert_array_containers` then `convert_present_to_associated` for the optionals | Standard, all three already confirmed leaves. |
| `calc_QG_slopes`'s own dummies (`h`, `tv`, `dt`, `G`, `GV`, `US`, `slope_x`, `slope_y`, `CS`, `OBC`) | mixed raw arrays + shared structs | `convert_array_containers` for `slope_x`/`slope_y`; `tv`/`OBC` follow the same classification as elsewhere in this plan | Boundary node — see QG-Leith section; everything it calls stays untouched. |

## Phase 2 execution order (for this tree)

1. **TreeRoot split** — rename `horizontal_viscosity`→`horizontal_viscosity_TR`, author
   `horizontal_viscosity` wrapper, **and** split the body into per-scheme subroutines (Stage 1
   does more work here than in `continuity()`/`btstep` — see "Monolith split" above).
2. **`create_shadow_container_type`** — the type definitions themselves for `VarMix`, `MEKE`
   (now a union, see `shared_type_unions.md`), `ADp`/`OBC` are built once by the combined
   shared-infrastructure PR (`shared_type_unions.md`), not here. This stage's own work for this
   tree is just the wrapper-side glue: instantiate each shadow from `horizontal_viscosity_TR`'s
   own dummies, use it, copy back. `STOCH` remains genuinely tree-scoped (not yet a union) — its
   type still gets authored here, not in the shared PR.
3. **`create_config_bundle_type`** — `hor_visc_CS`, once per new per-scheme subroutine from
   Stage 1's split.
4. **Optional-array containerization** — `hu_cont`, `hv_cont`, plus the three helpers' own
   optional scalars (`zero_land` x2, and `smooth_GME`'s two optional arrays); default direction
   throughout, none confirmed to cascade.
5. **`convert_array_containers` — downward pass**, root (`horizontal_viscosity_TR`) to leaves.
6. **`convert_array_containers` — upward pass**, leaves to root, G/GV/US-drop decisions.
7. **`convert_locals_to_containers`**, per subroutine once dummies are stable.
8. **`convert_present_to_associated`** — every confirmed optional array/scalar dummy. **Blocked
   on the "Open item — optional struct dummies" above for `BT`/`TD`/`ADp`/`STOCH`/`OBC`'s
   optional-struct status** — resolve that before this stage runs on those four/five dummies.
9. **`hoist_container_marshalling`**, once, at `horizontal_viscosity_TR`.

## Phase 3 wave order (provisional — depends on Stage 1's split; the ZB2020 and existing-leaf
portions are final now, the per-scheme subroutines' waves are not)

**Final (subroutines that already exist, unaffected by the split):**
- **Wave 1** (leaves): `smooth_x9_h`, `smooth_x9_uv`, `smooth_GME`, `barotropic_get_tav`,
  `thickness_diffuse_get_KH`, `thickness_to_dz`, `calc_QG_Leith_viscosity`, `calc_QG_slopes`
  (boundary node — no in-tree callees per the QG-Leith decision), `compute_c_diss`, `filter_3D`,
  `compute_stress`, `compute_energy_source`, `ZB2020_copy_gradient_and_thickness`,
  `activation_fn`.
- **Wave 2:** `filter_hq` (calls `filter_3D`), `layer_apply_sio`/`ANN_apply_array_sio` (calls
  `layer_apply_sio`→`activation_fn`).
- **Wave 3:** `filter_velocity_gradients`, `filter_stress` (both call `filter_hq`),
  `compute_stress_ANN_collocated` (calls `ANN_apply_array_sio`/`compute_stress`),
  `compute_stress_divergence` (calls `compute_energy_source`).
- **Wave 4:** `ZB2020_lateral_stress` (calls `compute_c_diss`, `filter_velocity_gradients`,
  `compute_stress_ANN_collocated`, `filter_stress`, `compute_stress_divergence` — all resolved by
  wave 3).

**Provisional (depends on Stage 1's actual split — recompute once it's done):**
- **Wave 5 (est.):** `hor_visc_GME` (needs `smooth_GME`/`barotropic_get_tav`/
  `thickness_diffuse_get_KH`, wave 1), `hor_visc_QG_Leith` (needs `thickness_to_dz`/
  `calc_QG_slopes`/`calc_QG_Leith_viscosity`, wave 1), `hor_visc_Leithy` (needs `smooth_x9_h`/
  `smooth_x9_uv`, wave 1), `hor_visc_core` (likely no in-tree dependencies).
- **Wave 6 (est.):** `hor_visc_ZB2020` (needs `ZB2020_lateral_stress`, wave 4).
- **Wave 7 (est., root, last):** `horizontal_viscosity_TR` (calls all per-scheme subroutines).
  The wrapper is never bridged.

## Branch

`claude_horizontal_viscosity_calltree`, created once before Phase 2 Stage 1.
