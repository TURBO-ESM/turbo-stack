# TURBO Stack backlog

Work items that are known but not yet scheduled, across turbo-stack and its
submodules. Each item names the component it lives in, so it can move to that
repository's issue tracker when it is picked up.

Format: one `##` section per item, with a stable ID (`TB-NNN`), and these fields:
**Component**, **Status** (`open` / `in progress` / `deferred` / `done`), **Opened**,
**Summary**, **Details**, **Proposed fix**, **Verification**.

Completed work is recorded in `CHANGELOG.md`, not here. When part of an item is
done, its entry here keeps only the remaining work and points to the changelog.

Related backlogs elsewhere:
- `submodules/protoMOMxx/.claude/skills/generate_amrex_code/lessons.md` §9
  (kernel-port backlog: fusing the orchestrator kernels' Newton iteration).
- `submodules/protoMOMxx/docs/design/northeast_stagger_views.md`
  (prerequisites and performance items for calling `mom_kernels` from the
  protoMOMxx driver).

---

## TB-001: Remove `isd`/`ied` from the continuity PPM code, starting in MOM6

- **Component:** MOM6 (`dev/turbo-debug`, `src/core/MOM_continuity_PPM.F90`,
  `src/core/MOM_continuity.F90`), then protoMOMxx (`src/mom_kernels/`, `tests/test_mom/`)
- **Status:** open
- **Opened:** 2026-11-03

### Summary

MOM6's `meridional_mass_flux` takes the data-domain i-range (`isd`, `ied`) as
plain integers. It uses them only to fill the scratch array `visc_rem_v_tmp`
over `i=isd:ied`, but every reader of that array stays inside the iteration
box's range `i=ish:ieh`. The wider fill is unnecessary.

The arguments thread through the continuity call chain and the `bind(C)`
interfaces. The mechanical port carried them into the C++ kernel API, where they
are the only iteration-space input not derived from an `amrex::Box`.

The fix belongs in the Fortran source, which is the source of truth for the
ports. Fix it there, then carry the change through the bridge interfaces,
captures, C++ kernels and tests, so both sides stay identical and bit-for-bit.

### Details

MOM6, `dev/turbo-debug` at `16501b711`, `src/core/MOM_continuity_PPM.F90`.
Line numbers are approximate; re-check before editing.

- **The only use.** In `meridional_mass_flux_fortran` (~4148), inside the
  `J` loop (~4280-4297):

  ```fortran
  if (.not.use_visc_rem) then
    do concurrent (k=1:nz, i=isd:ied)
      visc_rem_v_tmp(i,J,k) = 1.0
    enddo
  else
    do concurrent (k=1:nz, i=isd:ied)
      visc_rem_v_tmp(i,J,k) = visc_rem_v(i,J,k)
    enddo
  endif
  ```

  (marked `! this is expensive`).
- **Every Fortran read of `visc_rem_v_tmp` stays within `ish:ieh`:**
  - `flux_elem` and the `visc_rem_max` and CFL-limit loops in
    `meridional_mass_flux_fortran`;
  - the `v_cor` update;
  - `meridional_flux_adjust`, `set_merid_BT_cont` and
    `meridional_flux_thickness`, which receive `visc_rem_v_tmp_a`.

  `zonal_mass_flux_fortran` already fills `visc_rem_u_tmp` over the iteration
  range only and takes no such arguments.
- **Where `isd`/`ied` are passed** (all must change together):
  - `subroutine continuity_PPM` (~1136) and `continuity_PPM_fortran` (~976/993);
    the latter forwards them to `meridional_mass_flux` (~1090, ~1107).
  - `continuity_PPM_3d_fluxes` (~1448, call at ~1503).
  - `continuity_PPM_adjust_vel` (~1693, call at ~1781).
  - `meridional_mass_flux` dispatcher (~4534) and `meridional_mass_flux_fortran`
    (~4148).
  - `bind(C)` interfaces `turbotmp_meridional_mass_flux_bridge` (~709-740) and
    `turbotmp_continuity_ppm_bridge` (~822-866), and their call sites in the
    AMReX branches (~1422, ~4722).
  - Capture records `rec%add("_isd"/"_ied", ...)` (~1272-1273, ~4632-4633).
  - Callers in `src/core/MOM_continuity.F90`, which pass `G%isd, G%ied`
    (~150, ~217, ~353).
- **protoMOMxx counterparts:**
  - `mom_continuity_ppm.hpp:195-196` and `mom_continuity_ppm.cpp:392-393`,
    `:466`, `:481`, `:903-904`;
  - the `bx_visc_wide` scratch box at `mom_continuity_ppm.cpp:972-1002`;
  - the bridge prototypes in `turbotmp_mom_continuity_ppm_bridge.{h,cpp}`
    (`isd_dev`/`ied_dev` conversions);
  - `tests/test_mom/mom_continuity_ppm/test_mom_continuity_ppm.cpp:187-188`,
    `:266-267`, `:370-371`, `:419-420`.
- **Unrelated hits.** `OBC%segment(n)%HI%isd/ied` in Fortran, and
  `segment.HI.isd/ied` in the disabled C++ OBC blocks, are segment ranges, not
  these arguments. Leave them alone.

### Proposed fix

1. **MOM6 Fortran (the source of truth).**
   - In `meridional_mass_flux_fortran`, fill `visc_rem_v_tmp` over `i=ish:ieh`
     instead of `i=isd:ied`. If the `allocView` bounds are left as they are, the
     untouched columns are never read.
   - Remove the `isd`/`ied` dummy arguments from `meridional_mass_flux_fortran`,
     the `meridional_mass_flux` dispatcher, `continuity_PPM_fortran`,
     `continuity_PPM`, `continuity_PPM_3d_fluxes` and `continuity_PPM_adjust_vel`.
     Remove them from their call sites, including the three callers in
     `MOM_continuity.F90`.
   - Remove them from the `turbotmp_meridional_mass_flux_bridge` and
     `turbotmp_continuity_ppm_bridge` `bind(C)` interfaces and their AMReX-branch
     calls.
   - Remove the `_isd`/`_ied` capture records.
   - Follow the repository's verification discipline for multi-site Fortran
     edits (`CLAUDE.md`): afterwards, grep the whole file for
     `\bisd\b`/`\bied\b` with zero tolerance outside the OBC segment ranges.
2. **protoMOMxx bridge.** Remove `isd`/`ied` from the `extern "C"` prototypes
   of `turbotmp_continuity_ppm_bridge` and `turbotmp_meridional_mass_flux_bridge`,
   in both the `.h` and the `.cpp`, to match the new `bind(C)` interfaces. Drop
   the `isd_dev`/`ied_dev` conversions.
3. **protoMOMxx kernels.**
   - Size and fill `visc_rem_v_tmp` over `bxV` in `MOM::meridional_mass_flux`,
     and delete `bx_visc_wide`, mirroring the Fortran change.
   - Remove `isd`/`ied` from `MOM::meridional_mass_flux` and
     `MOM::continuity_PPM`, and from the forwarding calls inside
     `continuity_PPM`.
4. **Captures and tests.**
   - Regenerate the `continuity_ppm` and `meridional_mass_flux` capture fixtures
     from the updated MOM6, since they no longer contain `_isd`/`_ied`.
   - Update the `ContinuityPPM` and `MeridionalMassFlux` tests to stop reading
     and passing them.
5. **Design note.** Update `submodules/protoMOMxx/docs/design/northeast_stagger_views.md`:
   the `Continuity::step` sketch no longer derives `isd`/`ied` from the fab box.
6. **Land the MOM6 and protoMOMxx changes as a pair**, with the turbo-stack
   submodule bumps. As with the original protoMOMxx bridge switch, an
   interface change on one side alone breaks the TIM link.

### Verification

- **MOM6, Fortran path.** The double_gyre and benchmark answers are unchanged
  bit for bit before and after the change (`CONTINUITY_PPM_MODE` left at the
  Fortran default). The removed fill was never read, so any difference is a bug.
- **MOM6, AMReX path.** It still matches the Fortran path bit for bit.
- **protoMOMxx.** `test_mom`'s `ContinuityPPM` and `MeridionalMassFlux` pass on
  the regenerated captures.
- **Nothing left behind.**
  - `git grep -nw "isd\|ied"` on the touched MOM6 files shows only `G%isd`
    uses unrelated to continuity and the OBC segment ranges.
  - In protoMOMxx, `grep -n "isd\|ied" src/mom_kernels/*continuity_ppm*`
    shows only the commented-out `segment.HI.*` OBC code.

---

## TB-002: Adopt northeast (MOM6) stagger views for all stencil code

- **Component:** protoMOMxx, `config_src/infra/`, `src/types/`, `src/initialization/`
- **Status:** open
- **Opened:** 2026-11-03

### Summary

The ported kernels in `src/mom_kernels/` use MOM6's northeast stagger convention:
u point `i` is the east face of cell `i`. The native protoMOMxx fields use AMReX's
southwest convention: u point `i` is the west face of cell `i`.
`MOM_domain_infra.hpp` currently documents that "transcribed stencils shift by
one". Passing native staggered storage straight to a kernel would put every
staggered access one face off, and the result would look plausible.

### Details

The full design, with code sketches, is in
`submodules/protoMOMxx/docs/design/northeast_stagger_views.md`. In short:

- Storage stays AMReX-native southwest.
- Stencil code sees zero-copy northeast views, where `view(i) == storage(i+1)`
  along each nodal direction.
- Typed fields (`HField`/`UField`/`VField`/`QField`) make the view the only
  way stencil code can reach the data.

This keeps the kernels byte-identical, so MOM6 can keep calling them through the
bridge, which the team expects to do for at least another four years.

### Proposed fix

1. In `MOM_domain_infra.hpp`, add `mom_view()` and `Field<Stagger>`, and have
   `Domain::make_{h,u,v,q}_field` return typed fields. `pass_var`/`pass_vector`
   take typed fields and act on `.storage()`.
2. Rewrite the `MOM::Domain` class comment: storage is southwest, all stencil
   code is northeast. Remove the "transcribed stencils shift by one" paragraph.
3. Switch `GridFields`, `Grid` and `State` to the typed fields.
4. Convert the existing southwest stencil code to views. Today that is
   `spherical_grid_fields` and `set_masks` in `MOM_grid_initialize.cpp`, e.g.
   `maskCu(i) = maskT(i-1)*maskT(i)` becomes `maskT(i)*maskT(i+1)`.

### Verification

- New capture-replay test: load a `test_mom` capture into southwest-storage
  typed fields (shift +1 on load along nodal directions), call the kernel
  through `.array(mfi)`, and compare to the `_after` arrays bit for bit.
  Land this test before step 4.
- `MOM_grid`, `MOM_fixed_initialization` and `double_gyre` tests unchanged.

---

## TB-003: Driver-side continuity caller (`src/core/MOM_continuity`)

- **Component:** protoMOMxx, `src/core/`
- **Status:** open (caller-pattern decision 2026-11-03)
- **Opened:** 2026-11-03
- **Depends on:** TB-002, TB-005
- **Related:** TB-001, TB-007, TB-012, TB-013, TB-014

### Summary

Nothing in protoMOMxx calls `mom_kernels` yet. The kernels take a single
`Box` and about 50 `Array4`/scalar arguments (`continuity_PPM`), while `Model`
holds whole `MultiFab`s. `MOM_src_core` does not link `mom_kernels`.

### Details

The driver needs one layer between `Model` and the kernels, the analogue of
MOM6's `MOM_continuity.F90`. That layer is also the right home for the halo
exchanges, the configuration read (TB-006) and the optional debug
per-box stream sync (TB-007).

### Decision: build concretely, extract the convention later

CorAdCalc, hor_visc and vert_friction will each need a caller of the same
shape: a constructor that reads config and builds derived fields, and a
`step()` with `MFIter` at the root, northeast views and one kernel call per box.

- Build `Continuity` as a concrete class. No shared base class, template or
  framework for callers yet.
- After the **second** native caller exists, extract what the two have in common
  and write it down as a convention (in `lessons.md` or a design note). Refactor
  `Continuity` to match only if that is cheap.
- **Why:** two real callers are a better guide than a guessed abstraction, and
  the next ones already differ (hor_visc takes bundled structs of `Array4`;
  vertvisc returns per-box reductions that the caller must sum).

### Proposed fix

1. Add `src/core/MOM_continuity.{hpp,cpp}` with a `Continuity` class:
   - the constructor calls `read_continuity_ppm_params` (TB-006) once and
     stores the resulting config structs and stencil width;
   - `step(...)` takes typed fields from `Grid`, `VerticalGrid` and `State`.
   - *Proposed, not yet decided:* the optional arguments go in small
     caller-owned structs that mirror MOM6's own types, rather than a flat list
     of about 40 parameters. MOM6 calls `continuity()` several times per
     split-RK2 step with different sets of optional arguments: `uhbt`/`vhbt`,
     `visc_rem_u/v`, the `BT_cont` outputs (`FA_u_*`, `uBT_*`, `h_u`),
     `u_cor`/`v_cor`, `du_cor`. For example a `BTCont` (MultiFabs, the analogue
     of `BT_cont_type`) and a `ContinuityOptionals`, where an unallocated
     MultiFab means "absent". `step()` turns each into a view or `Array4{}`
     per box.
2. In `step`, loop with `MFIter` over the h field without tiling. Use
   `mfi.validbox()` as `bx0`, pull northeast views for every argument, and pass
   absent optional arguments as `Array4{}`.
3. Link `protoMOMxx::mom_kernels` into `MOM_src_core`.
4. Call it from the future `step_MOM`; `Model::initialize_dynamics` constructs it.
   - Halos: `step_MOM` exchanges halos (`pass_var`/`pass_vector`) at the same
     points MOM6's `step_MOM` does, and halo width stays 4 (`NIHALO`/`NJHALO`),
     which covers the continuity stencil (at most 3). That reproduces the inputs
     the kernels already see inside MOM6. Ghost values of `h`, `uh` and `vh`
     after the call are not meaningful. Exchange again if they are needed, as
     MOM6 does.

### Order of work (proposed)

1. TB-001 first. It is independent and cheap, and it means `step()` never has to
   pass `isd`/`ied`.
2. TB-002 (views) and TB-005 (grid fields) before any of this item.
3. The capture loader is the first real deliverable. It rebuilds native
   MultiFabs, in southwest storage, from the single-rank `ContinuityPPM`
   capture, so it also tests the TB-002 views.
4. TB-007's continuity fix before the multi-box GPU test means anything.

### Verification

- A unit test that runs `Continuity::step` on a small multi-box domain and
  matches the `ContinuityPPM` capture (via the TB-002 capture loader), compared
  on the compute domain.
- The same result with 1 and with several boxes per rank, and under `mpiexec`
  with 2 and 4 ranks.

---

## TB-005: Native `Grid` covers MOM6's `grid_core_type` and `grid_OBC_type`

- **Component:** protoMOMxx, `src/types/`, `src/initialization/`, `src/core/`
- **Status:** open (decided 2026-11-03; scope widened 2026-11-03)
- **Opened:** 2026-11-03
- **Related:** TB-003, TB-013, TB-014

### Summary

Originally this item covered only the fields `continuity_PPM` needs. The
CorAdCalc, hor_visc and vert_friction ports have since added
`turbotmp_mom_grid_c_types.h`. It contains C mirrors of MOM6's persistent grid
containers: `grid_core_C` (37 fields) and `grid_OBC_C` (4 fields), which the
bridges pass to the kernels. The native `Grid` has 26 fields. So the target is
now to cover both containers, which makes `Grid` a complete source for every
ported kernel, plus the `VerticalGrid` constants the kernels read.

All the missing fields are cheap to produce. Most are reciprocals or masked
products of fields `Grid` already has.

### Details

Missing from `GridFields`/`Grid`, with MOM6's final writer:

| Field | MOM6 source (final writer) | Definition |
|---|---|---|
| `IdxT`, `IdyT`, `IareaT` | `set_derived_metrics`, `MOM_grid.F90:439-441` | `Adcroft_reciprocal(dxT / dyT / areaT)`: `0` where the value is `0`, else `1/x` |
| `IdxCu`, `IdyCu`, `IdxCv`, `IdyCv` | `set_derived_metrics`, `MOM_grid.F90:447-456` | `Adcroft_reciprocal` of `dxCu`, `dyCu`, `dxCv`, `dyCv` |
| `IdxBu`, `IdyBu`, `IareaBu` | `set_derived_metrics`, `MOM_grid.F90:464-468` | `Adcroft_reciprocal` of `dxBu`, `dyBu`, `areaBu`; first `areaBu = dxBu*dyBu` where `areaBu <= 0` |
| `dy_Cu`, `dx_Cv` | `initialize_masks`, `MOM_grid_initialize.F90:1332, 1340` | `mask2dCu * dyCu`, `mask2dCv * dxCv` |
| `IareaCu`, `IareaCv` | `initialize_masks`, `MOM_grid_initialize.F90:1335, 1343` | `mask2dCu * Adcroft_reciprocal(areaCu)`, likewise for v |
| `Coriolis2Bu` | `MOM_fixed_initialization.F90:191` | `CoriolisBu**2` over the full data domain |
| `df_dx`, `df_dy` | `MOM_calculate_grad_Coriolis`, `MOM_shared_initialization.F90:114-122` | `IdxT * (f1 - f2)` from averages of the four surrounding `CoriolisBu`, on the compute domain, then `pass_vector(..., AGRID)` for the halos |
| `meanSL` | `MOM_fixed_initialization.F90:81-90`, transcribed with `+ Z_ref` | `0` (plus `Z_ref`) unless `READ_MEAN_SEA_LEVEL` |
| `OBCmaskCu`, `OBCmaskCv` | `initialize_masks`, `MOM_grid_initialize.F90:1272` | `= mask2dCu` / `mask2dCv`. With OBCs, `MOM_open_boundary` zeroes them at OBC faces |
| `IdxCu_OBCmask`, `IdyCv_OBCmask` | `set_derived_metrics`, `MOM_grid.F90:449, 457` | `OBCmaskCu * IdxCu`, `OBCmaskCv * IdyCv` |

Missing from `VerticalGrid`:

| Field | MOM6 source | Definition |
|---|---|---|
| `H_subroundoff` | `MOM_verticalGrid.F90:219` | `1e-20 * max(Angstrom_H, m_to_H * 1e-17)` |
| `dZ_subroundoff` | `MOM_verticalGrid.F90:220` | `1e-20 * max(Angstrom_Z, m_to_Z * 1e-17)` |
| `nkml` | `MOM.F90:3178-3180` | `0` unless the bulk mixed layer is used (needed by vert_friction's `vgrid_consts_C`, TB-014) |

Not grid fields:

| Field | MOM6 source | Definition |
|---|---|---|
| `por_face_areaU/V` | `MOM.F90:3228` | 3-D, allocated filled with `1.0`, even with porous barriers off |

Notes:

- **Reciprocals: use only the final form.** The Cartesian grid setup first sets
  `IareaT = I_dx * I_dy` (`MOM_grid_initialize.F90:476`), which can differ from
  `1/(dx*dy)` in the last bit. `set_derived_metrics` overwrites it when the
  dyn_horgrid is copied to the ocean grid. Reproduce only the
  `Adcroft_reciprocal` forms, over the full data domain (valid cells and halos),
  as MOM6 does. `set_derived_metrics` also clamps negative `dx*`/`dy*` to `0`
  first; reproduce that too.
- **`dy_Cu`/`dx_Cv` are already computed.** `MOM_grid_initialize.cpp:304`
  computes `dy_Cu = maskCu * dyCu` as a local to build `areaCu`, then
  discards it. The `dx_Cv` loop (`:316`) does the same. MOM6 notes that these "may be
  revised later" by channel-width edits (`reset_face_lengths`). double_gyre
  doesn't use those, so they are out of scope here.
- **The OBC masks are needed even without OBCs.** `gradKE` reads
  `IdxCu_OBCmask`/`IdyCv_OBCmask` unconditionally (`mom_coriolisadv.cpp:173,
  179`). Without OBCs they equal `mask2dC* * Id*C*`. Port the OBC modifications
  together with OBC support, not here.
- **`df_dx`/`df_dy` need a halo exchange at initialization.** That is the one
  field here that is not a pointwise function of existing fields over the data
  domain. Use `pass_vector` / `pass_vars` on cell-centred fields, matching
  MOM6's `AGRID` exchange.
- **Order matters.** In MOM6, `MOM_calculate_grad_Coriolis` reads `IdxT`/`IdyT`,
  so the reciprocals must be final before `df_dx`/`df_dy` are computed.
- **Porous barriers are not needed for double_gyre**
  (`USE_POROUS_BARRIER = False`, `examples/double_gyre/MOM_parameter_doc.all:47`).
  The kernel still reads `por_face_areaU/V` at every face, so something must be
  passed.
- **Line numbers** are from the pinned MOM6 submodule; check them against
  `dev/turbo-debug`.

### Proposed fix

1. Add a `set_derived_metrics` step to `make_grid` (`src/initialization`), run
   after the base metrics and masks are final. It computes all the reciprocals,
   `IareaCu`/`IareaCv`, `dy_Cu`/`dx_Cv`, the OBC masks and their products, and
   `Coriolis2Bu`, with MOM6's clamping and `Adcroft_reciprocal` semantics. This
   resolves the "defer" note in `MOM_fixed_initialization.cpp:87`.
2. Then compute `df_dx`/`df_dy` and exchange their halos. Set `meanSL`
   (`0` plus `Z_ref`; reading it from a file is out of scope).
3. Add every new field to `GridFields`, `Grid` (accessors), and `Grid`'s creation
   checks, so `Grid` covers `grid_core_C` and `grid_OBC_C` field for field.
4. Add `H_subroundoff()`, `dZ_subroundoff()` and `nkml()` to `VerticalGrid`.
5. `Continuity` (TB-003) allocates two 3-D face fields once, `setVal(1.0)`, and
   passes them as `por_face_areaU/V`. There is no porous-barrier struct. Add a
   real one only if porous barriers are ever enabled.

### Verification

- Every new grid field matches MOM6's double_gyre values bit for bit over the
  data domain, including halos. Use a captured grid or the `hchksum`/`qchksum`
  output MOM6 already produces in debug mode (`MOM_grid_initialize.F90:140-152`,
  `MOM_fixed_initialization.F90:196`).
- `H_subroundoff`, `dZ_subroundoff` and `nkml` match MOM6's values for
  double_gyre.
- A compile-time or unit check that `Grid` provides an accessor for every
  member of `grid_core_C` and `grid_OBC_C`, so the two can't drift apart
  silently.

---

## TB-006: Native configuration for the continuity kernels (`read_continuity_ppm_params`)

- **Component:** protoMOMxx, `src/mom_kernels/mom_continuity_ppm.hpp`,
  `src/core/MOM_continuity`; protoMOMxx `.claude/skills/generate_amrex_code/lessons.md`
- **Status:** open (decided 2026-11-03)
- **Opened:** 2026-11-03
- **Related:** TB-003

### Decision

The native driver uses the existing flat `bind(C)` mirror structs
`reconstruction_CS_C` and `transport_adjust_CS_C` (defined in
`mom_continuity_ppm.hpp`) as its configuration. This is permanent, not an
interim measure. No separate native C++ config type and conversion are added.

Rationale:

- **MOM6 already decouples its side.** `continuity_PPM_init` fills native
  Fortran types (`reconstruction_CS`, `transport_adjust_CS`), which are copied
  into the `bind(C)` mirrors only at the bridge call. The mirror is a wire
  format, and the Fortran internals can evolve freely.
- **On the C++ side the kernels are the consumer.** The struct is the kernels'
  configuration, not a foreign type. A second C++ type would duplicate the same
  eight fields and add a conversion.
- **`bind(C)` only requires that field order and types match the Fortran
  mirror.** That matters only when a field is added, which requires changing
  the kernels on both sides anyway.

### Proposed work

1. **Layout guards.** Next to each struct in `mom_continuity_ppm.hpp`, add
   `static_assert(std::is_standard_layout_v<T> && std::is_trivially_copyable_v<T>)`.
   This stops non-mirrorable members (`std::string`, `std::optional`, ...) from
   being added and silently breaking the Fortran mirror.
2. **Optional readability aliases.** For example,
   `namespace MOM { using ReconstructionConfig = ::reconstruction_CS_C; using TransportAdjustConfig = ::transport_adjust_CS_C; }`.
   This is cosmetic and has no ABI effect. (The structs currently sit at global
   scope, outside `namespace MOM`.)
3. **`read_continuity_ppm_params`.** This is the protoMOMxx analogue of MOM6's
   `continuity_PPM_init`, a free function in the style of `read_run_control`
   and `read_grid_extents`, so it can be unit-tested on its own:

   ```cpp
   struct ContinuityPPMConfig {
     reconstruction_CS_C   reconstruction;
     transport_adjust_CS_C transport_adjust;
     int                   stencil;
   };
   ContinuityPPMConfig read_continuity_ppm_params(RuntimeParams& params,
                                                  const VerticalGrid& vgrid);
   ```

   It is called once by `Continuity`'s constructor (TB-003). `stencil` feeds
   the kernel.

   Parameters to reproduce, in MOM6's order, with the same names, defaults,
   units and doc strings. Source: MOM6 `dev/turbo-debug`,
   `src/core/MOM_continuity_PPM.F90`, `continuity_PPM_init`.

   | Parameter | Field | Default / notes |
   |---|---|---|
   | `MONOTONIC_CONTINUITY` | `reconstruction.monotonic` | `false` |
   | `SIMPLE_2ND_PPM_CONTINUITY` | `reconstruction.simple_2nd` | `false` |
   | `UPWIND_1ST_CONTINUITY` | `reconstruction.upwind_1st` | `false` |
   | `ETA_TOLERANCE` | `transport_adjust.tol_eta` | `0.5 * NK * Angstrom`; units m, `scale = GV%m_to_H` in MOM6 |
   | `VELOCITY_TOLERANCE` | `transport_adjust.tol_vel` | `3.0e8`; units m s-1, `scale = US%m_s_to_L_T` in MOM6 |
   | `CONT_PPM_AGGRESS_ADJUST` | `transport_adjust.aggress_adjust` | `false` |
   | `CONT_PPM_VOLUME_BASED_CFL` | `transport_adjust.vol_CFL` | default = the value read for `CONT_PPM_AGGRESS_ADJUST` |
   | `CONTINUITY_CFL_LIMIT` | `transport_adjust.CFL_limit_adjust` | `0.5`; nondim |
   | `CONT_PPM_BETTER_ITER` | `transport_adjust.better_iter` | `true` |
   | `CONT_PPM_USE_VISC_REM_MAX` | `transport_adjust.use_visc_rem_max` | `true` |
   | `CONT_PPM_MARGINAL_FACE_AREAS` | `transport_adjust.marginal_faces` | `true` |
   | `CONT_USE_H_MARG_MIN` | (none) | `false`. Read so that it is logged. MOM6 sets `CS%h_marg_min` (`H_subroundoff` or 0) from it, but no continuity code in that file reads it. |

   The derived stencil is 3, or 2 if `simple_2nd`, or 1 if `upwind_1st`, as in
   MOM6.

   Notes:
   - **Order and dependent defaults matter.** The `MOM_parameters_doc.*` golden
     files compare the logged output.
   - **Unit scaling.** protoMOMxx has no unit scaling yet, so the MOM6
     `scale=` factors are 1 for now. Revisit `tol_eta` (thickness units [H])
     when non-Boussinesq mode and the units layer arrive.
   - **Re-check against MOM6 before implementing.** The table reflects
     `dev/turbo-debug` at `16501b711`.
   - **If MOM6 starts using `h_marg_min` in the continuity kernels,** add it to
     both `bind(C)` mirrors together. That is a normal mirrored change.
4. **Convention for later modules.** Record in `lessons.md` (and, if useful, a
   protoMOMxx design note):
   - each MOM6 `<module>_init` becomes a protoMOMxx `read_<module>_params()`
     returning the flat `bind(C)` structs that module's kernels take;
   - those structs are defined in the kernel header and used directly by native
     code;
   - anything that is not flat scalars (OBC, diagnostics handles, pointers,
     allocatable arrays) never goes into these structs.

### Verification

- A unit test for `read_continuity_ppm_params`:
  - defaults with an empty parameter file;
  - the dependent `vol_CFL` default with and without `CONT_PPM_AGGRESS_ADJUST`;
  - `tol_eta` for a given `NK`/`ANGSTROM`;
  - the stencil for each reconstruction option.
- The `double_gyre` system test's `MOM_parameters_doc.*` output for the
  continuity block matches MOM6's for the same `MOM_input`, once the
  `Continuity` constructor is wired into `Model`. Regenerate the golden files
  intentionally.
- The `static_assert`s compile. A deliberately added non-trivial member fails
  to compile.

---

## TB-007: Allocate kernel scratch from `The_Async_Arena()`

- **Component:** protoMOMxx, `src/mom_kernels/`; protoMOMxx
  `.claude/skills/generate_amrex_code/lessons.md`
- **Status:** open
- **Opened:** 2026-11-03
- **Related:** TB-003, TB-008, TB-011

### Summary

Several kernels allocate scratch `FArrayBox`/`IArrayBox` buffers as local
variables and free them at scope exit, while the kernels they launched may still
be running on the GPU. With `The_Arena()` (a host-side `CArena` pool) the memory
returns to the pool at once and can be handed out again.

This is safe on a single stream. It is a data race when several boxes run on
different GPU streams, which is what happens in an `MFIter` loop. That will be
the case for the native driver with more than one box per GPU, and it is
guaranteed with AMR (TB-011).

**Scope (updated 2026-11-03):** only `mom_continuity_ppm.cpp` is affected. The
modules added since (CorAdCalc, hor_visc, vert_friction) already allocate all
their scratch from `The_Async_Arena()`: 31, 54 and 26 sites respectively, 111 in
all. `mom_interface_heights.cpp` allocates no scratch. What remains is fixing
continuity and writing the convention down in `lessons.md`, which still has no
rule for it. The newer ports followed the convention without one.

### Details

- **Allocation sites** (28) in `src/mom_kernels/mom_continuity_ppm.cpp`:
  - `PPM_reconstruction_y/x`: `slp_fab` (lines ~105, ~260). These use the
    default arena; there is no explicit argument.
  - `continuity_PPM`: `h_W/h_E/h_S/h_N` (~446-490). Each is sized to the whole
    3-D `h` fab.
  - `continuity_PPM_2d_fluxes`: `h_W/h_E/h_S/h_N` (~541-550).
  - `zonal_mass_flux`: 7 `FArrayBox` + 1 `IArrayBox` (~651-658).
  - `meridional_mass_flux`: 7 `FArrayBox` + 1 `IArrayBox` (~981-988).
- **Why the bridge path is safe today.** The MOM6 bridge runs everything on one
  stream. A later kernel that reuses freed memory is queued behind the kernels
  that used it before, so stream order prevents the race. (The bridge's
  `Gpu::synchronize()` is not what makes it safe.)
- **Why a native `MFIter` loop is unsafe.** AMReX rotates boxes across
  `Gpu::numGpuStreams()` streams. Memory freed by box 0's call can be handed to
  box 1's call, on another stream, while box 0's kernels are still reading it.
- **CPU builds** are unaffected (no streams).
- **Allocation cost is minor.** `CArena` allocation is host-side pool
  bookkeeping, not `cudaMalloc`. The concerns are correctness and peak memory,
  not allocation churn.

### Proposed fix

1. Allocate every kernel scratch buffer from `amrex::The_Async_Arena()`:
   - `FArrayBox x(bx, 1, amrex::The_Arena())` becomes
     `FArrayBox x(bx, 1, amrex::The_Async_Arena())`, and likewise for
     `IArrayBox`;
   - give the two `slp_fab` allocations an explicit `The_Async_Arena()`.

   The async arena frees in stream order: memory is released only after the
   kernels already queued on that stream have finished.

   This is a one-token change per site. It changes no kernel signatures, so the
   bridge, the MOM6 Fortran side and the capture fixtures are untouched. It
   keeps the kernels a mechanical mirror of the Fortran routines, which
   themselves allocate scratch internally (`allocView`/`free`).

   On CPU builds `The_Async_Arena()` is equivalent to `The_Arena()`.
2. Confirm the behaviour of `The_Async_Arena()` for the pinned AMReX version on
   every GPU backend in use (CUDA; HIP/SYCL if targeted). On backends without a
   stream-ordered allocator it falls back to another mechanism. Record the
   result in this item.
3. Add a rule to `lessons.md` (§4 kernel conventions and §7 pitfalls): "scratch
   buffers allocated inside a kernel use `amrex::The_Async_Arena()`; never rely
   on `The_Arena()` or the default arena for temporaries". This keeps the next
   mechanically ported kernel from reintroducing the race. Mirror the rule in
   the skill's hard rules. Cite the CorAdCalc, hor_visc and vert_friction ports
   as the reference examples, and continuity as the one that got it wrong.
   *Completed; see `CHANGELOG.md`.*
4. In `Continuity::step` (TB-003), add an optional per-box
   `amrex::Gpu::streamSynchronize()` behind a debug flag. Use it only to bisect
   suspected stream races; the fix does not depend on it.

### Peak memory

With a stream-ordered free, each box still in flight holds its scratch until
its stream drains. Peak scratch memory per rank is therefore about
`min(boxes per rank, Gpu::numGpuStreams())` x per-box scratch.

For continuity, the per-box scratch is dominated by `continuity_PPM`'s four
whole-fab 3-D buffers (`h_W/h_E/h_S/h_N`, all alive together in either sweep
order). In the other modules, `horizontal_viscosity_tr` holds about 45
block-sized scratch arrays per k-block (`nkblock` layers each), so `nkblock` is
the knob there. Record these in the memory budget when sizing boxes. If they
become a constraint, consider the alternatives below.

### Alternatives considered (not chosen)

- **Per-box `streamSynchronize()` in the caller.** Correct, with no kernel
  changes, but it serializes the box loop and gives up cross-box GPU
  concurrency, which matters with AMR's many boxes. Kept only as the debug
  switch in step 4.
- **`Elixir` per scratch buffer.** The same guarantee as the async arena, via a
  host callback, but it needs an extra line per buffer. Use it only if the
  async arena is unsuitable on some backend.
- **A persistent workspace passed into the kernels.** Zero allocations and a
  bounded peak, but it changes every kernel signature and departs from the
  mechanical port. Revisit only if profiling shows allocation cost or peak
  memory matters, together with TB-008.
- **Removing scratch by fusing kernels (TB-008).** It would eliminate the
  `*_mass_flux` buffers but not `h_W/h_E/h_S/h_N`. It is a structural change,
  justified only by profiling.

### Verification

- `test_mom` capture-replay tests and a MOM6 AMReX-path run still match bit for
  bit. Only the allocation changes, not the arithmetic.
- **Race test.** Run the TB-003 native continuity test on GPU with several boxes
  per GPU (`DomainSpec::n_boxes`) and more than one stream, under
  `compute-sanitizer --tool racecheck` (and/or `--tool memcheck`), several times:
  - before the change, it should report the hazard, or produce results that
    vary run to run or differ from the CPU result;
  - after the change, it should be clean, with results bit-identical to the CPU
    run.
- `grep -n "The_Arena()\|FArrayBox [a-z_]*(.*, 1);" src/mom_kernels/*.cpp`
  shows no scratch allocations outside `The_Async_Arena()`. (The bridge helper's
  `A4Box` buffers are out of scope; they live on the single-stream bridge path.)

---

## TB-008: Reduce kernel launches in the continuity orchestrators

- **Component:** protoMOMxx, `src/mom_kernels/`
- **Status:** deferred (2026-11-03)
- **Opened:** 2026-11-03
- **Related:** TB-007, TB-011; `submodules/protoMOMxx/docs/design/answers_not_structure.md`
- **Tracked in:** `submodules/protoMOMxx/.claude/skills/generate_amrex_code/lessons.md` §9

### Summary

`zonal_mass_flux`/`meridional_mass_flux` call `*_flux_adjust`,
`set_*_BT_cont` and `*_flux_thickness` as separate kernel launches over
locally allocated scratch. Fusing them into one launch per orchestrator would
remove launches and most of the scratch (see TB-007).

### Why deferred

- **Rough size:** about 8 to 10 `ParallelFor` launches per direction, so about
  20 per `continuity_PPM` call and about 60 per split-RK2 step. At about 5 µs per
  launch that is about 0.3 ms per step, which is noise for large boxes on a GPU.
  It matters only for many small boxes per GPU, which AMR could produce
  (TB-011).
- **The likelier real cost is memory traffic.** Each launch writes scratch
  arrays that the next one reads back, in memory-bound kernels. This is
  unmeasured.
- Without a profile, the refactoring cost is not justified.

### Trigger to reopen

A GPU profile (e.g. Nsight Systems) of native double_gyre continuity that shows
launch gaps or scratch memory traffic as a significant share of continuity
time. Include the small-box case if AMR is in use by then.

### Design rule when reopened

Fuse through the `*_point` tier rather than by rewriting kernel bodies:

1. Move the per-`(i,j)` body of `*_flux_adjust`, `set_*_BT_cont` and
   `*_flux_thickness` into `*_point` device functions.
2. Keep the existing box-level kernels as thin `ParallelFor(bx2d, ..._point)`
   wrappers. They stay 1:1 with the Fortran subroutines, remain callable from
   MOM6 through the bridge, and keep their own capture tests.
3. The fused orchestrator calls the same `*_point` functions inside a single
   `ParallelFor`.

Both paths then share one body, so bit-for-bit results follow and nothing is
duplicated.

This rule is a **preference, not a requirement**
(`submodules/protoMOMxx/docs/design/answers_not_structure.md`). Keep it while
it is cheap, because the leaf capture tests are valuable. If profiling shows
`*_point` fusion is not enough, the fused orchestrator may restructure further,
for example with a different loop nesting to relieve register pressure. The
conditions are that the arithmetic at each point and the reduction order of the
Newton iteration stay unchanged. Validation then moves from leaf capture replay
to capture replay of `continuity_PPM`, whose arguments still match.

**Watch item:** `*_flux_adjust` keeps per-column state across `k` inside each
Newton iteration. Fusing it means recomputing that state or holding
`nz`-length per-thread data, which risks register spill. Check this in the
profile before and after. If it does spill, it is a reason to restructure under
the principle above, not a blocker.

### Verification when reopened

- Capture-replay tests still match bit for bit: for `continuity_PPM` always,
  and for the leaf kernels as long as the `*_point` wrappers are kept.
- The profiler shows fewer launches and less scratch traffic, and continuity
  time does not regress.

---

## TB-009: Parallelism within a rank on CPU

- **Component:** protoMOMxx, `src/core/MOM_continuity`, TIM `Domain`
- **Status:** deferred (2026-11-03)
- **Opened:** 2026-11-03
- **Related:** TB-007, TB-011

### Summary

The kernels work on whole boxes and grow their iteration boxes internally, so
`MFIter` tiling cannot be used with them. With one box per rank, there is no
OpenMP parallelism inside a rank on CPU builds.

### Why deferred

- CPU runs use flat MPI, one rank per core and one box per rank. That is how
  MOM6 itself runs in production, including in CESM, so nothing is missing.
  The node is fully used through ranks rather than threads.
- On GPU, `ParallelFor` already spreads each box across the device. OpenMP plays
  no role there.
- Hybrid MPI+OpenMP is an optimisation (memory and halo volume at very high
  core counts), not a capability gap. There is no current target that needs it.

### If reopened

1. **Preferred:** OpenMP over boxes. Wrap the subtree-root `MFIter`
   (non-tiled) in `#pragma omp parallel`, one box per thread. This needs no
   kernel changes. It requires TB-007 (per-call scratch) and several boxes per
   rank, which AMR (TB-011) brings anyway. Extra halo cells per box are the
   cost.
2. **Not without a measured need:** tile-aware kernels that take a tile box plus
   the enclosing valid box. This is the only option that would need real
   design work.

Verification when reopened: a strong-scaling test on one CPU node, with the
native driver at `OMP_NUM_THREADS` 1 to N, compared with flat MPI on the same
cores.

---

## TB-010: Remove the identity "transpose" in the bridge helper and fix its documentation

- **Component:** protoMOMxx, `src/mom_kernels/turbotmp/`,
  `.claude/skills/generate_amrex_code/`
- **Status:** open (low priority, 2026-11-03)
- **Opened:** 2026-11-03

### Summary

`turbotmp_helper` describes the kernel-facing buffer as "C order" and
`copy_FortranHost_to_array4`/`copy_array4_to_FortranHost` as a "Fortran to C
transpose". `amrex::Array4` is already column-major (i fastest, offset
`i + jstride*j + kstride*k + nstride*n`, see `AMReX_Array4.H`), the same as
Fortran. The index formula in the "transpose" kernel is identical on both
sides, so it is an identity copy.

### Details

For every array, on every bridge call, this costs:
- a second device buffer (`data_f`);
- an extra kernel launch and a stream sync, in each direction.

This affects only the MOM6-to-bridge path, not the native driver. That path is
used for validation only (capture runs and bit-for-bit checks), so the cost does
not matter for production. Hence low priority, except for the documentation
correction below. The wrong
description is repeated in `turbotmp_helper.hpp` (lines 20-21, 54, 73-74, 98)
and in `lessons.md` §2.

The bridge uses strict copy-in/copy-out (`turbotmp_mom_continuity_ppm_bridge.cpp`).
Every array is copied in, including pure outputs such as `FA_u_*` and `h_u`, and
every output is copied back in full. Wrapping the Fortran pointer directly on CPU
builds therefore gives the same results. The one exception would be Fortran
passing the same array to two dummy arguments when one of them is modified,
which Fortran's aliasing rules already forbid. `continuity_PPM`'s callers pass
distinct arrays.

### Proposed fix

**Do soon, independent of priority:** correct the "C order" / "Fortran to C
transpose" comments in `turbotmp_helper.hpp` (lines 20-21, 54, 73-74, 98).
The matching correction to the skill (`lessons.md`, `SKILL.md`) is done; see
`CHANGELOG.md`.

**Low priority:**

1. Drop `data_f` and the transpose kernels, and keep one buffer:
   - GPU builds: one `Gpu::copy` host to device and back.
   - CPU builds: wrap the Fortran host pointer directly in the `Array4`, with no
     copy and no allocation (`make_array4` already assumes the descriptor's data
     is contiguous).
2. The helper and the shared C types (`RealArray_C` etc.) are a protoMOMxx and
   TIM interface: check the skill's "do not modify the `turbotmp_helper` core
   API" rule. The fix changes the implementation, not the API.

### Verification

- All `test_mom` tests, and a MOM6 run with the AMReX path, still match bit for bit.
- Bridge time per call drops (profile one `continuity_PPM` call before and after).

---

## TB-011: AMR readiness for the protoMOMxx driver

- **Component:** protoMOMxx (`src/core/`, `src/types/`, `src/initialization/`,
  `config_src/infra/`), TIM (`tim/cpp/core/tim_domain.*`)
- **Status:** open (design guardrails; no implementation scheduled)
- **Opened:** 2026-11-03
- **Related:** TB-001, TB-003, TB-007, TB-009

### Summary

The plan is to use AMReX mesh refinement eventually. With AMR, multiple boxes
per rank are unavoidable:

- Each refined level is an irregular union of patches. It is split under
  `max_grid_size`/`blocking_factor` and redistributed at every regrid.
- Level 0 is often split too, for load balance.

The decision on box counts and `MFIter` loop placement is deferred until whole-application
performance can be measured. This item records what to avoid building in the
meantime, so that AMR is not blocked later.

### Background: loop placement

The current direction is to place `MFIter` loops at the root of each
communication-free subtree (e.g. around `continuity_PPM`). Kernels stay at the
box level (`Box` + `Array4`). This is the common AMReX application pattern
(e.g. Castro, ERF), and it works unchanged on every AMR level:

- Halo fills at coarse-fine boundaries come from `FillPatch` instead of `pass_var`.
- Face fluxes (`uh`/`vh`) feed a `FluxRegister` per box, inside the same loop,
  for refluxing.

Keeping kernels box-level keeps the loop placement movable later. Changing
kernels to take `MultiFab`s would break MOM6 callability and is the costly
direction to undo.

### Guardrails

1. **Don't assume one box per rank anywhere.** Examples to avoid:
   - halo widths or index ranges taken from "the" box;
   - Fortran-style data-domain arguments such as `isd`/`ied` (TB-001);
   - reductions or diagnostics that assume a single fab per rank.

   Iteration ranges come from the `Box` passed in. Halo widths come from each
   field's `nGrowVect()`.
2. **Make kernel scratch memory safe for multiple boxes (TB-007).** AMR
   guarantees the multi-box case, so the scratch-memory race must be resolved
   before any refined level runs on GPU. The chosen fix is to allocate kernel
   scratch from `The_Async_Arena()`.
3. **State the halo contract as "ghost cells valid to width N", not "`pass_var`
   was called" (TB-003 step 4).**
   - The communication-free subtree only needs valid ghost cells out to the
     stencil width before it runs.
   - On level 0 (and away from coarse-fine boundaries) they are filled by
     `pass_var`/`pass_vector`. At coarse-fine boundaries they are filled by
     `FillPatch` (space and possibly time interpolation from the coarser level).
   - Assertions and docs in `Continuity` should check ghost width and require
     valid ghosts. They should not name the fill mechanism.
4. **Plan for `Domain` and `Grid` to be per level.**
   - Today there is one `MOM::Domain` (one `TIM::Domain`, one 2-D `Geometry`)
     and one `Grid` of metrics. With AMR, each level needs its own geometry,
     `BoxArray`/`DistributionMapping`, metrics (`Grid`), masks, and `dt` when
     subcycling.
   - Avoid code that treats `Model::domain()`/`Model::grid()` as global
     singletons in kernel-facing paths. Pass them in explicitly, as the
     initialization functions already do.
   - **Known hard blocker in TIM.** `TIM::Domain`'s constructor aborts unless
     every box maps to a distinct tile and the boxes form a complete
     rectangular tile grid (`layout_nx * layout_ny == n_boxes`;
     `tim_domain.cpp`, "does not form a complete rectangular tile grid"). The
     check exists for the I/O decomposition model (`TIM::IoDecomp`). A
     refined-level `BoxArray` will not satisfy it.
   - Refined levels therefore need either a separate level type, or a
     `Domain` mode without the tile-grid invariant, with I/O handled by
     another decomposition description. Raise this with TIM before AMR work
     starts.

### Out of scope here (design topic, not a backlog item)

How MOM6's split barotropic/baroclinic time stepping interacts with
subcycling and refluxing (the `uhbt`/`BT_cont` machinery in the continuity
kernels, barotropic substeps across levels, and conservation of the
barotropic transport). This deserves its own design discussion before any
AMR implementation.

### Verification (when AMR work starts)

- A two-level test (one refined patch) on the double-gyre configuration.
  Total volume is conserved to round-off with refluxing on, and the result is
  insensitive to `max_grid_size`, i.e. to the box count.
- The same test under `mpiexec` with several ranks, and on GPU with several boxes per GPU.

---

## TB-012: Native configuration for the CorAdCalc kernels (`read_coriolisadv_params`)

- **Component:** protoMOMxx, `src/mom_kernels/mom_coriolisadv.hpp`, `src/core/`
- **Status:** open
- **Opened:** 2026-11-03
- **Related:** TB-006 (sets the convention)

### Summary

The CorAdCalc kernels take `CorAdv_opts_CS_C`, which contains
`Coriolis_scheme_CS_C`. Nothing on the native side fills them. MOM6 reads them
in `CoriolisAdv_init` (`src/core/MOM_CoriolisAdv.F90`).

### Details

This is the smallest of the three readers: parameters only, with no derived
fields or file reads. The parameters, with the same names, defaults, units and
doc strings as MOM6:

`CORIOLIS_SCHEME`, `CORIOLIS_EN_DIS`, `KE_SCHEME`, `KE_USE_LIMITER`,
`PV_ADV_SCHEME`, `CORIOLIS_ADV_NKBLOCK`, `CORIOLIS_BLEND_F_EFF_MAX`,
`CORIOLIS_BLEND_WT_LIN`, `NOSLIP`, `BOUND_CORIOLIS`, `WENO_VELOCITY_SMOOTH`.

- `CORIOLIS_SCHEME`, `KE_SCHEME` and `PV_ADV_SCHEME` are strings in the
  parameter file. They map to the integer codes the struct holds, and the
  mapping must match the Fortran module's named constants exactly.
- `BOUND_CORIOLIS` and `NOSLIP` are also read by `hor_visc_init` (TB-013).
  Each reader logs them the way MOM6 does, so `MOM_parameter_doc` stays
  identical.
- This list was extracted from the pinned MOM6 submodule. Check it against
  `dev/turbo-debug`, which defines the `bind(C)` mirrors.

### Proposed fix

Follow TB-006: keep the `_C` structs as the native config, add `static_assert`
layout guards, and add
`CorAdvConfig read_coriolisadv_params(RuntimeParams&, ...)`, called once by the
native CorAdCalc caller's constructor.

### Verification

- Unit test of the reader against default and non-default parameter files.
- The double_gyre `MOM_parameter_doc.*` golden files are unchanged.

---

## TB-013: Native configuration for the horizontal viscosity kernels (`hor_visc_init` port)

- **Component:** protoMOMxx, `src/mom_kernels/mom_hor_visc.hpp`, `src/core/`
- **Status:** open
- **Opened:** 2026-11-03
- **Related:** TB-005, TB-006 (sets the convention), TB-012

### Summary

`horizontal_viscosity_tr` takes `hv_opts_CS_C` (59 scalar fields) and
`hv_metrics_dev` (44 `Array4` coefficient fields). MOM6 produces both in
`hor_visc_init` (`src/parameterizations/lateral/MOM_hor_visc.F90`, about 1000
lines). This is a reader plus a port of the derived-field computation, not just
a parameter reader.

### Details

- **Parameters** (about 70 names):
  - which schemes run: `LAPLACIAN`, `BIHARMONIC`, `SMAGORINSKY_KH`/`_AH`,
    `LEITH_KH`/`_AH`, `MODIFIED_LEITH`, `USE_LEITHY`, `SMOOTH_AH`,
    `USE_QG_LEITH_VISC`, `USE_GME`, `ANISOTROPIC_VISCOSITY`,
    `ADD_LES_VISCOSITY`;
  - coefficients and bounds: `KH`, `AH`, `KH_VEL_SCALE`, `AH_VEL_SCALE`,
    `AH_TIME_SCALE`, `SMAG_LAP_CONST`, `SMAG_BI_CONST`, `LEITH_*_CONST`,
    `KH_BG_MIN`, `KH_SIN_LAT`, `KH_PWR_OF_SINE`, `BOUND_KH`, `BOUND_AH`,
    `RE_AH`, `HORVISC_BOUND_COEF`, `MAXVEL`, `KILL_SWITCH_*`;
  - bug and answer-date switches: `FRICTWORK_BUG`, `KH_BG_2D_BUG`,
    `USE_CONT_THICKNESS_BUG`, `OBC_SPECIFIED_STRAIN_BUG`,
    `HOR_VISC_ANSWER_DATE`, `DEFAULT_ANSWER_DATE`, `ENABLE_BUGS_BY_DEFAULT`;
  - `HORVISC_NKBLOCK`, `USE_MEKE`, `RES_SCALE_MEKE_VISC`, and `DT`, which is
    read here too.
- **Derived 2-D fields (`hv_metrics_dev`):** `Kh_bg_xx`, `Ah_bg_xx`,
  `Laplac2_const_xx`, `Biharm_const_xx`, `Kh_Max_xx`, `grid_sp_h2`,
  `n1n2_h`, and the rest, at h and q points. They are computed from the grid,
  for example `Kh_bg_xx = max(Kh, Kh_vel_scale*sqrt(grid_sp_h2))`, with an
  optional 2-D background read from `KH_BG_2D_FILENAME`. They need the full set
  of grid metrics (TB-005, widened) and must match MOM6 bit for bit, including
  in halos.
- **`do_*` diagnostic flags** (`do_FrictWork`, `do_Ah_h`, …): in MOM6 these come
  from diagnostic registration, not parameters. Until the native driver has
  diagnostics, set them all false.
- **Scope for double_gyre:** Laplacian only (`LAPLACIAN = True`,
  `BIHARMONIC = False`, no GME or Leith+E). Port the full parameter set so the
  parameter docs match, but derived fields only for the enabled schemes. Abort
  with a clear message when a scheme whose derived fields aren't ported yet is
  switched on.
- Check the list against `dev/turbo-debug`.

### Proposed fix

1. `HorViscConfig read_hor_visc_params(RuntimeParams&, ...)`, filling
   `hv_opts_CS_C`, following TB-006.
2. `make_hor_visc_metrics(const HorViscConfig&, const Grid&)`, which owns the
   `hv_metrics_dev` MultiFabs, plus a per-`MFIter` builder that returns the
   bundle of northeast views (TB-002).
3. Both are called once from the native hor_visc caller's constructor.

### Verification

- Reader unit tests and unchanged double_gyre `MOM_parameter_doc.*` golden
  files.
- The derived fields match MOM6's double_gyre values bit for bit, over the
  data domain including halos.

---

## TB-014: Native configuration for the vertical friction kernels (`vertvisc_init` port)

- **Component:** protoMOMxx, `src/mom_kernels/mom_vert_friction.hpp`, `src/core/`
- **Status:** open
- **Opened:** 2026-11-03
- **Related:** TB-005, TB-006 (sets the convention)

### Summary

The vertical friction kernels take `vertvisc_opts_CS_C` and `coef_opts_CS`
(which contains `coupling_CS_C` and the GL90 scalars). MOM6 reads them in
`vertvisc_init`
(`src/parameterizations/vertical/MOM_vert_friction.F90`).

### Details

- **Parameters:** `DIRECT_STRESS`, `HMIX_STRESS`, `HMIX_FIXED`,
  `STOKES_MIXING_COMBINED`, `VEL_UNDERFLOW`, `CFL_TRUNCATE`, `CFL_REPORT`,
  `CFL_TRUNCATE_RAMP_TIME`, `CFL_TRUNCATE_START`, `U_TRUNC_FILE`,
  `V_TRUNC_FILE`, `HBBL`, `HBBL_GL90`, `HARMONIC_VISC`, `HARMONIC_BL_SCALE`,
  `KV`, `KVML`, `KVBBL`, `KV_EXTRA_BBL`, `KV_ML_INVZ2`, `DYNAMIC_VISCOUS_ML`,
  `FIXED_DEPTH_LOTW_ML`, `LOTW_VISCOUS_ML_FLOOR`, `BOTTOMDRAGLAW`,
  `USE_GL90_IN_SSW`, `USE_GL90_N2`, `KD_GL90`, `alpha_GL90`, `READ_KD_GL90`,
  `KD_GL90_FILE`, `KD_GL90_VARIABLE`, `VERT_FRICTION_ANSWER_DATE`,
  `DEFAULT_ANSWER_DATE`, `DEBUG`.
- **Time-dependent value:** with `CFL_TRUNCATE_RAMP_TIME > 0`, MOM6 ramps
  `CFL_trunc` from `CFL_TRUNCATE_START` over time (`updateCFLtruncationValue`).
  So `CFL_trunc` in the struct is state that the caller updates each step, not
  a constant.
- **Truncation reporting:** `do_report_u/v` follow from
  `U_TRUNC_FILE`/`V_TRUNC_FILE`. The report files are host-side I/O. Set the
  flags false until the native driver writes these files.
- **GL90:** `kappa_gl90_2d` (from `KD_GL90_FILE`) reaches the kernel as an
  `Array4`. That array needs a file read; leave it unallocated unless
  `READ_KD_GL90`.
- **`do_GLwork`, `do_du_dt_visc_gl90`, `do_dv_dt_visc_gl90`** come from
  diagnostic registration. Set them false, as in TB-013.
- Some parameters (`HBBL`, `KV`, `BOTTOMDRAGLAW`, …) are also read by
  `set_visc_init`. Log them the way MOM6 does.
- **`vgrid_consts_C` is not part of this reader.** Its fields (`ke`,
  `Boussinesq`, `nkml`, `dZ_subroundoff`, `H_subroundoff`, the unit
  conversions `H_to_m`, `m_to_H`, `RZ_to_H`, `Z_to_H`, `T_to_s`, `H_to_RZ`,
  `m_s_to_L_T`, and `Angstrom_H`) come from `VerticalGrid` and the unit scales.
  Build it from `VerticalGrid`; TB-005 adds the missing `H_subroundoff`,
  `dZ_subroundoff` and `nkml`.
- Check the list against `dev/turbo-debug`.

### Proposed fix

Follow TB-006: `VertViscConfig read_vertvisc_params(RuntimeParams&, ...)` fills
`vertvisc_opts_CS_C` and `coef_opts_CS`, and is called once
by the native vertvisc caller's constructor. The caller also owns the
`CFL_trunc` ramp update.

### Verification

- Reader unit tests and unchanged double_gyre `MOM_parameter_doc.*` golden
  files.
- A ramp test: `CFL_trunc` matches MOM6's sequence over the first steps when
  `CFL_TRUNCATE_RAMP_TIME > 0`.

---

## TB-015: Asymmetric corner term in MOM6's `smooth_x9_h` / `smooth_x9_uv` stencil

- **Component:** MOM6 (`src/parameterizations/lateral/MOM_hor_visc.F90`), then
  protoMOMxx (`src/mom_kernels/mom_hor_visc.cpp`); possibly upstream NOAA-GFDL/MOM6
- **Status:** open
- **Opened:** 2026-11-03
- **Related:** TB-016 (the `pass_var` split in `horizontal_viscosity_tr`)

### Summary

The 9-point smoothing filter is meant to be rotationally symmetric, but one of
its four corner terms pairs the mask at one corner with the field value at a
different corner:

```fortran
G%mask2dT(i+1,j-1) * fh_prev(i-1,j-1)     ! should be fh_prev(i+1,j-1)
```

The southwest value is counted twice and the southeast value is never used.

### Details

- The same typo appears in all three variants: `smooth_x9_h`
  (`MOM_hor_visc.F90:3965`, pinned submodule) and both the u and v parts of
  `smooth_x9_uv` (`fu_prev(I-1,j-1)`, `fv_prev(i-1,J-1)`).
- The C++ port reproduces it faithfully (`mom_hor_visc.cpp:72` in
  `smooth_x9_pass`), as it must for bit-for-bit agreement.
- Callers:
  - `horizontal_viscosity` (Leith+E with `SMOOTH_AH`, on `m_leithy` and `Ah_sq`);
  - the `u_smooth`/`v_smooth` path (`MOM_hor_visc.F90:592`);
  - `MOM_stochastics.F90:235` (`taperCu`/`taperCv`).

  So the effect is not limited to Leith+E.
- This is not related to TURBO-ESM/MOM6 PR #75, which fixes halo extents in
  `hor_visc_strain`, not this stencil.
- The bug changes answers. It breaks rotational symmetry, so MOM6's rotation
  tests should expose it in any configuration that runs these paths.

### Proposed fix

1. Confirm the bug is present upstream (NOAA-GFDL/MOM6 `dev/gfdl`) and report it
   there, since the code isn't TURBO-specific.
2. Fix it in MOM6 behind the usual answer-changing guard: a bug flag (e.g.
   `SMOOTH_X9_STENCIL_BUG`, defaulting to the old behaviour) or an answer date.
   Follow upstream's choice if they fix it first.
3. Mirror the flag in the C++ (`smooth_x9_pass`, a template parameter or a
   run-time `bool` tested outside the `ParallelFor`) and in `hv_opts_CS_C`.
   This is a MOM6 Fortran plus protoMOMxx pair, like TB-001.

### Verification

- With the bug flag set to the old behaviour, all existing captures and
  regression answers are bit for bit unchanged.
- With the fix, a rotated-grid test (MOM6 `ROTATE_INDEX` / rotation test) of
  a configuration using these smoothers gives rotationally consistent results.
- Capture replay of the fixed `smooth_x9_h`/`smooth_x9_uv` matches bit for bit.

---

## TB-016: Leith+E smoothing in `horizontal_viscosity_tr` without mid-computation halo exchanges

- **Component:** protoMOMxx (`src/mom_kernels/mom_hor_visc.cpp`, the future native
  hor_visc caller, grid construction)
- **Status:** deferred (2026-11-03)
- **Opened:** 2026-11-03
- **Related:** TB-011, TB-013, TB-015; TURBO-ESM/MOM6 PR #75;
  `submodules/protoMOMxx/docs/design/answers_not_structure.md`

### Summary

With `BIHARMONIC && USE_LEITHY && SMOOTH_AH`, MOM6 exchanges halos four times per
layer inside `horizontal_viscosity`:
`pass_var(m_leithy, halo=2)`, `smooth_x9_h`, `pass_var(m_leithy)`, and the same
for `Ah_sq` (`MOM_hor_visc.F90:2605-2630`). The C++ port aborts at both sites
(`mom_hor_visc.cpp:3451`, `:3475`). A kernel called per box cannot exchange
halos in the middle of a computation.

### Why deferred

Nothing needs Leith+E with smoothing yet. double_gyre has `BIHARMONIC = False`
and `USE_LEITHY = False`, and the abort prevents silent misuse.

### Decision

Use a wide-halo, communication-free kernel on the AMReX side. Leave MOM6's
Fortran unchanged. This applies the "answers, not structure" principle
(`answers_not_structure.md`).

- **Reach:** each `smooth_x9_h` consumes 2 halo points. Removing both pairs of
  exchanges means computing raw `Ah_sq` to the domain plus 3, raw `m_leithy` to
  the domain plus 5, and the vorticity chain to the domain plus 7. So `u`, `v`
  and `h` (and the grid metrics) must be valid to about 8, compared with 3 to 4
  today.
- **Locality:** in AMReX, ghost width is per MultiFab. The model halo stays 4.
  The native hor_visc caller copies `u`, `v` and `h` into temporary MultiFabs with
  about 8 ghosts and exchanges them once before the `MFIter` loop. Static 2-D grid
  metrics are built with 8 ghosts. The communication moves to the root of the
  subtree; the kernel keeps its structure, k-block loop and signature.
- **Code change inside the kernel:** only the option-dependent box extents for the
  Leith+E chain, under `use_Leithy && smooth_Ah`, following the existing
  option-dependent `kh_lo` / `is_vort` logic. The two aborts and their
  `pass_var` comments go away. Add an assertion that the inputs carry enough ghost
  cells; on the MOM6 bridge path at halo 4 this keeps aborting for this option.
- **Cost:** only in runs that enable the option. It is the temporary wide copies
  and about 30% to 65% more work in the vorticity chain, depending on box size.

### Rejected alternatives

1. **Split the routine into phases at each exchange.** That moves the k-block
   loop and 45 block-sized scratch arrays to the caller, and lets one option
   dictate the structure of the whole subroutine.
2. **A halo-exchange callback passed into the kernel.** Exchanges are collective
   over all boxes, so this works only with exactly one box per rank, which
   conflicts with TB-011.
3. **Widening in MOM6.** MOM6's halo is global (`NIHALO`), so every array would
   pay for it.

### Before implementing

- Re-derive the reach numbers after TURBO-ESM/MOM6 PR #75 merges. It changes
  the Leith-dependent `bxHtens`/`bxVort` extents in `hor_visc_strain`. Port its
  box changes to the C++ first.
- Check physical-edge behaviour. MOM6 zeroes `m_leithy`/`Ah_sq` "to initialize
  domain edge halo values" and `pass_var` leaves out-of-domain halos alone.
  Computing into those cells must give the same masked result on the compute
  domain.
- Decide whether TB-015 (the `smooth_x9` stencil bug) is fixed first; it changes
  the answers this path is validated against.

### Verification

- Run MOM6 with `NIHALO = NJHALO = 8` and `USE_LEITHY`/`SMOOTH_AH` on. The
  AMReX path through the bridge matches plain Fortran bit for bit on the compute
  domain, including with non-periodic boundaries.
- The same native configuration gives identical results with 1 and several
  boxes per rank, and with several ranks.
