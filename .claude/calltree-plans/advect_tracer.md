# Call-tree conversion plan: `advect_tracer`

Promoted mid-survey from a candidate descendant of `step_MOM_tracer_dyn` to its own entry point
(user decision): `advect_tracer` is `public` in `MOM_tracer_advect` and called from 4 places
across 2 files (`MOM.F90`'s `step_MOM_tracer_dyn` and `step_offline`, plus
`MOM_offline_main.F90`'s `offline_advection_ale`/`offline_advection_layer`) — a stronger
externally-fixed contract than `step_MOM_tracer_dyn` itself had, and this is what resolves the
shared-descendant problem cleanly: every caller, in or out of any campaign tree, treats
`advect_tracer` as an opaque call needing only call-site marshalling. `step_MOM_tracer_dyn`'s own
plan (deferred, not yet written) will list this call the same way.

No pre-existing audit doc existed for this entry point.

## Hard precondition checks

- **Callers (repo-wide, confirmed by grep):** `MOM.F90:1645` (`step_MOM_tracer_dyn`),
  `MOM.F90` (`step_offline`, via the same call graph found for `tracer_hordiff` below),
  `MOM_offline_main.F90:336,517,558,938,955` (`offline_advection_ale`,
  `offline_advection_layer`). None of these callers are campaign entry points; this plan does not
  touch them — only `advect_tracer`'s own signature and everything below it.
- Shared-descendant check on `advect_tracer`'s own descendants: `advect_x` (430-823) and
  `advect_y` (827-1248) are both **private** (`MOM_tracer_advect`'s `public` list is only
  `advect_tracer`, `tracer_advect_init`, `tracer_advect_end`) — confirmed zero callers outside
  this file. Fully tree-internal, no joint-decision flag needed.
- Not entry points, out of scope: `tracer_advect_init`, `tracer_advect_end` (same
  init/teardown-pair pattern excluded everywhere else this session).

## Step 1d — wrapper case

**Case 3** — plain subroutine, called directly, no existing alias/wrapper.
`advect_tracer` → `advect_tracer_TR`, new `advect_tracer` wrapper. Wrapper never bridged.
`advect_x`/`advect_y` are not entry points, no rename/wrapper of their own.

## External signature (frozen — do not change)

`advect_tracer(h_end, uhtr, vhtr, OBC, dt, G, GV, US, CS, Reg, x_first_in, vol_prev, max_iter_in, update_vol_prev, uhr_out, vhr_out)`
— `MOM_tracer_advect.F90:57-91`. 10 mandatory dummies (`h_end`, `uhtr`, `vhtr`, `OBC`, `dt`, `G`,
`GV`, `US`, `CS`, `Reg`) + 6 optional (`x_first_in` logical, `vol_prev` real 3-D array,
`max_iter_in` integer, `update_vol_prev` logical, `uhr_out`/`vhr_out` real 3-D arrays). The doc
comments call out `vol_prev`/`max_iter_in`/`update_vol_prev`/`uhr_out`/`vhr_out` as "only used in
offline tracer mode" — i.e. these six optionals are exactly the seam between the online
(`step_MOM_tracer_dyn`) and offline (`MOM_offline_main.F90`) call sites.

## Full descendant list

| Subroutine | Direct in-tree callees | Notes |
|---|---|---|
| `advect_x` (430-823) | none | private leaf; called from `advect_tracer` at 4 sites depending on `x_first`/iteration parity |
| `advect_y` (827-1248) | none | private leaf; same calling pattern |

Both leaves take `Tr` (the `tracer_type` array, see below), `hprev`/`uhr` or `vhr`, a
neglect-threshold array, `OBC`, a `domore_u`/`domore_v` logical array, `ntr`, `Idt`, loop-bound
scalars, `G`/`GV`/`US`, and an `advect_schemes` integer array. No calls to anything outside this
file — no EOS, no halo-pass calls of their own (halo passes happen in `advect_tracer`'s own body,
around the leaf calls, via `create_group_pass`/`do_group_pass`).

## `OBC` — grows the union substantially (see `shared_type_unions.md`)

`advect_tracer`/`advect_x`/`advect_y` dereference `OBC` far more deeply than any prior tree,
including a **new field shape not seen before**: `segment(n)%tr_Reg`, a pointer to a full nested
`tracer_registry_type` (itself containing its own `Tr(:)` array of `tracer_type`, with fields
`ntr_index`, `tres`, `OBC_inflow_conc` dereferenced, plus a `ntseg` count) — a registry nested
inside a segment nested inside the array-of-struct `segment(:)`. This compounds the existing
"array-of-custom-derived-type decomposition" open item (`shared_type_unions.md`) rather than
resolving it — flagged, not solved, here.

New top-level fields beyond what's already unioned: `open_u_BCs_exist_globally`,
`open_v_BCs_exist_globally` (siblings of the already-unioned `specified_*_BCs_exist_globally`),
`exterior_OBC_bug` (scalar logical). New per-segment field: `segment(:)%HI%jsd`, `segment(:)%HI%jed`
(plain, non-B-grid — the existing union rows only had `JsdB`/`isd`/`ied`/`IedB`/`JedB`). Already-
unioned fields reused without change: `OBC_pe`, `number_of_segments`, `specified_u_BCs_exist_globally`,
`specified_v_BCs_exist_globally`, `segment(:)%is_E_or_W`, `segment(:)%is_N_or_S`,
`segment(:)%specified`, `segment(:)%direction`, `segment(:)%HI%IsdB`/`IedB`/`JsdB`/`JedB`,
`segnum_u`, `segnum_v` (the last two already known from `vertvisc_coef`'s top-level-array shape).

## `tracer_type`/`tracer_registry_type` (`Reg`/`Tr`) — new type, array-of-struct, hand-authored gap

Not yet in `shared_type_unions.md` — first tree to need it. `tracer_registry_type%Tr` is a
**fixed-size** array (`Tr(MAX_FIELDS_)`, not allocatable) of `tracer_type`, ~40 fields per
element; `advect_tracer`/`advect_x`/`advect_y` touch only 7: `t`, `ad_x`, `ad_y`, `ad2d_x`,
`ad2d_y`, `advection_xy` (all real pointer arrays, 2-D or 3-D), `advect_scheme` (integer scalar).
Same shape as the already-flagged `BTCL_u`/`BTCL_v` (`btstep.md`) and `OBC%segment`
(`shared_type_unions.md`) situation — needs the same per-field, hand-authored container
decomposition; no sibling skill covers array-of-custom-derived-type natively. `tracer_registry_type`
is shared 45 files repo-wide (broader than `OBC`'s 44) — candidate for promotion to
`shared_type_unions.md` once a second tree needs it (expected: `tracer_hordiff`, surveyed
separately, also takes `Reg`).

## `tracer_advect_CS` — bundle by precedent (no fresh Step 3 needed)

6 fields (`MOM_tracer_advect.F90:36-45`, private): `dt` (real), `diag` (nested `diag_ctrl`
pointer), `debug`/`useHuynhStencilBug` (logical), `pass_uhr_vhr_t_hprev` (`group_pass_type` —
halo-exchange infra), `default_advect_scheme` (integer). Same shape as every other private CS
bundled this session — `create_config_bundle_type` on the 4 physics scalars (`dt`, `debug`,
`useHuynhStencilBug`, `default_advect_scheme`), excluding `diag` (nested CS pointer, opaque by
precedent) and `pass_uhr_vhr_t_hprev` (infra type, leave alone by precedent — same treatment as
`pass_var`/`pass_vector` themselves).

## Ungrouping `pass_uhr_vhr_t_hprev` for testing — real ordering dependency (verified against source, this session)

If `create_group_pass`/`do_group_pass` on `CS%pass_uhr_vhr_t_hprev` is ever replaced with individual
`pass_var`/`pass_vector` calls for testing purposes (e.g. to get a capture fixture without needing
the grouped-pass machinery), **the replacement calls must sit where `do_group_pass` currently sits
(line 277), not where the `create_group_pass` registrations sit (lines 180-183).** Verified by
reading the body directly: `uhr`/`vhr`/`hprev` are all registered into the group at 180-183, then
zeroed and refilled with real data at 191-225 (`uhr`/`vhr` from `uhtr`/`vhtr` at 202/205, `hprev`
from the thickness reconstruction or `vol_prev` at 212-222) — all *after* registration but *before*
the deferred exchange at line 277 actually runs. The grouped form is correct because the exchange
is deferred until after that fill; individual `pass_var`/`pass_vector` calls issued immediately at
the registration points would exchange the stale pre-fill (zeroed) state instead. `Reg%Tr(m)%t`
(registered at 183) is not written anywhere in that range — only its sibling diagnostic fields
(`ad_x`/`ad_y`/`advection_xy`/`ad2d_x`/`ad2d_y`) are zeroed at 243-269 — so it's the one array in
this group where placement wouldn't matter, but `uhr`/`vhr`/`hprev` are order-sensitive. This is a
testing-methodology note, not a Phase 2/3 target-classification change — the grouped calls
themselves are still "leave alone by precedent" per the `tracer_advect_CS` section above.

## `create_group_pass`/`do_group_pass` does real message aggregation — AMReX has no equivalent today (verified against source, this session)

Checked the actual FMS implementation (`infra/TIM/mpp/include/mpp_group_update.fh`,
`MPP_DO_GROUP_UPDATE_`) rather than assume: `nsend`/`nrecv` are counts of **neighboring ranks**
(up to 8), not counts of registered fields. All fields registered into one group
(`uhr`/`vhr`/`hprev`/every tracer, here) get packed into one shared buffer per neighbor before a
single `mpp_send`/`mpp_recv` per neighbor — so grouping genuinely reduces MPI message count from
`(fields × neighbors)` to `(neighbors)`, regardless of the registered fields having different grid
staggering (that only affects how the packing step lays out each field's own index range within
the shared buffer, not whether they can be batched).

**AMReX's closest equivalent — `FillBoundary(Vector<MF*> const& mf, ...)` in
`AMReX_FabArrayCommI.H` — exists but does not do the same thing.** Its active implementation
(`#if 1`, the branch that actually compiles) is:
```cpp
for (int i = 0; i < N; ++i) { mf[i]->FillBoundary_nowait(...); }
for (int i = 0; i < N; ++i) { mf[i]->FillBoundary_finish(); }
```
— each `MultiFab` still sends its own separate per-neighbor messages; this only overlaps N
independent exchanges' latency rather than packing them into fewer messages. A genuinely
message-packing implementation (building combined per-neighbor send/recv tag lists spanning
multiple `MultiFab`s) exists in the same file behind `#else` but is dead code in this AMReX
checkout, never compiled. **So an eventual AMReX port of this group has no drop-in equivalent for
the Fortran side's actual message-count reduction** — only the smaller latency-hiding benefit, or
custom-authored packing if true parity with the Fortran communication pattern is wanted. Doesn't
change any Phase 2/3 decision here (the group-pass calls stay external infra, per precedent) — a
note for whoever eventually designs the C++/AMReX replacement for this halo exchange.

## Step 2 — target classification (fixed-rule items)

| Target | Classification | Skill | Notes |
|---|---|---|---|
| `h_end`, `uhtr`, `vhtr` | mandatory raw array dummies | `convert_array_containers` | Standard 3-D real arrays. |
| `vol_prev`, `uhr_out`, `vhr_out` | optional raw array dummies | `convert_present_to_associated`, after containerizing | Offline-mode-only outputs; never leave raw given this tree is scheduled for Phase 3 bridging. |
| `x_first_in`, `max_iter_in`, `update_vol_prev` | optional scalars | `convert_present_to_associated` | logical/integer/logical. |
| `domore_u`, `domore_v` (in `advect_x`/`advect_y`) | mandatory raw **logical** array dummies | `convert_array_containers` | `LogicalArray_t` confirmed to exist in `array_container_lessons` alongside `RealArray_t`/`IntArray_t` (confirmed during `tracer_hordiff`'s survey, which hit the same shape in `find_neutral_surface_positions_discontinuous`/`mark_unstable_cells`) — ordinary classification, no gap. |
| `advect_schemes` (in `advect_x`/`advect_y`) | mandatory raw integer array dummy | `convert_array_containers` | Standard `IntArray_t`. |
| `OBC` | shared, union (grows substantially — see above) | `create_shadow_container_type`, union scope | See `shared_type_unions.md`. |
| `Reg`/`Tr` | shared, new type, array-of-struct | hand-authored decomposition (no sibling skill) | See dedicated section above. |
| `G`, `GV`, `US` | shared grid/scaling types | `convert_array_containers`'s own drop mechanism | Not a separate decision. |
| `CS` (`tracer_advect_CS`) | private, 6 fields | `create_config_bundle_type`, physics-fields-only | See dedicated section above. |

## Phase 2 execution order

1. **TreeRoot split** — `advect_tracer` → `advect_tracer_TR` + wrapper (Step 1d).
2. **`create_shadow_container_type`** — `OBC`'s type definition and `Reg`/`Tr`'s hand-authored
   decomposition are both built once by the combined shared-infrastructure PR
   (`shared_type_unions.md`), not here — the `Reg`/`Tr` decomposition specifically is shared with
   `tracer_hordiff`, authored once, not duplicated across the two plans. This stage's own work is
   just the wrapper-side glue — instantiate each shadow from `advect_tracer_TR`'s own dummies,
   use it, copy back.
3. **`create_config_bundle_type`** — `tracer_advect_CS`, once.
4. **Optional-array containerization** — `vol_prev`, `uhr_out`, `vhr_out`: containerize first
   (item 5 below), then `convert_present_to_associated` (item 8) — never left raw, this tree is
   scheduled for Phase 3.
5. **`convert_array_containers` — downward pass**, root to leaves (`advect_tracer_TR` →
   `advect_x`/`advect_y`). Resolve the logical-array open item before this step touches
   `domore_u`/`domore_v`.
6. **`convert_array_containers` — upward pass**, `G`/`GV`/`US`-drop decisions.
7. **`convert_locals_to_containers`** — `hprev`, `uhr`, `vhr`, `uh_neglect`, `vh_neglect`,
   `local_advect_scheme`, etc., once dummies are stable.
8. **`convert_present_to_associated`** — the 6 optional dummies, ahead of Phase 3.
9. **`hoist_container_marshalling`**, once, at `advect_tracer_TR`.

## Phase 3 wave order

- **Wave 1** (leaves): `advect_x`, `advect_y`.
- **Wave 2 (root, last)**: `advect_tracer_TR`.

Wrapper (`advect_tracer`) never bridged.

## Branch

`claude_advect_tracer_calltree`, created once before Phase 2 Stage 1.
