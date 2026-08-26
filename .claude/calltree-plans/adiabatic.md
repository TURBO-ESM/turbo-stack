# Call-tree conversion plan: `adiabatic`

The smallest entry point surveyed this campaign: `adiabatic` (`src/parameterizations/vertical/MOM_diabatic_driver.F90:2905-2923`,
19 lines) zeroes out all entrainment terms and forwards everything into one call,
`call_tracer_column_fns`. Unlike `advect_tracer`/`tracer_hordiff`, that one descendant is
**not** promoted to its own entry point — see the reasoning below, recorded here because it
changes how little of this tree actually needs converting.

No pre-existing audit doc existed for this entry point.

## Hard precondition checks

- **Caller**: `MOM.F90:1848`, inside `step_MOM_thermo` (`MOM.F90:1717`) — genuinely cross-module,
  unlike `step_MOM_tracer_dyn`'s same-file situation. Signature is cleanly externally fixed, no
  wrinkle.
- **Shared-descendant check — `call_tracer_column_fns`**: `public` in `MOM_tracer_flow_control`,
  called from 7 places outside this tree: `diabatic_ALE_legacy`, `diabatic_ALE`,
  `layered_diabatic` (all `MOM_diabatic_driver.F90`, none are campaign entry points) and 3 sites
  in `MOM_offline_main.F90`. **Decision (user): do not promote it to its own entry point.**
  Every one of its ~16 dispatch targets (`OCMIP2_CFC_column_physics`, `MOM_generic_tracer_column_physics`
  — the latter under `config_src/external/GFDL_ocean_BGC/`, the same swappable-pluggable-stub
  shape already flagged for `MOM_particles.F90` — `pseudo_salt_tracer_column_physics`,
  `MARBL_tracers_column_physics`, `ideal_age_tracer_column_physics`, `dye_tracer_column_physics`,
  `oil_tracer_column_physics`, and ~9 more) lives in its own independent module, confirmed called
  from nowhere but `call_tracer_column_fns` — each is an independently-maintained science package,
  not a core-solver kernel. Since every leaf underneath it is going to stay opaque regardless,
  running Phase 2/3 on `call_tracer_column_fns` itself would produce a shim whose AMReX branch has
  nothing to call into — bookkeeping without payoff, unlike EOS (8 of 9 forms genuinely bridge) or
  `advect_tracer`/`tracer_hordiff` (real kernels underneath worth converting). **Classification:
  `call_tracer_column_fns` — leave alone, opaque, widely shared, view-marshal at the call site**,
  same tier as the EOS calls or `thickness_to_dz`. No separate plan file. The shared-descendant
  flag resolves trivially: nothing is being converted there, so there's nothing to reconcile with
  `diabatic_ALE`/`layered_diabatic` if/when they're surveyed later.
- Not an entry point, out of scope: nothing else in this file's public list is reached from
  `adiabatic` — its tree has no other descendants at all.

## Step 1d — wrapper case

**Case 3** — plain subroutine, called directly, no existing alias/wrapper.
`adiabatic` → `adiabatic_TR`, new `adiabatic` wrapper. Wrapper never bridged.

## External signature (frozen — do not change)

`adiabatic(h, tv, fluxes, dt, G, GV, US, CS)` — `MOM_diabatic_driver.F90:2905-2914`. All 8 dummies
mandatory, no optionals, no bare `pointer` dummies except `CS` itself (`type(diabatic_CS), pointer`).

## Full descendant list

None. `adiabatic`'s only call is to `call_tracer_column_fns`, classified leave-alone above. There
is nothing else in this tree for Phase 2/3 to touch beyond `adiabatic`'s own dummies.

## `tv`, `fluxes`, `CS` — all confirmed pure pass-through, need no shadow in this tree

Grep-confirmed against the full 19-line body:
- **`tv`** (`thermo_var_ptrs`, already a union elsewhere — `PressureForce`, `tracer_hordiff`):
  zero `tv%field` dereferences inside `adiabatic` itself. Passed straight into the opaque
  `call_tracer_column_fns` call. Same treatment as `vertvisc_limit_vel`/`write_u_accel` forwarding
  `ADp` opaquely — no shadow build needed in `adiabatic_TR`'s wrapper; `tv` stays a plain
  derived-type dummy, unconverted, for this tree.
- **`fluxes`** (`type(forcing)` — note: distinct from the already-tracked `mech_forcing`/`forces`
  union): zero dereferences inside `adiabatic`. Same pure-pass-through treatment, no shadow.
- **`CS`** (`diabatic_CS`): exactly 3 fields touched — `CS%optics`, `CS%tracer_flow_CSp`,
  `CS%debug` — and all 3 are extracted only to feed the same one opaque call, never branched on,
  never dereferenced further. `diabatic_CS` itself is shared far outside this tree (used by
  `diabatic_ALE`/`diabatic_ALE_legacy`/`layered_diabatic`, none in scope) — the same shape as
  `MOM_control_struct` was for `step_MOM_tracer_dyn`, but since nothing here actually needs a
  shadow (every touched field is pure pass-through into a leave-alone call), there is nothing to
  build. **No shadow, no bundle — `CS` stays a plain pointer dummy, unconverted.**

This is why this tree's Phase 2 work is unusually light: with `call_tracer_column_fns` opaque and
`tv`/`fluxes`/`CS` all pure pass-through, the only genuine conversion target in the whole tree is
`h` itself.

## Step 2 — target classification (fixed-rule items)

| Target | Classification | Skill | Notes |
|---|---|---|---|
| `h` | mandatory raw array dummy | `convert_array_containers` | The only real container work in this tree — standard 3-D real array, still needs converting on `adiabatic`'s own signature even though it's immediately view-marshalled back to raw for the opaque call, same as every other entry point that calls an opaque leaf. |
| `tv`, `fluxes`, `CS` | pure pass-through, confirmed by grep | leave alone, no shadow/bundle | See dedicated section above. |
| `call_tracer_column_fns` | widely-shared leaf, all descendants pluggable science packages | leave alone — view-marshal at call site | See Hard precondition checks above; no entry-point promotion, no plan file. |
| `G`, `GV`, `US` | shared grid/scaling types | `convert_array_containers`'s own drop mechanism | Lightly used (only for `h`'s `SZI_`/`SZJ_`/`SZK_` shape and the internal `zeros` local) — flag for upward-pass drop consideration. |
| `dt` | scalar | nothing to do | Forwarded opaquely into the leave-alone call. |

## Phase 2 execution order

1. **TreeRoot split** — `adiabatic` → `adiabatic_TR` + wrapper (Step 1d).
2. **`create_shadow_container_type`** — none needed (`tv`/`fluxes`/`CS` all pure pass-through).
3. **`create_config_bundle_type`** — none needed (no private CS bundling target — `CS` stays
   unconverted).
4. **Optional-array containerization** — none needed, no optional dummies at all.
5. **`convert_array_containers` — downward pass** — `h` only, at `adiabatic_TR`. There is no
   deeper level to push it into, since `call_tracer_column_fns` stays raw.
6. **`convert_array_containers` — upward pass** — `G`/`GV`/`US`-drop decision for `adiabatic_TR`
   itself (single-subroutine tree, so this is really just confirming whether all three survive
   the drop check).
7. **`convert_locals_to_containers`** — the local `zeros` array, once `h`'s container is stable.
8. **`convert_present_to_associated`** — not needed, no optionals.
9. **`hoist_container_marshalling`**, once, at `adiabatic_TR` — marshals `h`'s container back to
   raw for the `call_tracer_column_fns` call (and `zeros`, `tv`, `fluxes`, `CS` pass through
   unchanged).

## Phase 3 wave order

- **Wave 1 (root, only wave)**: `adiabatic_TR`. No leaves to bridge first — `call_tracer_column_fns`
  is external/opaque, not part of this tree's bridging at all.

Wrapper (`adiabatic`) never bridged.

## Branch

`claude_adiabatic_calltree`, created once before Phase 2 Stage 1.
