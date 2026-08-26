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
| `buggy_Wright_EOS` | `MOM_EOS_Wright.F90` | 1115 | Closed-form, self-contained. **Explicitly legacy** — kept for bit-reproducing historical bugged behavior via an opt-in flag (`USE_WRIGHT_2ND_DERIV_BUG`) |
| `Wright_full_EOS` | `MOM_EOS_Wright_full.F90` | 992 | Closed-form, self-contained. **This codebase's default** (`EOS_DEFAULT`) |
| `Wright_red_EOS` | `MOM_EOS_Wright_red.F90` | 994 | Closed-form, self-contained |
| `Jackett06_EOS` | `MOM_EOS_Jackett06.F90` | 510 | Closed-form rational polynomial, self-contained |
| `TEOS10_EOS` | `MOM_EOS_TEOS10.F90` | 247 (thin wrapper) | **Delegates to the vendored GSW-Fortran toolbox** (`pkg/GSW-Fortran/`, ~200 files/~16,478 lines). The module's own docs recommend switching to `Roquet_rho`/`Roquet_SpV` instead; a known upstream GSW bug already causes one of its self-consistency tests to be skipped. |
| `Roquet_rho_EOS` | `MOM_EOS_Roquet_rho.F90` | 691 | Closed-form polynomial fit, self-contained. The "NEMO-compatible" form (`EOS_NEMO_STRING` aliases to it) |
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
`calculate_density_second_derivs`, `calculate_compress`, and `calculate_TFreeze` are all
**generic interfaces** (`MOM_EOS.F90:70-110`) resolving by argument shape to concrete
`_scalar`/`_1d`/`_2d` module subroutines — e.g. `calculate_density_1d` (line 314),
`calculate_density_2d` (364), `calc_spec_vol_1d` (537), `calculate_density_derivs_1d` (846),
`calculate_density_derivs_2d` (898). **These are ordinary module subroutines, not type-bound
procedures** — unlike the array-level wrappers above, they fit the exact shim mechanism
`cpp_bridge_lessons` already established for `PPM_limit_pos`/etc. with no restructuring needed.
`calculate_TFreeze` (freezing-point calculation) is a related but distinct family, found during
this survey but not yet fully catalogued — confirm its own concrete routine list during
implementation, don't assume it's out of scope just because it wasn't named in the original
"why this exists" framing.

The `_scalar` variants (single-point calls) have no meaningful AMReX mode — there's no array to
dispatch to a GPU kernel for one point — so they need no shim at all; leave them calling the
unchanged type-bound elemental kernels directly.

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
   `calculate_density_derivs`, `calculate_density_second_derivs`, `calculate_compress`, and
   `calculate_TFreeze` pending its own confirmation) and each array rank (`_1d`, `_2d`) it has:
   apply the `cpp_bridge_lessons` shim recipe with **one deliberate deviation from the PPM
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

**What this design deliberately leaves open, for whoever implements the C++ side (explicitly not
this document's deliverable, same boundary `cpp_bridge_lessons` itself draws):** the actual
dispatch mechanism among the 8 forms in C++ — a template-per-form instantiation selected once at
setup, a resolved-once function pointer, or a loop-invariant enum branch outside the per-cell
kernel are all plausible AMReX idioms; which one fits best is an AMReX architecture decision
informed by (but not made by) this survey. The informing context: the choice is invariant per
run, 8 of the forms are small enough that any of these approaches is cheap, and none of them
need to accommodate TEOS10's heavier dependency in this pass.

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

1. **Full enumeration of every concrete `_scalar`/`_1d`/`_2d` routine name** across all 6+ kernel
   families, including confirming `calculate_TFreeze`'s exact scope — partially confirmed via
   grep in this survey, not exhaustively catalogued. Do this precisely at implementation time.
2. **`TEOS10_EOS`** — its own dedicated porting effort (vendored GSW-Fortran toolbox), not
   scheduled.
3. **The C++-side dispatch mechanism** — see above, an AMReX architecture decision for whoever
   picks up implementation.
4. **Whether/when to revisit the ~15-18 "heavy" EOS consumers not yet surveyed as their own
   `convert_calltree` entry points** (`MOM_mixed_layer_restrat`, `MOM_neutral_diffusion`,
   `MOM_thickness_diffuse`, `MOM_bulk_mixed_layer`, `MOM_set_viscosity`, etc.) — this design
   makes their eventual EOS calls bridge-ready once they're each surveyed, but none of them have
   been scoped as entry points yet.
