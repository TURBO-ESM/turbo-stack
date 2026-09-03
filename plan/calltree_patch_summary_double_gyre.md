# Calltree conversion plans — double_gyre patch summary

**Read [`calltree_blocker_summary_double_gyre_unsplit.md`](calltree_blocker_summary_double_gyre_unsplit.md) first.** That file is the base
— every tree, blocker, and status covering the campaign's first validation target,
`double_gyre_unsplit`. This file covers only what's *additional*, needed to extend that base up to
full `double_gyre` (`SPLIT=True`) support. It does not restate anything the base file already
covers, and nothing here is scheduled before the base is done.

A third tier, `benchmark`, builds on top of *this* file (same split dynamics, adds real
thermodynamics and variable mixing) — see
[`calltree_patch_summary_benchmark.md`](calltree_patch_summary_benchmark.md).

**Legend:** ✅ resolved/confirmed clean · 🔴 blocking (external dependency) · 🟡 not blocking, but
real unfinished work

---

## Why this file exists

`double_gyre_unsplit`'s exercised code is a strict subset of `double_gyre`'s (confirmed via the
gcovlens coverage report and a source trace of `MOM.F90`'s `CS%split` branch,
`MOM.F90:1367-1425`) — so everything built and validated against the base gets reused, unchanged,
once this patch lands. The patch is exactly the split-only code the base never touches:

- `btstep` in full (`btstep`/`btcalc`/`bt_mass_source`/`set_dtbt`) — `MOM_barotropic.F90` is never
  entered under `SPLIT=False` (44.6% → 0.0% coverage under `double_gyre_unsplit`).
- `vertvisc_remnant`'s *runtime validation* — the subroutine itself is documented in the base
  file's `vertvisc_family` section (grouped with its siblings `vertvisc`/`vertvisc_coef`, since
  it's a small, 106-line piece of that same tree) and its Phase 2 work can proceed there. What's
  patch-specific is validation only: `vertvisc_remnant` is called exclusively from the split
  dynamics core (`MOM_dynamics_split_RK2.F90`/`MOM_dynamics_split_RK2b.F90`), absent from
  `MOM_dynamics_unsplit_RK2.F90` — so it cannot be capture-fixture-validated against
  `double_gyre_unsplit` at all. Real validation needs `double_gyre` (`SPLIT=True`) specifically.

Neither item is blocked on the other, and neither is blocked by the (now-empty) combined
shared-infrastructure PR — see the base file's "Deferred shared types" section, which covers both.

---

## `btstep` (barotropic solver — `btstep`/`btcalc`/`bt_mass_source`/`set_dtbt`)
Detail: [`btstep.md`](../.claude/calltree-plans/btstep.md)

- ✅ Resolved: `BT_cont_type` wholesale conversion — verified done across all 5 files.
- ✅ **No longer blocked by shared infrastructure.** `ADp` and `OBC` — the two types this tree
  needed from the combined shared-infrastructure PR — were both deferred (confirmed
  PASSED-BUT-INERT under both double_gyre configs; see the base file's deferral section). Zero
  remaining `create_shadow_container_type` dependencies.
- 🔴 Blocking — the one real blocker: `BTCL_u`/`BTCL_v` array-of-struct decomposition — no sibling
  skill exists, affects 11 subroutines.
- 🟡 Narrower blocker: optional-struct-dummy mechanism unresolved, but only affects `set_dtbt`'s
  `BT_cont` param.
- Size: 4465 lines (own tree) / 4947 (all four entry points) — largest of every tree checked,
  campaign-wide.

## `vertvisc_remnant` — validation caveat only (subroutine itself lives in the base file)

Not a separate entry-point plan or blocker list — `vertvisc_remnant` is part of
`vertvisc_family.md` and the base file's `vertvisc_family` section covers its actual Phase 2
status (no shared-infrastructure blocker, same as its siblings). The only patch-specific fact:
its capture-fixture validation requires `double_gyre` (`SPLIT=True`), not `double_gyre_unsplit` —
confirmed via `MOM_dynamics_split_RK2.F90:658,841,843,1128` (call sites) and their absence from
`MOM_dynamics_unsplit_RK2.F90` (grep, no match). If `vertvisc_family`'s Phase 2 runs against the
base config only, `vertvisc_remnant`'s own converted code path stays unexercised until this patch
phase — track that as a validation gap, not a scheduling blocker.

## Shared-type validation caveat, patch-specific

`shared_type_unions.md`'s runtime exercise audit found `MOM_variables.F90` (the closest match to
"shared types" in that file) has a real reachability difference between configs — 27.5% (28/102
lines) under `double_gyre` vs. 15.9% (20/126 lines) under `double_gyre_unsplit`, and the *total*
line count itself differs (102 vs. 126), meaning different derived-type members are reachable
depending on which dynamics core is compiled in. Any shadow fields that get un-deferred later and
are BT-related (`ADp`, anything `BT_cont_type`-adjacent) should be re-verified against actual
`double_gyre` capture output specifically during this patch phase — the base phase
(`double_gyre_unsplit`) can't exercise those fields to sanity-check them.

---

## Practical prerequisite

No `MOM_input`/`MOM_override` for `double_gyre` beyond what's already in
`examples/double_gyre/` is a concern here (unlike the base config, `double_gyre` itself is already
present in this repo) — the base file's action item about sourcing `double_gyre_unsplit`'s config
is the one prerequisite blocking either file's work from being run for real; nothing further is
needed to eventually run this patch's config once the base is built and validated.
