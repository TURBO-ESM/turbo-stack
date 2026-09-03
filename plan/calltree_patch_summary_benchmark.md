# Calltree conversion plans — benchmark patch summary

**Read [`calltree_blocker_summary_double_gyre_unsplit.md`](calltree_blocker_summary_double_gyre_unsplit.md)
(base) and [`calltree_patch_summary_double_gyre.md`](calltree_patch_summary_double_gyre.md) (patch)
first.** This file covers only what's *additional* to reach `benchmark`, on top of the
`double_gyre` patch — not a restatement of either.

**Legend:** ✅ resolved/confirmed clean · 🔴 blocking (external dependency) · 🟡 not blocking, but
real unfinished work

---

## Why this is a physics patch on `double_gyre`, not a new dynamics patch

`benchmark` (`examples/benchmark/`, exists locally — unlike `double_gyre_unsplit`, no config-
sourcing gap here) sets `SPLIT = True` — the same as `double_gyre`, not `double_gyre_unsplit`.
Confirmed directly: `MOM_barotropic.F90` (`btstep`'s file) shows real, comparable coverage under
both (44.6% `double_gyre` vs. 46.2% `benchmark`). So `benchmark` builds on the **`double_gyre`**
patch, reusing `btstep` unchanged — it does not add a new dynamics-core axis, only new physics
packages on top of the same split dynamics.

Config diff (`examples/benchmark/MOM_parameter_doc.all` vs. `examples/double_gyre/MOM_parameter_doc.all`):

| Flag | `double_gyre` | `benchmark` | Effect |
|---|---|---|---|
| `SPLIT` | `True` | `True` | unchanged — confirms this builds on `double_gyre` |
| `ENABLE_THERMODYNAMICS` | `False` | **`True`** | `tv` goes live |
| `USE_VARIABLE_MIXING` | `False` (default) | **`True`** | `VarMix` goes live |
| `BULKMIXEDLAYER` | `False` | **`True`** | some `vertvisc_type` fields go live (see below) |
| `USE_MEKE` | `False` | `False` | `MEKE` stays inert |
| `USE_WAVES` | `False` | `False` | `Waves` stays inert |
| `USE_POROUS_BARRIER` | `False` | `False` | `pbv` stays inert |
| `OBC_NUMBER_OF_SEGMENTS` | `0` | `0` | `OBC` stays inert |
| `EQN_OF_STATE` | `"WRIGHT"` | `"WRIGHT"` | unchanged |

`ADp` checked separately: `benchmark`'s `diag_table` requests none of the diagnostics gating
`ADp`'s fields (`diffu`/`diffv`/etc. — same grep as the base-file audit, zero hits) — stays
inert, same as under both double_gyre configs.

## Two types un-defer: `tv` and `VarMix`

Coverage evidence (`double_gyre` vs. `benchmark`, from the existing
`coverage_diff_double_gyre_V_benchmark_files` report):

| File | `double_gyre` | `benchmark` | Verdict |
|---|---|---|---|
| `MOM_EOS.F90` | 0.3% (3/930) | **13.5%** (121/896) | `tv%eqn_of_state` dispatch now genuinely reached |
| `MOM_EOS_Wright_full.F90` (the actual resolved form) | 0.0% (0/322) | **31.3%** (100/319) | the EOS kernel itself now runs — first real validation of `EOS_bridge_design.md`'s tier-1 `buggy_Wright_EOS`/`Wright_full_EOS` claim, previously configured-but-unverified (see that file's corrected caveat) |
| `MOM_lateral_mixing_coeffs.F90` (`VarMix_CS`'s file) | 13.5% (117/866) | **34.9%** (289/829) | `VarMix`'s real fields (`Res_fn_*`, `SN_*`, etc.) now computed, not just guard-checked |
| `MOM_set_viscosity.F90` | 21.6% (291/1346) | **39.1%** (524/1341) | `tv`-dependent EOS calls in `set_viscous_BBL`/`_ML`, plus `BULKMIXEDLAYER`-gated fields (below) |
| `MOM_hor_visc.F90` | 33.3% (462/1386) | 36.7% (502/1369) | modest increase, consistent with `VarMix`'s real resolution-scaling now active |
| `MOM_tracer_hor_diff.F90` | 7.0% (59/847) | **71.1%** (575/809) | this tree's own three dispatch branches (`Diffuse_ML_interior`/`use_hor_bnd_diffusion`/`use_neutral_diffusion`) become genuinely exercised — resolves the pre-existing gap flagged in `tracer_hordiff.md` ("neither double_gyre config can validate this tree; `benchmark` is the config that would") |
| `MOM_PressureForce_FV.F90` | 21.2% (203/958) | 21.3% (203/955) | flat — most of this file's lines are pressure-gradient math independent of thermodynamics; the `if (use_EOS)` guard flipping true doesn't move the file-level line count much even though real EOS calls now execute inside it |
| `MOM_variables.F90` | 27.5% (28/102) | 28.6% (28/98) | barely moves — confirms the earlier base-file finding that this file's reachability difference is driven by `SPLIT`, not by the thermodynamics/mixing axis |

**Decision, following the same reasoning applied throughout this campaign:** `tv` and `VarMix`
move from "deferred" back to **real `create_shadow_container_type` work**, each as its own
single-type shared shadow (not bundled into an artificial multi-type "combined PR" — there's no
coordination problem between `tv` and `VarMix` themselves, only the ordinary "build once per type,
shared by every tree that needs it" principle already used for `OBC` before its own deferral, and
for `forces%taux`/`tauy`).

- **`tv` — shared shadow, needed by `PressureForce` (all six subroutines), `tracer_hordiff` (own
  body + `tracer_epipycnal_ML_diff`), `set_viscosity_family` (both entry points), and the
  vertvisc-family cluster (`SpV_avg`, via `vertvisc_coef`/`vertvisc_remnant`).** Field list already
  fully itemized in `shared_type_unions.md`'s `tv` section from before the deferral — `SpV_avg`,
  `T`, `S`, `P_Ref`, `eqn_of_state` (opaque handle, forwarded into EOS calls only), `varT`,
  `p_surf` — no re-survey needed, just re-activation.
- **`VarMix` — shared shadow, needed by `horizontal_viscosity`, `vertvisc_coef` (via
  `find_coupling_coef_gl90`), and `tracer_hordiff`.** Field list also already itemized (~10 of the
  type's ~89 fields) — same re-activation, no re-survey.

## `vertvisc_type` — no new blocker, but two fields move Tier 2 → Tier 1

`BULKMIXEDLAYER=True` under `benchmark` (vs. `False` under both double_gyre configs) means
`nkml_visc_u`/`nkml_visc_v` — previously Tier 2/inert in the vertvisc-family cluster's *already-
active* local shadow (see `shared_type_unions.md`'s `vertvisc_type` section) — become genuinely
live. This isn't a mechanism change: `vertvisc_type` was never deferred, its cluster-local shadow
already exists as a target regardless of config. It just means two more of that shadow's fields
are now capture-fixture-validatable, worth noting in `shared_type_unions.md`'s Tier table whenever
that's revisited, but not a scheduling blocker for any tree.

## What stays deferred, unchanged from the `double_gyre` patch

`OBC`, `ADp`, `Waves`, `pbv`, `MEKE` — none of their gating flags change under `benchmark` (see
the config-diff table above). Same treatment, same reasoning, no new work.

## Net effect on tree-level blockers

| Tree | Change under this patch |
|---|---|
| `PressureForce` | Was fully clear (base file). Now needs `tv`'s shared shadow — real Phase 2 Stage 2 work, not just "nothing to wait on." |
| `set_viscosity_family` | Was fully clear (base file). Now needs `tv`'s shared shadow (both entry points). |
| `tracer_hordiff` | Base file: only `Reg`/`Tr` blocker. Now also needs `tv` and `VarMix`'s shared shadows — and, unlike under either double_gyre config, its own three dispatch branches finally have real coverage to validate against. |
| `horizontal_viscosity` | Was fully clear (base file). Now needs `VarMix`'s shared shadow. |
| `vertvisc_family` | Base file: only its own local cluster shadow (never blocked). Now that cluster shadow gains real Tier-1 status for `nkml_visc_u/v`, and separately needs `tv`'s shared shadow for `SpV_avg` (`vertvisc_coef`/`vertvisc_remnant`) and `VarMix`'s for `find_coupling_coef_gl90`. |
| `btstep`, `CorAdCalc`, `advect_tracer`, `set_viscosity_family`'s `OBC`/`pbv` needs | Unchanged — nothing in this patch touches them. |

`EOS_bridge_design.md` is worth revisiting once this patch's capture fixtures exist: it's the
first config in this campaign that actually exercises the Wright EOS kernel, so its tier-1
"trusted" classification for `buggy_Wright_EOS` finally gets real runtime backing instead of
resting only on "double_gyre happens to configure this form."
