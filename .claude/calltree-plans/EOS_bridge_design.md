# Design: bridging `MOM_EOS.F90`'s equation-of-state dispatch to C++/AMReX

**Status: planning only — no implementation yet.** This is not a `convert_calltree` entry-point
plan (`MOM_EOS.F90` has no single external signature and no descendant tree in that sense) — it's
the blocking prerequisite recorded in `shared_type_unions.md`, worked out properly instead of
deferred again. Read `cpp_bridge_lessons` before implementing any of this — the mechanism
described here is a direct application of that skill's shim pattern, not a new one.

## Why this exists

Every entry point surveyed so far that reaches EOS (`PressureForce` pervasively,
`horizontal_viscosity`'s QG-Leith branch at its `calc_QG_slopes` boundary, and — discovered as
side effects, not campaign entry points — `MOM.F90`'s main step and `MOM_MEKE.F90` via
`calc_isoneutral_slopes`) has used the same stopgap: leave every EOS call raw, marshal via
container `%view`, never touch `MOM_EOS.F90` itself. That's fine as an immediate unblock, but it
doesn't get any entry point's EOS-dependent computation onto AMReX/GPU — ever — until EOS itself
is solved. This document is that solution's design.

## Survey findings

### The 9 concrete implementations

`EOS_type` (`MOM_EOS.F90:113-160`) holds `class(EOS_base), allocatable :: type`. `EOS_base` is
`abstract` (`MOM_EOS_base_type.F90:13`) with 9 deferred kernels, **8 of which are declared
`elemental`** (hence `pure`): `density_elem`, `density_anomaly_elem`, `spec_vol_elem`,
`spec_vol_anomaly_elem`, `calculate_density_derivs_elem`, `calculate_density_second_derivs_elem`,
`calculate_specvol_derivs_elem`, `calculate_compress_elem` (the 9th, `EOS_fit_range`, is a plain
subroutine, not used by any array wrapper). No `do concurrent`/purity obstacle anywhere in this
subsystem, unlike `CorAdCalc`'s WENO family.

| Implementation | File | Lines | Complexity |
|---|---|---|---|
| `linear_EOS` | `MOM_EOS_linear.F90` | 759 | Trivial closed-form (`density_elem` is one line) |
| `UNESCO_EOS` | `MOM_EOS_UNESCO.F90` | 586 | Closed-form rational polynomial, self-contained |
| `buggy_Wright_EOS` | `MOM_EOS_Wright.F90` | 1192 | Closed-form, self-contained. **Explicitly legacy** — kept for bit-reproducing historical bugged behavior via an opt-in flag (`USE_WRIGHT_2ND_DERIV_BUG`) |
| `Wright_full_EOS` | `MOM_EOS_Wright_full.F90` | 992 | Closed-form, self-contained. **This codebase's default** (`EOS_DEFAULT`) |
| `Wright_red_EOS` | `MOM_EOS_Wright_red.F90` | 994 | Closed-form, self-contained |
| `Jackett06_EOS` | `MOM_EOS_Jackett06.F90` | 510 | Closed-form rational polynomial, self-contained |
| `TEOS10_EOS` | `MOM_EOS_TEOS10.F90` | 247 (thin wrapper) | **Delegates to the vendored GSW-Fortran toolbox** (`pkg/GSW-Fortran/`, ~200 files/~16,478 lines). The module's own docs recommend switching to `Roquet_rho`/`Roquet_SpV` instead; a known upstream GSW bug already causes one of its self-consistency tests to be skipped. |
| `Roquet_rho_EOS` | `MOM_EOS_Roquet_rho.F90` | 943 | Closed-form polynomial fit, self-contained. The "NEMO-compatible" form (`EOS_NEMO_STRING` aliases to it) |
| `Roquet_SpV_EOS` | `MOM_EOS_Roquet_SpV.F90` | 776 | Closed-form polynomial fit in specific volume, self-contained |

### Selection mechanism — chosen once, fixed for the whole run

`EOS_init` (`MOM_EOS.F90:1661-1852`) reads the `EQN_OF_STATE` config string once, maps it to a
`form_of_EOS` integer, and calls `EOS_manual_init` (`MOM_EOS.F90:1855-1920`), which does the
actual polymorphic allocation:
```fortran
select case (EOS%form_of_EOS)
  case (EOS_LINEAR)        ; allocate(linear_EOS :: EOS%type)
  case (EOS_WRIGHT)        ; allocate(buggy_Wright_EOS :: EOS%type)
  ...
end select
```
**`EOS_init` is called at exactly 2 sites in the entire codebase** — `MOM.F90:3225` (main ocean
model) and `MOM_ice_shelf.F90:1931` (independent ice-shelf sub-model instance) — both at
component-initialization time, never inside a timestep loop. (The unit-test harness,
`test_MOM_EOS.F90`, re-inits repeatedly to swap forms for self-consistency testing — the
*mechanism* must stay swappable, but no production run ever re-selects mid-run.) **This is the
single most important property for the bridge design**: the C++ side does not need genuine
runtime virtual dispatch inside a hot per-cell loop — it can resolve the form once, the same way
Fortran does.

### The array-level wrapper functions — not the bridge seam, but the "Fortran truth" underneath

`MOM_EOS_base_type.F90` provides 8 type-bound, non-deferred wrapper procedures on `EOS_base`
(`calculate_density_array`, `calculate_density_array_2d`, `calculate_spec_vol_array`,
`calculate_density_derivs_array`, `calculate_density_derivs_2d`,
`calculate_density_second_derivs_array`, `calculate_specvol_derivs_array`,
`calculate_compress_array`). Each is tiny (21-30 lines): resolve an index window (`start`/`npts`
or a `dom(2,2)` bound box), branch once on `present(rho_ref)`-style anomaly args, then one
elemental array-section dispatch line, e.g. `rho(js:je) = this%density_elem(T(js:je), S(js:je),
pressure(js:je))`. No explicit loop anywhere — Fortran's elemental semantics do the work. These
stay completely untouched by this design; they're the reference implementation every shim's
default mode calls into.

### The actual bridge seam — the generic-interface concrete routines in `MOM_EOS.F90`

`calculate_density`, `calc_spec_vol`, `calculate_density_derivs`,
`calculate_density_second_derivs`, and `calculate_compress` are all **generic interfaces**
(`MOM_EOS.F90:70-110`) resolving by argument shape to concrete `_scalar`/`_1d`/`_2d` module
subroutines — e.g. `calculate_density_1d` (line 314), `calculate_density_2d` (364),
`calc_spec_vol_1d` (537), `calculate_density_derivs_1d` (846), `calculate_density_derivs_2d`
(898). **These are ordinary module subroutines, not type-bound procedures** — unlike the
array-level wrappers above, they fit the exact shim mechanism `cpp_bridge_lessons` already
established for `PPM_limit_pos`/etc. with no restructuring needed. `calculate_TFreeze`
(freezing-point calculation) is **not part of this family** — see its own dedicated section below;
it doesn't dispatch through `class(EOS_base)` at all.

The `_scalar` variants (single-point calls) have no meaningful AMReX mode — there's no array to
dispatch to a GPU kernel for one point — so they need no shim at all; leave them calling the
unchanged type-bound elemental kernels directly.

### `calculate_TFreeze` — a separate, smaller polymorphism (survey correction, this session)

**Not one of the five kernel families, and not governed by the same consistency argument.**
Originally grouped in with `calculate_density`/etc.; checking the actual source
(`equation_of_state/MOM_EOS.F90`) shows it's structurally different in a way that matters for the
bridge-mode design:

- `calculate_TFreeze` (generic interface resolving to `calculate_TFreeze_scalar`/`_1d`/`_array` —
  note `_array`, not `_2d`, a different naming convention from the density family) dispatches via
  `select case (EOS%form_of_TFreeze)` into a wholly separate module, `MOM_TFreeze`
  (`calculate_TFreeze_linear`/`_Millero`/`_TEOS_poly`/`_teos10`) — **not** through
  `EOS%type%..._elem(...)`, the `class(EOS_base)` virtual dispatch every density/derivative kernel
  uses. It was never one of the 9 deferred kernels on `EOS_base` to begin with.
- `EOS%form_of_TFreeze` is its own field with its own config parameter, `TFREEZE_FORM`
  (`"LINEAR"`/`"MILLERO_78"`/`"TEOS_POLY"`/`"TEOS10"` — **4** forms, not 8/9). It has a sensible
  default tied to `form_of_EOS` (TEOS10/Roquet_rho/Roquet_SpV default `TFREEZE_FORM` to `TEOS10`;
  everything else defaults to `LINEAR`, `MOM_EOS.F90:2019-2028`), but a user can override it
  independently — a run configured `EQN_OF_STATE=WRIGHT_FULL` with `TFREEZE_FORM=MILLERO_78`
  simultaneously is valid, unremarkable Fortran today, with no consistency requirement between the
  two anywhere in the source.

**Consequence:** the physics-consistency argument that justifies one shared `EOS%bridge_mode`
across the five density-family kernels (a derivative computed by a different backend than the
function it's the derivative of is actually wrong, not just inconsistent) doesn't extend to
`calculate_TFreeze` — it isn't a derivative or component of the density function, it's an
independently-computed empirical curve that Fortran itself already treats as decoupled. Revised
design: `calculate_TFreeze` gets its **own** independent bridge-mode field (following the normal
`cpp_bridge_lessons` per-kernel-independent precedent — the one the density family deliberately
deviates from, not the default this whole campaign otherwise uses) and its **own** 4-form
dispatch/tiering, separate from the switch and tiering built for the 8 density forms above. Not
designed in detail here — smaller in scope than the density-family work, and no entry point in
this campaign currently needs it (see consumer check below) — but tracked as its own follow-up,
not folded into the five-kernel-family framing any more.

**Which entry points actually call it, checked directly (survey correction, this session):**
`calculate_TFreeze` callers are `MOM_diabatic_driver.F90`, `MOM_diabatic_aux.F90`,
`MOM_ice_shelf.F90`, `MOM.F90`, and `MOM_diagnose_MLD.F90` — grepped directly, not inferred.
**None of `horizontal_viscosity` (`MOM_hor_visc.F90`), `vertvisc_family` (`MOM_vert_friction.F90`),
`set_viscosity_family` (`MOM_set_viscosity.F90`), or `tracer_hordiff` (`MOM_tracer_hor_diff.F90`)
reference `TFreeze` at all** — confirmed by grep on each file individually, zero matches. So none
of the entry points already recorded in this campaign as EOS-touching trees need
`calculate_TFreeze` bridged for their own sake. Its actual consumers
(`MOM_diabatic_driver`/`MOM_diabatic_aux` in particular) fall inside the "~15-18 heavy EOS
consumers not yet surveyed as their own `convert_calltree` entry points" already noted below —
this doesn't change that list, just confirms `calculate_TFreeze` isn't relevant until one of
*those* gets surveyed.

### Consumer landscape (59 files using `MOM_EOS` directly)

~15-18 "heavy" consumers (double-digit-to-high-single-digit call sites, genuine hot-loop
dependency: `MOM_mixed_layer_restrat`, `MOM_neutral_diffusion`, `MOM_thickness_diffuse`,
`MOM_bulk_mixed_layer`, `MOM_set_viscosity`, plus the core-dynamics set already surveyed this
session), ~25-28 "light" consumers (1-4 call sites, niche paths), ~8-10 "pure plumbing" (no
direct EOS math call, just carry `EOS_type` as an opaque handle through a derived type). **None
of the 59 reach the vendored GSW toolbox directly** — it's fully walled off behind
`MOM_EOS.F90`'s dispatch, confirming that layer is the right seam regardless of which routines
end up bridged.

Correction to two files assumed in scope earlier this session: **`MOM_continuity_PPM.F90` and
`MOM_MEKE.F90` do not `use MOM_EOS` directly** — `continuity()` never touches EOS at all
(consistent with its "self-contained" audit finding), and `MOM_MEKE.F90` only reaches EOS
*transitively* through `calc_isoneutral_slopes` (itself in `MOM_isopycnal_slopes.F90`, which does
`use MOM_EOS`), not via its own `use` statement.

## Decisions (user, this session)

**Scope: all 8 self-contained forms now, `TEOS10_EOS` deferred.** `linear_EOS`, `UNESCO_EOS`,
`buggy_Wright_EOS`, `Wright_full_EOS`, `Wright_red_EOS`, `Jackett06_EOS`, `Roquet_rho_EOS`,
`Roquet_SpV_EOS` all get bridged in this pass — `buggy_Wright_EOS` specifically because the user
needs it for their first deliverable, not because of a usage-popularity judgment; the other 7
ride along because the survey found no meaningful complexity difference among the 8 (all
self-contained closed-form analytic kernels). `TEOS10_EOS` is the one genuine complexity
outlier (vendored ~16,478-line GSW-Fortran toolbox) — deferred to its own follow-up porting
effort, not solved here.

**Architecture: shim at the `MOM_EOS.F90` generic-interface concrete routines, one shim per
kernel-and-rank (not per EOS form), plus one new one-time init-time bridge call that decides
*both* the form and the FORTRAN/CAPTURE/AMREX mode, once, together.**

1. For each in-scope kernel family (`calculate_density`, `calc_spec_vol`,
   `calculate_density_derivs`, `calculate_density_second_derivs`, and `calculate_compress` —
   **`calculate_TFreeze` is out of this list**, see its own dedicated section above) and each
   array rank (`_1d`, `_2d`) it has: apply the `cpp_bridge_lessons` shim recipe with **one
   deliberate deviation from the PPM
   precedent** — rename the original to `_fortran`, author a new subroutine under the original
   name with the same signature, `select case` on **`EOS%bridge_mode`, read from the already-
   resolved field on the `EOS_type` dummy every one of these shims already receives** (not a
   fresh `getenv_mode(...)` call of its own), default arm calls the renamed `_fortran` original
   (which itself is unchanged, still doing `EOS%type%calculate_density_array(...)` polymorphic
   dispatch exactly as today). Update the generic interface's `module procedure` list to point at
   the new shim names.
2. `convert_array_containers` first, on each shimmed routine's `T`/`S`/`pressure`/`rho`/etc.
   dummies (currently plain `real, dimension(:)`/`(:,:)` arrays) — same precondition as every
   other bridged kernel in this campaign.
3. **New infrastructure beyond the existing pattern**: a one-time setup bridge call (e.g.
   `turbotmp_eos_init_bridge(form_of_EOS, bridge_mode)`), invoked once alongside the real
   `EOS_init`/`EOS_manual_init`, resolving **two things together, not one**: which of the 8
   forms' implementation to use (already planned), and — new — the single `EOS%bridge_mode`
   value (`FORTRAN`/`CAPTURE`/`AMREX`) that every one of this kernel family's shims will read for
   the rest of the run. Store it as a new field on `EOS_type` itself (`MOM_EOS.F90:113-160`,
   alongside `form_of_EOS`) — since `EOS` is already threaded through to every call site (directly
   or via `tv%eqn_of_state`), this needs zero new plumbing anywhere else. `EOS_manual_init`
   (`MOM_EOS.F90:1855-1921`, already `intent(inout)` on `EOS`) is the natural place to set it,
   read once from a single env var (e.g. `EOS_BRIDGE_MODE`), mirroring exactly how `form_of_EOS`
   itself is set once and never revisited mid-run.

**Why this deviates from `cpp_bridge_lessons`' own precedent (user decision, this session).**
The PPM shims (`PPM_limit_pos`/`PPM_limit_cw84`/`PPM_reconstruction_y`) each read their own
dedicated env var, independently, on every call — deliberate, so a kernel could be bisected/
brought up on AMReX independently of its siblings (`cpp_bridge_lessons` §7). That independence is
safe for PPM because those three kernels don't need to agree with each other numerically. EOS's
kernel family does not have that property: `calculate_density` and `calculate_density_derivs`
(and the rest) are expected to stay mutually self-consistent for a given form — physics code
downstream (e.g. Newton-iteration-style pressure adjustments in `PressureForce`) assumes the
derivative genuinely is the derivative of the density function it's paired with. If each shim
independently chose its own mode, a run could end up computing density via one backend and its
derivative via another — silently, since env vars don't change mid-run, but still inconsistently
across kernels within the same run — exactly the failure mode a per-call/per-shim decision can't
rule out and a single init-time decision does. **Trade-off accepted**: this gives up per-kernel
independent AMReX bring-up/bisection for EOS specifically (bisection now happens at the whole-
subsystem level — run with `EOS_BRIDGE_MODE=FORTRAN` vs `=AMREX` and compare — not kernel-by-
kernel). This is a scoped deviation for EOS only; it does not change the already-shipped
per-kernel-independent pattern for `MOM_continuity_PPM`'s three kernels, and doesn't set a new
default for future bridged kernels unless they have the same cross-kernel-consistency property.

**C++ dispatch mechanism among the 8 forms — decided (user decision, this session).** Loop-invariant
enum/`switch` branch outside the per-cell kernel, selecting once per call site — the same pattern
`cpp_bridge_lessons` already established for a call-constant mode split (`MOM_continuity_PPM`'s
Boussinesq/non-Boussinesq dispatch, `generate_amrex_code`'s `lessons.md` §7 #9): one `if`/`switch`
on `form_of_EOS` before the `ParallelFor`, each device lambda then calling exactly one concrete
per-form kernel with no conditional inside it. Rejected the other two options this survey raised:

- **Resolved-once function pointer** — functionally equivalent to the switch if used only to pick
  which lambda to launch (no benefit, plus a dispatch table to keep in sync every time a form is
  added); worse if pushed inside the device lambda itself, since per-cell device function pointers
  are a real portability/performance risk across AMReX's GPU backends (CUDA/HIP/SYCL) for a choice
  that doesn't need per-cell resolution in the first place — the whole point of resolving the form
  once at init, same as Fortran, is that no per-cell dispatch is needed at all.
- **Template-per-form instantiation** — real payoff only for a hypothetical single-form specialized
  build (e.g. a Wright-only build with the branch fully compiled out and inlined); a general build
  still needs a runtime switch on top of the template instantiations to pick one, so it doesn't
  remove the dispatch mechanism, just adds template boilerplate underneath one. Worth revisiting
  only if EOS ever shows up hot in a profile — not needed now.

The switch wins primarily because each `case` arm is ordinary host C++, which is what makes the
per-form verification tiering below trivial to attach — no generic-programming machinery needed to
carry per-form trust/warn/abort behavior.

### Per-form verification tiering (user decision, this session)

Three tiers, attached directly to the dispatch switch's `case` arms:

1. **Trusted** — a full C++ port, verified via the same capture-replay methodology as every other
   kernel in this campaign (`generate_amrex_unit_test`, replayed against real Fortran-captured
   `.bin`/`.meta` fixtures). Called with no warning. **`buggy_Wright_EOS` is the first — and, as of
   this session, only — form scoped to reach this tier**; it's the user's own near-term deliverable,
   built and verified against it specifically.
2. **Implemented, not yet extensively verified** — the other 7 in-scope forms (`linear_EOS`,
   `UNESCO_EOS`, `Wright_full_EOS`, `Wright_red_EOS`, `Jackett06_EOS`, `Roquet_rho_EOS`,
   `Roquet_SpV_EOS`). The original scope decision above (all 8 forms now) still holds — the survey
   found no meaningful complexity difference among them, so there's no real cost saved by deferring
   their C++ translation — but each one's `case` arm calls `amrex::Warning(...)` before dispatching
   to its kernel until it independently earns tier-1 status via its own capture-replay coverage. A
   form graduates from tier 2 to tier 1 exactly when that coverage exists — not on a schedule, not
   by inspection.
3. **Not implemented** — `TEOS10_EOS` (still fully deferred, per the original scope decision) and
   any form whose `case` arm hasn't been written yet. Hard failure via `AMREX_ABORT_LOC`, the same
   guard already used throughout `MOM_continuity_PPM`'s port for `OceanOBC`-not-yet-implemented:
   refuse loudly rather than silently compute something wrong.

**Tier 2's warn-and-proceed is the real runtime behavior, not a placeholder pending a stricter
gate (user decision, this session).** No additional opt-in beyond `EOS_BRIDGE_MODE=AMREX` is
required to actually execute a tier-2 form's kernel — accepted deliberately, because the current
user base is developers on this codebase, not production runs. `amrex::Warning(...)` is the
tier-2 signal now; the plan is to delete each form's warning once its own configuration has
exercised and validated it (see capture-fixture sourcing below), not to add a stronger gate later.
Revisit this posture before any non-developer-facing use of `EOS_BRIDGE_MODE=AMREX`.

**Capture-fixture sourcing for tiers 2→1 (user decision, this session).** No dedicated effort to
generate fixtures for the other 7 forms up front. Every MOM6 configuration already fixes its own
`EQN_OF_STATE` — `double_gyre` happens to use Wright; a future configuration (e.g. `neverworld2`)
may use a different form. As each configuration gets exercised in this campaign's normal course of
work, its capture run naturally produces fixtures for whichever form *that* configuration selects,
and that form graduates from tier 2 to tier 1 as a side effect — the same organic, per-configuration
sourcing every capture fixture in this campaign has already used, not a new process.

**Caveat, confirmed via coverage (applies to both double_gyre and double_gyre_unsplit — base plan,
unaffected by the base/patch split):** "double_gyre happens to use Wright" is true only of the
*configured* `EQN_OF_STATE`, not of runtime coverage. `double_gyre`'s `MOM_input` also sets
`ENABLE_THERMODYNAMICS=False`, so `tv%eqn_of_state` is never `associated` and the EOS
density-calculation kernels are essentially never called — `MOM_EOS.F90` sits at 0.3% line
coverage (3/930 lines) under **both** `double_gyre` and `double_gyre_unsplit` (`SPLIT` doesn't
gate this at all). Don't read "double_gyre selects Wright" as "double_gyre's capture runs actually
exercise/verify the Wright kernels" — they don't, under either config, today. Tier-1 status for
`buggy_Wright_EOS` should be understood as "the configured form," not "runtime-verified by
double_gyre's own capture fixtures."

Sketch (illustrative, not final signatures):
```cpp
switch (form_of_EOS) {
    case EOS_WRIGHT_BUGGY:                    // tier 1: trusted
        ParallelFor(bx, [=] AMREX_GPU_DEVICE (int i, int j, int k) noexcept {
            density_elem_wright(T(i,j,k), S(i,j,k), pressure(i,j,k), rho(i,j,k));
        });
        break;
    case EOS_LINEAR:                          // tier 2: implemented, unverified
        amrex::Warning("EOS: linear_EOS AMReX path not extensively verified yet");
        ParallelFor(bx, [=] AMREX_GPU_DEVICE (int i, int j, int k) noexcept {
            density_elem_linear(T(i,j,k), S(i,j,k), pressure(i,j,k), rho(i,j,k));
        });
        break;
    // ... one case per remaining tier-2 form ...
    case EOS_TEOS10:                          // tier 3: not implemented
    default:
        AMREX_ABORT_LOC("EOS form not yet implemented in AMReX mode");
}
```

### Per-form C++ file layout (user decision, this session)

**One `mom_eos_<form>.{hpp,cpp}` pair per form** (`mom_eos_wright.{hpp,cpp}`,
`mom_eos_linear.{hpp,cpp}`, ... 8 pairs total), rather than one shared `mom_eos.cpp` holding all 8
forms' kernels. This preserves the existing convention every other bridged module in this campaign
already follows — one C++ file pair per Fortran source module (`mom_continuity_ppm.{hpp,cpp}` for
`MOM_continuity_PPM.F90`, and so on) — and EOS already has that one-form-per-file structure on the
Fortran side (`MOM_EOS_linear.F90`, `MOM_EOS_Wright.F90`, `MOM_EOS_UNESCO.F90`, ...), so this is the
structure-preserving choice, not a new one. The dispatch `switch` (above) lives in whichever file
owns the five kernel-family bridges (mirroring `turbotmp_mom_continuity_ppm_bridge.cpp`'s role) and
`#include`s each form's header to reach its `density_elem_<form>`-style functions; each `case` arm
calls into its own form's file, nothing more.

## Per-call-tree AMReX-mode scoping (user decision, this session)

**Problem:** `EOS%bridge_mode` lives on the single shared `EOS_type` instance (reached via
`tv%eqn_of_state`) that every EOS-touching call site in the model shares — there's no way for a
shim to tell, from its arguments alone, whether a call originated in `PressureForce`'s
`Set_pbce_Bouss` or in `horizontal_viscosity`'s `calc_QG_slopes`. The user wants to bring up
`EOS_BRIDGE_MODE=AMREX` against `PressureForce` only, while it's the only tree in this campaign
that's actually exercised it, without other already-shipped EOS-touching trees
(`horizontal_viscosity`, `vertvisc_family`, `set_viscosity_family`, `tracer_hordiff`) picking up
AMReX-mode EOS execution as an unintended side effect of the same global flag.

**Mechanism: two variables, AND'd together, composed in one new shared helper.**

1. **Set by the call tree** — not an env var, a literal string constant baked into each converted
   tree's own thin wrapper source (e.g. `"PressureForce"` in the `PressureForce` wrapper authored
   by Phase 2 Stage 1's TreeRoot split). Fixed at authoring time, one per tree, no runtime
   configurability needed since it's not something a user should be choosing.
2. **Set by the user** — a new env var, `EOS_BRIDGE_MODE_TREES` (comma-separated tree-name
   allowlist, e.g. `EOS_BRIDGE_MODE_TREES=PressureForce`), read once at init alongside the existing
   `EOS_BRIDGE_MODE` read in `EOS_manual_init`. Empty/unset means "all trees allowed" — so this
   mechanism is a no-op, not a new restriction, until a user actually sets it.

**Implementation shape:** a small new dynamically-scoped module variable holds the name of the
call tree currently executing (e.g. `current_calltree_scope`). Each converted tree's own wrapper
sets it to its own tree-name constant on entry and restores the caller's previous value on exit —
costing two lines in a subroutine each tree's Phase 2 Stage 1 already authors as a pure
pass-through, with no changes needed to any subroutine downstream of the wrapper (`Set_pbce_Bouss`,
the EOS shims, etc. — none of them need to know this mechanism exists). **Caveat to check at
implementation time:** Fortran has no destructors, so the restore has to happen on every return
path out of the wrapper, not just a final line — fine if the wrapper is a genuine single
pass-through call with one exit, needs an explicit restore before each return (or a refactor to a
single-exit shape) if it isn't.

The five EOS shims stop reading `EOS%bridge_mode` directly and instead call one new centralized
helper, e.g. `effective_eos_bridge_mode(EOS, current_calltree_scope)`, which returns
`EOS%bridge_mode` only when `current_calltree_scope` is in `EOS%bridge_mode_trees` (or when that
allowlist is empty), and forces Fortran-truth otherwise. One shared change, not five.

**Gates `AMREX` mode only — `CAPTURE` mode stays ungated everywhere (user decision, this
session).** Gating `CAPTURE` too would block the organic per-configuration fixture-sourcing plan
above (a form/tree combination can't graduate tier 2→1 if its captures never get recorded because
the tree wasn't in the allowlist yet). So `effective_eos_bridge_mode` only substitutes
Fortran-truth in place of `AMREX` when the current tree is out of scope; a `CAPTURE`-mode request
passes through unchanged regardless of tree scope.

**This is shared infrastructure, same sequencing question as the marshalling helper below.** The
scope variable, the new env var, and `effective_eos_bridge_mode` all live in code every
EOS-touching tree shares, not code `PressureForce` owns alone — so it needs the same "who authors
it, which PR, landing before which trees depend on it" resolution as the marshalling helper
(explicitly still open, see "Explicitly not resolved here" below).

## Shared marshalling helper (user decision, this session)

Every EOS-touching entry point (`PressureForce` pervasively, `horizontal_viscosity`,
`vertvisc_family`, `set_viscosity_family`, `tracer_hordiff`, and any future one) currently repeats
the same few lines at each call site: unwrap that tree's own container back to a raw pointer,
call the still-unbridged `calculate_density`/`calculate_density_derivs`/etc., wrap the raw result
back into a container. Left inline, this boilerplate shows up dozens of times across every EOS-
touching tree's diff even though it's identical logic everywhere. **Decision: factor it into one
small shared helper** (e.g. `marshal_call_EOS_density(container_in, container_out, EOS, ...)`),
authored once as part of the same combined infrastructure PR as the shared-type-union work (see
`shared_type_unions.md`), not as a side effect of whichever EOS-touching tree's PR runs first.
Every entry point's own call site then becomes one call into the helper instead of several inline
unwrap/rewrap lines — this is genuinely extractable, unlike the mode-selection logic above,
because the helper's *content* doesn't depend on which tree calls it; only the container it's
handed does. This does not change any bridging decision above — the helper wraps the same shim
call every tree already makes, it's a diff-size reduction, not a design change.

## Payoff: no existing plan needs to change

Because every shim's default mode is Fortran-truth (bit-identical to today, per
`cpp_bridge_lessons` §1), **none of the "leave EOS alone" classifications already recorded in
`btstep.md`, `horizontal_viscosity.md`, `PressureForce.md`, or `vertvisc_family.md` need to be
revisited once this lands.** Those trees keep calling `calculate_density`/`calculate_density_derivs`/
etc. completely unchanged — the shim transparently sits underneath, and AMReX mode only activates
when explicitly enabled. This bridge is additive, not a breaking change to any plan already
written this session.

## Explicitly not resolved here — follow-up work

1. **Full enumeration of every concrete `_scalar`/`_1d`/`_array` routine name for
   `calculate_TFreeze`'s own (separate) bridge** — its dispatch shape and consumers are now
   confirmed (see its dedicated section above), but the actual per-rank shim design for its 4-form
   dispatch hasn't been worked out, since no entry point in this campaign needs it yet. Do this
   when a tree that actually calls `calculate_TFreeze` gets surveyed (see item 4 below).
2. **`TEOS10_EOS`** — its own dedicated porting effort (vendored GSW-Fortran toolbox), not
   scheduled.
3. **Actually porting the 8 in-scope forms' elemental kernels to C++.** The dispatch mechanism and
   verification tiering are now decided (above); the per-form translations themselves — 8 kernel
   ports across up to 8 elemental methods each — are not this document's deliverable and haven't
   started. `buggy_Wright_EOS` is the only one with a concrete near-term plan (the user's own
   deliverable); the other 7 ride along per the scope decision but have no implementation order
   fixed yet.
4. **Whether/when to revisit the ~15-18 "heavy" EOS consumers not yet surveyed as their own
   `convert_calltree` entry points** (`MOM_mixed_layer_restrat`, `MOM_neutral_diffusion`,
   `MOM_thickness_diffuse`, `MOM_bulk_mixed_layer`, `MOM_set_viscosity`, etc.) — this design
   makes their eventual EOS calls bridge-ready once they're each surveyed, but none of them have
   been scoped as entry points yet.
5. **Whether the two `EOS_type` instances (`MOM.F90`'s main ocean model and
   `MOM_ice_shelf.F90`'s independent sub-model) are allowed to independently diverge in
   `form_of_EOS` and/or `bridge_mode`.** Deferred (user decision, this session) — not a design gap
   being actively worked around, just genuinely out of scope right now: the double_gyre
   configuration this work is verified against doesn't exercise the ice-shelf sub-model, and there's
   no near-term plan to use it. Revisit if/when an ice-shelf configuration actually enters scope.
6. **Landing sequencing for the two pieces of shared infrastructure this design introduces** — the
   marshalling helper and the per-call-tree AMReX-mode scoping mechanism (`current_calltree_scope`,
   `EOS_BRIDGE_MODE_TREES`, `effective_eos_bridge_mode`). Both are decided in shape, both live in
   code every EOS-touching tree shares rather than code any one tree owns, and neither has a
   decided answer for which PR authors them or whether a tree can land its own inline stand-in
   first and swap to the shared version later. Since `PressureForce` is the first tree to actually
   need the scoping mechanism, it may end up the natural place both pieces first land — but that's
   not decided, just plausible.
