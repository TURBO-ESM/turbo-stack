# convert_calltree plan — `horizontal_viscosity`

Skill: `convert_calltree`. Phase 1 output only — no code changed yet.
Repo: `submodules/MOM6` checkout at
`/Users/dennis/Desktop/Work/Claude_auto_convert/turbo-stack/submodules/MOM6`.
Unrelated to the `continuity()` campaign (separate plan file, separate tree,
separate branch when Phase 2 starts) — do not conflate the two.

**Base plan — double_gyre_unsplit.** `horizontal_viscosity` is called once per step from both
split and unsplit dynamics cores (split passes barotropically-corrected `u_av`/`v_av`, unsplit
passes raw `u_in`/`v_in` — same subroutine, same code path either way) — confirmed nearly
identical file coverage under `double_gyre` (33.3%) and `double_gyre_unsplit` (31.9%). No patch
needed.

**Shared-infrastructure status, updated this session: fully clear.** `MEKE_type`/`VarMix_CS`/
`accel_diag_ptrs` — this tree's only three ties to `shared_type_unions.md`'s combined PR — were
all deferred (confirmed PASSED-BUT-INERT under both double_gyre configs; see that file's
"Mechanism decision 2"). `OBC` was already dropped from this tree's needs in an earlier redo
(QG-Leith/ZB2020 scoped out). This tree now has **zero remaining `create_shadow_container_type`
dependencies on anything outside itself** — only `stochastic_CS` (tree-scoped, never externally
blocked) and `hor_visc_CS` (its own private config bundle) remain, both fully within this plan's
own control. Nothing left to wait on. **This holds for double_gyre_unsplit and double_gyre only**
— `VarMix` re-activates under the `benchmark` patch (`USE_VARIABLE_MIXING=True` there), and this
tree genuinely dereferences its real fields, so `benchmark` reintroduces a real `VarMix` shadow
dependency. See `plan/calltree_patch_summary_benchmark.md`.

## Step 1a — external signature (frozen)

```fortran
subroutine horizontal_viscosity(u, v, h, uh, vh, diffu, diffv, MEKE, VarMix, G, GV, US, &
                                CS, nkblock, tv, dt, OBC, BT, TD, ADp, hu_cont, hv_cont, STOCH)
```

Declared `src/parameterizations/lateral/MOM_hor_visc.F90:273`, 1,913 lines
(the whole file is 4,416 lines). Mandatory: `u,v,h,uh,vh,diffu,diffv`
(raw arrays), `MEKE` (`type(MEKE_type), intent(inout)`), `VarMix`
(`type(VarMix_CS), intent(inout)`), `G`/`GV`/`US`, `CS`
(`type(hor_visc_CS), intent(inout)`), `nkblock` (integer), `tv`
(`type(thermo_var_ptrs), intent(in)`), `dt`. Optional: `OBC`
(`type(ocean_OBC_type), pointer`, bare — not a Fortran `optional`
attribute but tested via `present()`/`associated()` both), `BT`
(`type(barotropic_CS), optional, intent(in)`), `TD`
(`type(thickness_diffuse_CS), optional, intent(in)`), `ADp`
(`type(accel_diag_ptrs), optional, intent(in)`), `hu_cont`/`hv_cont`
(raw arrays, `optional, intent(inout)`), `STOCH`
(`type(stochastic_CS), intent(inout), optional`).

## Step 1d — Scope case

**Case 3** — no separate name exists; `horizontal_viscosity` is called
directly, everywhere. No `_TR` split exists yet. Phase 2 Stage 1 must
rename the implementation to `horizontal_viscosity_TR` and author a
pass-through wrapper under `horizontal_viscosity`'s own name.

External callers (repo-wide grep, all in `src/core/`) — 6 call sites,
all of which must keep compiling unchanged once the wrapper exists:
- `MOM_dynamics_unsplit_RK2.F90:284`
- `MOM_dynamics_split_RK2b.F90:584`, `:895`
- `MOM_dynamics_split_RK2.F90:969`, `:1765`
- `MOM_dynamics_unsplit.F90:272`

## Step 1b/1c — Call graph and target inventory

```
horizontal_viscosity (no wrapper yet, Case 3)         — MOM_hor_visc.F90:273
├─ hor_visc_Leith_grad          [Wave 1 — leaf]
├─ hor_visc_backscatter_h       [Wave 1 — leaf]
├─ hor_visc_backscatter_q       [Wave 1 — leaf]
├─ hor_visc_GME_setup           [Wave 1 — leaf, guarded by CS%use_GME]
├─ smooth_GME                   [Wave 1 — leaf]
├─ smooth_x9_uv                 [Wave 1 — leaf]
└─ hor_visc_Leithy_Ah           [Wave 2]
    └─ smooth_x9_h              [Wave 1 — leaf]
```

`hor_visc_init`/`hor_visc_end`/`hor_visc_vel_stencil`/`hor_visc_nkblock`/
`align_aniso_tensor_to_grid` live in the same file but are **not**
descendants (never called from inside this tree) — same non-descendant
status `continuity_init`/`continuity_stencil` had in the `continuity()`
campaign. Out of scope.

Out-of-tree calls (not part of this campaign, all into other established
modules): `hchksum`/`Bchksum`/`uvchksum` (MOM_checksums), `post_data`/
`post_product_*` (MOM_diag_mediator), `pass_var`/`pass_vector`
(MOM_domains), `MOM_error`, `thickness_to_dz` (MOM_interface_heights),
`calc_QG_slopes`/`calc_QG_Leith_viscosity` (MOM_lateral_mixing_coeffs —
`VarMix`'s own defining module), `barotropic_get_tav` (MOM_barotropic),
`thickness_diffuse_get_KH` (MOM_thickness_diffuse),
`ZB2020_lateral_stress`/`ZB2020_copy_gradient_and_thickness`
(MOM_Zanna_Bolton).

No `elemental`/`pure` scalar-only leaf exists in this tree (unlike
`continuity()`'s `flux_elem`) — every descendant is a real candidate for
bridging, none exempt on those grounds.

**Zero pre-existing containers anywhere in this tree** — 100% raw, unlike
`continuity()` where 6 leaves were already bridged before this campaign
started. Every one of the 8 subroutines above needs `convert_array_containers`.

## Derived types referenced in the tree

| Type | Dummy | Fields touched / total | Shared outside tree? | Classification |
|---|---|---|---|---|
| `hor_visc_CS` | `CS` | 131 / 131 | No — only the 4 dynamics files hold it, always opaquely as `CS%hor_visc` | `create_config_bundle_type` — see clustering below |
| `MEKE_type` | `MEKE`, mandatory `intent(inout)` | 8 / — (`Au`,`Ku`,`GME_snk`,`mom_src`,`mom_src_bh` arrays; `backscatter_Ro_pow`,`backscatter_Ro_c` scalars) | **Yes** — 9 other files | **DEFERRED this session** — confirmed PASSED-BUT-INERT under both double_gyre configs (`USE_MEKE=False`); leave alone, view-marshal at call site, no shadow built now. See `shared_type_unions.md`'s "Mechanism decision 2." |
| `VarMix_CS` | `VarMix`, mandatory `intent(inout)` | 5 / — (`Res_fn_h`,`Res_fn_q`,`BS_struct` arrays; `Resoln_scaled_Kh`,`use_variable_mixing` scalars) | **Yes** — 9 other files | **DEFERRED this session** — confirmed PASSED-BUT-INERT (guard true, real fields never computed); leave alone, view-marshal at call site. See `shared_type_unions.md`'s "Mechanism decision 2." |
| `accel_diag_ptrs` | `ADp`, **optional**, `intent(in)` | 6 / — (`diag_hfrac_u`,`diag_hfrac_v`,`diag_hu`,`diag_hv`,`visc_rem_u`,`visc_rem_v`, all raw arrays) | **Yes** — 13 other files | **DEFERRED this session** — confirmed PASSED-BUT-INERT (diagnostics not requested in `double_gyre`'s `diag_table`); leave alone via plain `present()`/`associated()`, no shadow, no grouped-optional work needed now. See `shared_type_unions.md`'s "Mechanism decision 2." |
| `stochastic_CS` | `STOCH`, **optional**, `intent(inout)` | 3 / — (`skeb_diss` array; `skeb_frict_coef`,`skeb_use_frict` scalars) | **Yes** — 7 other files | same combination as `ADp` (Decision Q1) |
| `ocean_OBC_type` | `OBC`, bare **optional `pointer`** | not fully enumerated (nested `%segment` etc. not expanded) | Yes — 45 other files | `convert_present_to_associated`, bare-pointer form — `present()`/`associated()` both tested at the entry point (line 233/239), never forwarded to a descendant. Exactly the `BT_cont` class of target this skill family was corrected to catch. |
| `barotropic_CS` | `BT`, optional, `intent(in)` | 0 direct — forwarded to `hor_visc_GME_setup`, itself only used via the external accessor `barotropic_get_tav(BT,...)` | Yes — 4 other files | **Leave alone, confirmed** — zero `present(BT)` anywhere; forwarding is guarded by `CS%use_GME`, a config flag, not `present()` |
| `thickness_diffuse_CS` | `TD`, optional, `intent(in)` | 0 direct — same pattern, forwarded to `thickness_diffuse_get_KH(TD,...)` | Yes — 3 other files | **Leave alone, confirmed** — zero `present(TD)` anywhere |
| `thermo_var_ptrs` | `tv`, mandatory `intent(in)` | 0 direct — forwarded opaquely to `thickness_to_dz`/`calc_QG_slopes` (both external) | Yes — 101 other files | **Leave alone, confirmed** — mandatory, never `%field`-accessed, same treatment as `G`/`GV`/`US` |
| `ocean_grid_type`/`verticalGrid_type`/`unit_scale_type` | `G`/`GV`/`US` | opaque field access only | Yes, universally | Leave alone, same as `continuity()` |
| `ZB2020_CS` (nested in `hor_visc_CS`) | `CS%ZB2020` | 0 direct — forwarded opaquely to `ZB2020_lateral_stress`/`ZB2020_copy_gradient_and_thickness` (external, MOM_Zanna_Bolton) | N/A (nested, not a top-level dummy) | **Leave alone** |
| `diag_ctrl` (nested in `hor_visc_CS`) | `CS%diag`, `pointer` | never-bindable | N/A | **Leave alone**, same as `continuity_PPM_CS`'s own `diag` precedent |

## `hor_visc_CS` bundling (Decision Q2 — field-trace confirmed)

131 fields: 1 init guard (`initialized`), ~46 scalar config fields, ~34
`id_*` diagnostic-handle integers, 42 array fields (all `real,
allocatable`, rank-2), plus the 2 never-bundled entries above
(`ZB2020`, `diag`).

**Co-occurrence matrix** (fundamentally different shape than
`continuity_PPM_CS`'s: there, fields recurred across *many*
subroutines; here `horizontal_viscosity` itself touches essentially all
131, while each descendant touches only a small, disjoint subset):

| Subroutine | CS fields touched |
|---|---|
| `horizontal_viscosity` | ~all 131 |
| `hor_visc_Leith_grad` | `Leith_Ah`, `Modified_Leith`, `use_beta_in_Leith`, `use_Leithy`, `use_QG_Leith_visc` (5, scalar) |
| `hor_visc_backscatter_h` | `id_BS_coeff_h` (1) |
| `hor_visc_backscatter_q` | `id_BS_coeff_q` (1) |
| `hor_visc_Leithy_Ah` | `Ah_bg_xx`, `Biharm6_const_xx`, `c_K`, `m_const_leithy`, `m_leithy_max`, `smooth_Ah` (6; 4 arrays + 2 scalars) |
| `hor_visc_GME_setup` | `debug`, `DX_dyBu`, `DX_dyT`, `DY_dxBu`, `DY_dxT`, `GME_efficiency`, `GME_h0`, `no_slip` (8; 4 arrays + 4 scalars) |
| `smooth_GME` | `num_smooth_gme` (1) |
| `smooth_x9_h`, `smooth_x9_uv` | 0 — don't take `CS` at all |

**Clusters** (fields recurring with the same descendant — the skill's
actual bundling criterion):
- **`leith_CS`** — `Leith_Ah`, `Modified_Leith`, `use_beta_in_Leith`,
  `use_Leithy`, `use_QG_Leith_visc` (shared with `hor_visc_Leith_grad`).
- **`leithy_CS`** — `Ah_bg_xx`, `Biharm6_const_xx`, `c_K`,
  `m_const_leithy`, `m_leithy_max`, `smooth_Ah` (shared with
  `hor_visc_Leithy_Ah`).
- **`gme_setup_CS`** — `debug`, `DX_dyBu`, `DX_dyT`, `DY_dxBu`, `DY_dxT`,
  `GME_efficiency`, `GME_h0`, `no_slip` (shared with `hor_visc_GME_setup`).
- **Standalone, no companion, not bundled** (per the skill's own rule):
  `id_BS_coeff_h`, `id_BS_coeff_q`, `num_smooth_gme` — each shared with
  exactly one descendant, alone.

**The remaining ~109 fields** (83% of the struct, including 32 of the 34
`id_*` diagnostic handles) are touched only by `horizontal_viscosity`
itself — no descendant co-occurrence exists to cluster them by evidence.
**User decision (Q2): one catch-all bundle** —
`hor_visc_general_CS` — covering all ~109, accepting a large,
semantically-mixed bundle in exchange for not exploding
`horizontal_viscosity`'s eventual bridge interface into 100+ individual
parameters. (Two exceptions already noted above: `id_BS_coeff_h`/
`id_BS_coeff_q` are NOT part of this catch-all — they're standalone,
2-subroutine fields, listed above.)

`create_config_bundle_type`'s own Step 6 (per-leaf "keeps whole struct"
vs. "stops taking it") still needs to run when that skill is actually
invoked in Phase 2 — every one of the 8 subroutines in this tree will
eventually be bridged (this campaign's whole point), so none of them
gets to "keep the whole struct" indefinitely; this plan records the
cluster membership, not the per-leaf narrowing (that's Stage work, not
a Phase 1 decision, per `continuity_PPM_CS`'s own precedent).

## Step 2/3 — Target classification and recorded decisions

| Target | Skill | Setting |
|---|---|---|
| `hor_visc_CS` | `create_config_bundle_type` | 3 clusters (`leith_CS`, `leithy_CS`, `gme_setup_CS`) + 1 catch-all (`hor_visc_general_CS`, ~109 fields) + 3 standalone (`id_BS_coeff_h`, `id_BS_coeff_q`, `num_smooth_gme`) + 2 leave-alone (`ZB2020`, `diag`) — Q2 |
| `MEKE_type` | **DEFERRED** — leave alone, view-marshal at call site | Shared, 9 files, 5 array + 2 scalar fields touched; PASSED-BUT-INERT, not built now |
| `VarMix_CS` | **DEFERRED** — leave alone, view-marshal at call site | Shared, 9 files, 3 array + 2 scalar fields touched; PASSED-BUT-INERT, not built now |
| `accel_diag_ptrs` (`ADp`) | **DEFERRED** — leave alone via plain `present()`/`associated()`, no shadow | Shared, 13 files, all 6 touched fields raw arrays; PASSED-BUT-INERT, not built now — grouped-optional (Q1) work no longer applies here |
| `stochastic_CS` (`STOCH`) | `create_shadow_container_type` + `convert_present_to_associated` (grouped-optional) | Shared, 7 files, 1 array + 2 scalar fields, optional-as-whole-struct — Q1 |
| `ocean_OBC_type` (`OBC`) | `convert_present_to_associated`, bare-pointer form | `present()`/`associated()` both tested at the entry point only |
| `barotropic_CS` (`BT`), `thickness_diffuse_CS` (`TD`) | leave alone | Confirmed by grep — never `present()`-tested, only config-flag-guarded |
| `thermo_var_ptrs` (`tv`), `G`/`GV`/`US` | leave alone | Mandatory, opaque field access only |
| `ZB2020` (nested), `diag` (nested) | leave alone | Never-bindable / forwarded opaquely to an external module |
| `u,v,h,uh,vh,diffu,diffv` + every local in all 8 subroutines | `convert_array_containers` | Top-down, root to leaves |
| `hu_cont`/`hv_cont` (optional raw arrays) | `convert_array_containers` (plain, not the optional-args variant) | `present()`-tested jointly but never forwarded past `horizontal_viscosity` itself — no combinatorial branching risk |
| `zero_land` (plain `logical` optional scalar, in `smooth_x9_h`/`smooth_x9_uv`) | leave alone | Scalar optionals are never containerized |

## Phase 2 execution order (Step 4's fixed 9 stages)

1. **TreeRoot split** — rename `horizontal_viscosity` → `horizontal_viscosity_TR`
   in `MOM_hor_visc.F90`, author a pass-through wrapper under
   `horizontal_viscosity`'s own name with the frozen signature (Step 1a),
   calling `_TR`. Fix up the 6 external call sites' expectations (they
   don't change — same name, same signature — but confirm via grep after).
2. **`create_shadow_container_type`**, per `stochastic_CS` (`STOCH`) only — 1 shadow, built
   tree-locally (never blocked on the combined PR). `MEKE_type`/`VarMix_CS`/`accel_diag_ptrs`
   are **deferred this session** (see "Mechanism decision 2" in `shared_type_unions.md`) — no
   shadow for them now; the wrapper forwards them raw, exactly as the original code did.
3. **`create_config_bundle_type`** for `hor_visc_CS` — 3 clusters +
   1 catch-all, per the section above; update `hor_visc_init`'s body to
   populate the new bundle types instead of 131 flat fields.
4. **Optional-array containerization** — `hu_cont`/`hv_cont` via plain
   `convert_array_containers` (no combinatorial risk, per the
   classification table); `OBC`/`STOCH`'s own optionality is
   `convert_present_to_associated`'s job (item 8), not this item's. `ADp`'s optionality is now
   just plain `present()`/`associated()` on the raw (deferred) type, no grouped-optional work.
5. **`convert_array_containers` — downward pass**, root to leaves:
   `horizontal_viscosity` → `hor_visc_Leith_grad`/`hor_visc_backscatter_h`/
   `hor_visc_backscatter_q`/`hor_visc_GME_setup`/`smooth_GME`/
   `smooth_x9_uv` → `hor_visc_Leithy_Ah` → `smooth_x9_h`.
6. **`convert_array_containers` — upward pass**, leaves to root:
   `G`/`GV`/`US`-drop decisions and Step 2b promotions, per that skill's
   required bottom-up ordering for this question.
7. **`convert_locals_to_containers`**, once dummies are stable tree-wide.
8. **`convert_present_to_associated`**: `OBC` (bare-pointer form, entry
   point only); `ADp`/`STOCH` (grouped-optional form, on top of their
   Stage-2 shadows).
9. **`hoist_container_marshalling`**, once, at `horizontal_viscosity`, last.

One branch for the whole run:
`claude_horizontal_viscosity_calltree` (per the skill's own default
naming — no user override recorded for this campaign yet).

## Phase 3 wave order (computed from the call graph above)

- **Wave 1:** `hor_visc_Leith_grad`, `hor_visc_backscatter_h`,
  `hor_visc_backscatter_q`, `hor_visc_GME_setup`, `smooth_GME`,
  `smooth_x9_uv`, `smooth_x9_h`.
- **Wave 2:** `hor_visc_Leithy_Ah` (depends on `smooth_x9_h`).
- **Wave 3 (root, last):** `horizontal_viscosity`.

The wrapper (`horizontal_viscosity`'s Case-3 pass-through, once Stage 1
authors it) is never bridged, in any wave — same rule as every other
entry point in this campaign family.

## Decisions recorded (Step 3, `AskUserQuestion`, one topic per call)

- **Q1 — `accel_diag_ptrs`/`stochastic_CS`: shadow + optional
  combination.** Both are shared-outside-tree types with real array
  fields *and* optional-as-a-whole-struct at the entry point — a
  combination `continuity()`'s campaign never hit (its own shared
  optional, `BT_cont`, was a bare pointer, not a whole-struct
  `optional`). Proposed: shadow the type first
  (`create_shadow_container_type`), then apply
  `convert_present_to_associated`'s grouped-argument rule on top of the
  shadow, treating each type's touched fields as one grouped-optional
  set. **User confirmed: yes, shadow then grouped-optional.**
- **Q2 — `hor_visc_CS`'s ~109 fields with no descendant co-occurrence.**
  The trace found 3 real clusters + 3 standalone fields from actual
  cross-subroutine usage, but 83% of the struct is touched only by
  `horizontal_viscosity` itself, giving the trace no evidence to
  sub-cluster further. Presented three options: one catch-all bundle,
  several thematic sub-bundles (name/comment-based, not evidence-based),
  or individual field promotion (mechanically safest, ~109 new
  parameters). **User confirmed: one catch-all bundle**
  (`hor_visc_general_CS`).

## Summary table for review

| Target | Skill | Decision |
|---|---|---|
| `hor_visc_CS` | create_config_bundle_type | 3 clusters + 1 catch-all + 3 standalone + 2 leave-alone (Q2) |
| `MEKE_type`, `VarMix_CS`, `accel_diag_ptrs` | **DEFERRED** — leave alone, view-marshal | confirmed PASSED-BUT-INERT under both double_gyre configs; no shared-infra dependency left on this tree from `shared_type_unions.md`'s combined PR at all |
| `stochastic_CS` | create_shadow_container_type + convert_present_to_associated | shadow then grouped-optional (Q1) — tree-scoped, never blocked externally |
| `ocean_OBC_type` | convert_present_to_associated | bare-pointer form, entry point only |
| `barotropic_CS`, `thickness_diffuse_CS`, `thermo_var_ptrs`, `G`/`GV`/`US`, `ZB2020`, `diag` | leave alone | confirmed by grep |
| `u,v,h,uh,vh,diffu,diffv` + all locals, 8 subroutines | convert_array_containers | top-down then bottom-up (Stages 5–6) |
| `hu_cont`/`hv_cont` | convert_array_containers (plain) | no forwarding past entry point |
| `zero_land` | leave alone | scalar optional |

Not yet started: Phase 2 Stage 1 (TreeRoot split) — awaiting go-ahead.
